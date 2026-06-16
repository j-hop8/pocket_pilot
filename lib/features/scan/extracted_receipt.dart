/// The structured data Gemini reads off a receipt / invoice photo (the
/// `extract-receipt` Edge Function response). Mirrors the role `ParsedQrInvoice`
/// plays for the QR path: a source-specific value object the ingest service
/// turns into an [Invoice]. Money fields are whole NT$ **dollars** (the QR/CSV
/// convention) — `dollarsToCents` is applied on save.
class ExtractedReceipt {
  final String? merchantName;
  final DateTime date;
  final int totalDollars;
  final int? salesDollars;
  final String? sellerTaxId;

  /// The e-invoice number if the model could read one off a 電子發票 (two letters
  /// + 8 digits). null for an ordinary receipt — used only for opportunistic
  /// dedup against the QR/carrier records.
  final String? invoiceNumber;

  /// 'expense' (money out) or 'income' (money in).
  final String kind;
  final List<ExtractedItem> items;

  const ExtractedReceipt({
    this.merchantName,
    required this.date,
    required this.totalDollars,
    this.salesDollars,
    this.sellerTaxId,
    this.invoiceNumber,
    this.kind = 'expense',
    this.items = const [],
  });

  factory ExtractedReceipt.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>?) ?? const [];
    return ExtractedReceipt(
      merchantName: _str(json['merchantName']),
      date: _parseDate(json['date']),
      totalDollars: _int(json['total']) ?? 0,
      salesDollars: _int(json['salesAmount']),
      sellerTaxId: _taxId(json['sellerTaxId']),
      invoiceNumber: _invoiceNumber(json['invoiceNumber']),
      kind: json['kind'] == 'income' ? 'income' : 'expense',
      items: [
        for (final raw in items)
          if (raw is Map<String, dynamic>) ExtractedItem.fromJson(raw),
      ],
    );
  }
}

/// One line item, amounts in whole dollars.
class ExtractedItem {
  final String name;
  final num quantity;
  final int unitPriceDollars;
  final int amountDollars;

  const ExtractedItem({
    required this.name,
    this.quantity = 1,
    required this.unitPriceDollars,
    required this.amountDollars,
  });

  factory ExtractedItem.fromJson(Map<String, dynamic> json) {
    final amount = _int(json['amount']) ?? 0;
    return ExtractedItem(
      name: _str(json['name']) ?? '',
      quantity: (json['quantity'] as num?) ?? 1,
      unitPriceDollars: _int(json['unitPrice']) ?? amount,
      amountDollars: amount,
    );
  }
}

String? _str(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _int(Object? value) {
  if (value is num) return value.round();
  if (value is String) {
    final n = num.tryParse(value.replaceAll(RegExp(r'[,\s]'), ''));
    return n?.round();
  }
  return null;
}

/// The seller tax id, kept only if it's the expected 8 digits.
String? _taxId(Object? value) {
  final id = _str(value)?.replaceAll(RegExp(r'\D'), '');
  return (id != null && id.length == 8) ? id : null;
}

/// The e-invoice number, normalised to the canonical 2-letters-+-8-digits form
/// (the `invoice_number` column is VARCHAR(10)). Anything else → null, so a
/// misread never collides on the UNIQUE constraint or overflows the column.
String? _invoiceNumber(Object? value) {
  final raw = _str(value)?.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (raw == null) return null;
  return RegExp(r'^[A-Z]{2}\d{8}$').hasMatch(raw) ? raw : null;
}

/// Parses an ISO `yyyy-MM-dd` date, falling back to today when the model
/// couldn't read one (better an editable wrong-day record than a failed scan).
DateTime _parseDate(Object? value) {
  final s = _str(value);
  if (s != null) {
    final parsed = DateTime.tryParse(s);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
  }
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}
