/// Carrier credentials state + sync settings. Persisted as a single row per user
/// in the `carrier_config` table (one row per user, keyed by `user_id`).
///
/// SECURITY: the portal password is **not** a field here. It is write-only from
/// the client — `CarrierRepository.saveCredentials` sends it to the
/// `set_carrier_credentials` RPC, which stores it in Supabase Vault. Only the
/// server-side carrier-sync Edge Function (service role) can read it back.
class CarrierConfig {
  final int? id;
  final String? phone;
  final DateTime? lastSyncedAt;
  final int lastSyncCount;

  /// Whether the scheduled (interval) sync runs for this user.
  final bool autoSyncEnabled;

  /// How often the scheduled sync runs, in minutes (default 60 = hourly).
  final int syncIntervalMinutes;

  /// Outcome of the most recent sync attempt: `'ok' | 'error' | 'running'`.
  final String? lastSyncStatus;

  /// Error detail when [lastSyncStatus] is `'error'` (null otherwise).
  final String? lastSyncError;

  /// When the most recent sync was attempted (set even if it failed).
  final DateTime? lastSyncAttemptAt;

  const CarrierConfig({
    this.id,
    this.phone,
    this.lastSyncedAt,
    this.lastSyncCount = 0,
    this.autoSyncEnabled = true,
    this.syncIntervalMinutes = 60,
    this.lastSyncStatus,
    this.lastSyncError,
    this.lastSyncAttemptAt,
  });

  bool get hasError => lastSyncStatus == 'error';

  factory CarrierConfig.fromJson(Map<String, dynamic> json) => CarrierConfig(
        id: json['id'] as int?,
        phone: json['phone'] as String?,
        lastSyncedAt: _parseTs(json['last_synced_at']),
        lastSyncCount: (json['last_sync_count'] as int?) ?? 0,
        autoSyncEnabled: (json['auto_sync_enabled'] as bool?) ?? true,
        syncIntervalMinutes: (json['sync_interval_minutes'] as int?) ?? 60,
        lastSyncStatus: json['last_sync_status'] as String?,
        lastSyncError: json['last_sync_error'] as String?,
        lastSyncAttemptAt: _parseTs(json['last_sync_attempt_at']),
      );

  /// Partial upsert payload for the sync settings only — leaves credentials and
  /// last-sync state untouched.
  Map<String, dynamic> toSyncSettingsJson() => {
        'auto_sync_enabled': autoSyncEnabled,
        'sync_interval_minutes': syncIntervalMinutes,
        'updated_at': DateTime.now().toIso8601String(),
      };
}

DateTime? _parseTs(Object? v) =>
    v == null ? null : DateTime.parse(v as String);
