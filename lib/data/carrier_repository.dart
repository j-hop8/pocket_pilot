import 'package:http/http.dart' as http;

import '../core/supabase.dart';
import '../models/carrier_config.dart';
import '../models/sync_result.dart';

/// Base URL of the PocketPilot backend (carrier sync service). Injected at build
/// time via --dart-define BACKEND_URL (e.g. http://localhost:8080 in dev).
const _backendUrl = String.fromEnvironment('BACKEND_URL');

/// Reads/writes the single `carrier_config` row (credentials + sync settings +
/// last-sync state) and triggers an on-demand sync. Created lazily on the first
/// save/sync.
class CarrierRepository {
  Future<CarrierConfig?> getConfig() async {
    final row = await supabase
        .from('carrier_config')
        .select()
        .order('id')
        .limit(1)
        .maybeSingle();
    return row == null ? null : CarrierConfig.fromJson(row);
  }

  /// Stores the portal login. The password goes straight into Supabase Vault via
  /// the `set_carrier_credentials` SECURITY DEFINER RPC (it never lands in a
  /// client-readable column); [phone] is upserted onto the config row.
  Future<void> saveCredentials({
    required String phone,
    required String password,
  }) async {
    await supabase.rpc('set_carrier_credentials', params: {
      'p_phone': phone.trim(),
      'p_password': password,
    });
  }

  /// Erases the stored portal login via the `clear_carrier_credentials`
  /// SECURITY DEFINER RPC: deletes the Vault password secret, clears the phone,
  /// and turns auto-sync off. For users who no longer want their carrier
  /// credentials saved in the app. The config row (and last-sync history) is
  /// kept so the screen falls back to the disconnected state.
  Future<void> clearCredentials() async {
    await supabase.rpc('clear_carrier_credentials');
  }

  /// Persists the auto-sync toggle + interval. Partial upsert touches only those
  /// columns, so credentials and last-sync state are preserved.
  Future<void> saveSyncSettings({
    required bool enabled,
    required int intervalMinutes,
  }) async {
    await supabase.from('carrier_config').upsert({
      'user_id': _userId,
      'auto_sync_enabled': enabled,
      'sync_interval_minutes': intervalMinutes,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  /// Triggers an immediate server-side sync (login → download CSV → ingest) on
  /// the PocketPilot backend for the signed-in user. The backend enqueues the
  /// job and returns 202 right away (scraping can take a while), so we then poll
  /// `carrier_config` until the job leaves the `running` state and report the
  /// outcome. Only the inserted count is known client-side (the worker records
  /// `last_sync_count`); a per-run skipped/items breakdown isn't persisted.
  Future<SyncResult> syncNow() async {
    if (_backendUrl.isEmpty) {
      throw StateError('BACKEND_URL is not set (pass it via --dart-define).');
    }
    final token = supabase.auth.currentSession?.accessToken;
    if (token == null) {
      throw StateError('Not signed in.');
    }

    final res = await http.post(
      Uri.parse('$_backendUrl/sync/now'),
      // No body to send — the user is derived from the Bearer token. Declaring a
      // JSON content-type with an empty body trips Fastify's parser (400).
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    // The backend rate-limits manual syncs per user (cooldown / already running).
    if (res.statusCode == 429) {
      final retry = int.tryParse(res.headers['retry-after'] ?? '') ?? 0;
      throw StateError(
        retry > 0 ? '同步太頻繁，請於 $retry 秒後再試。' : '同步太頻繁，請稍後再試。',
      );
    }
    if (res.statusCode != 202 && res.statusCode != 200) {
      throw StateError('Sync request failed (${res.statusCode}): ${res.body}');
    }

    // Poll for completion. The server flips status to 'running' before returning,
    // so we wait for it to become 'ok'/'error' (or time out).
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final config = await getConfig();
      final status = config?.lastSyncStatus;
      if (status == 'error') {
        throw StateError(config?.lastSyncError ?? 'Sync failed.');
      }
      if (status == 'ok') {
        return SyncResult(
          inserted: config?.lastSyncCount ?? 0,
          skipped: 0,
          items: 0,
        );
      }
    }
    throw StateError('Sync timed out — still running on the server.');
  }

  /// Records a completed sync: bumps `last_synced_at` and stores [count] as the
  /// number of invoices imported in this run. Upsert touches only these columns,
  /// so saved credentials are preserved. (Used by the CSV-import fallback path.)
  Future<void> recordSync({required int count}) async {
    final now = DateTime.now().toIso8601String();
    await supabase.from('carrier_config').upsert({
      'user_id': _userId,
      'last_synced_at': now,
      'last_sync_count': count,
      'last_sync_status': 'ok',
      'last_sync_error': null,
      'last_sync_attempt_at': now,
      'updated_at': now,
    }, onConflict: 'user_id');
  }

  String get _userId => supabase.auth.currentUser!.id;
}
