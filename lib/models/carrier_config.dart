/// Carrier credentials + last-sync state. Persisted as a single row in the
/// `carrier_config` table (single-user Phase 1 app).
///
/// SECURITY: [password] is stored in Supabase under the Phase-1 demo RLS, which
/// grants the anon role full access — acceptable only for this local demo. See
/// the `carrier_config` table comment in the init migration for the production
/// hardening checklist.
class CarrierConfig {
  final int? id;
  final String? phone; // 手機號碼 (portal login)
  final String? password; // 密碼 (portal login)
  final String? carrierId; // 手機條碼載具 /XXXXXXX
  final String? cardVerificationCode; // 條碼驗證碼 (for the official API)
  final DateTime? lastSyncedAt;
  final int lastSyncCount;

  const CarrierConfig({
    this.id,
    this.phone,
    this.password,
    this.carrierId,
    this.cardVerificationCode,
    this.lastSyncedAt,
    this.lastSyncCount = 0,
  });

  factory CarrierConfig.fromJson(Map<String, dynamic> json) => CarrierConfig(
        id: json['id'] as int?,
        phone: json['phone'] as String?,
        password: json['password'] as String?,
        carrierId: json['carrier_id'] as String?,
        cardVerificationCode: json['card_verification_code'] as String?,
        lastSyncedAt: json['last_synced_at'] == null
            ? null
            : DateTime.parse(json['last_synced_at'] as String),
        lastSyncCount: (json['last_sync_count'] as int?) ?? 0,
      );

  /// Credential fields only (not sync state). Used when the user saves the form.
  Map<String, dynamic> toCredentialsJson() => {
        'phone': _emptyToNull(phone),
        'password': _emptyToNull(password),
        'carrier_id': _emptyToNull(carrierId),
        'card_verification_code': _emptyToNull(cardVerificationCode),
        'updated_at': DateTime.now().toIso8601String(),
      };
}

String? _emptyToNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}
