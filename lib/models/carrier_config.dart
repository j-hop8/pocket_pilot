/// Carrier credentials + last-sync state. Persisted as a single row in the
/// `carrier_config` table (single-user Phase 1 app).
///
/// SECURITY: [password] is stored in Supabase under the Phase-1 demo RLS, which
/// grants the anon role full access — acceptable only for this local demo.
class CarrierConfig {
  final int? id;
  final String? phone;
  final String? password;
  final DateTime? lastSyncedAt;
  final int lastSyncCount;

  const CarrierConfig({
    this.id,
    this.phone,
    this.password,
    this.lastSyncedAt,
    this.lastSyncCount = 0,
  });

  factory CarrierConfig.fromJson(Map<String, dynamic> json) => CarrierConfig(
        id: json['id'] as int?,
        phone: json['phone'] as String?,
        password: json['password'] as String?,
        lastSyncedAt: json['last_synced_at'] == null
            ? null
            : DateTime.parse(json['last_synced_at'] as String),
        lastSyncCount: (json['last_sync_count'] as int?) ?? 0,
      );

  Map<String, dynamic> toCredentialsJson() => {
        'phone': _emptyToNull(phone),
        'password': _emptyToNull(password),
        'updated_at': DateTime.now().toIso8601String(),
      };
}

String? _emptyToNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}
