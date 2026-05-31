import '../core/supabase.dart';
import '../models/carrier_config.dart';

/// Reads/writes the single `carrier_config` row (credentials + last-sync state).
/// Created lazily on the first save/sync.
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

  /// Upserts the credentials onto the single config row, returning the saved row.
  Future<CarrierConfig> saveCredentials(CarrierConfig config) async {
    final existing = await getConfig();
    final payload = config.toCredentialsJson();
    final Map<String, dynamic> row;
    if (existing?.id != null) {
      row = await supabase
          .from('carrier_config')
          .update(payload)
          .eq('id', existing!.id!)
          .select()
          .single();
    } else {
      row = await supabase
          .from('carrier_config')
          .insert(payload)
          .select()
          .single();
    }
    return CarrierConfig.fromJson(row);
  }

  /// Records a completed sync: bumps `last_synced_at` and stores [count] as the
  /// number of invoices imported in this run.
  Future<void> recordSync({required int count}) async {
    final existing = await getConfig();
    final now = DateTime.now().toIso8601String();
    final payload = {
      'last_synced_at': now,
      'last_sync_count': count,
      'updated_at': now,
    };
    if (existing?.id != null) {
      await supabase
          .from('carrier_config')
          .update(payload)
          .eq('id', existing!.id!);
    } else {
      await supabase.from('carrier_config').insert(payload);
    }
  }
}
