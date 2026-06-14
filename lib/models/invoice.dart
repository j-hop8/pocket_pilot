import 'package:intl/intl.dart';

import 'invoice_item.dart';

final _dateOnly = DateFormat('yyyy-MM-dd');

/// Invoice header + (when joined) its line items. Money fields are TWD cents.
class Invoice {
  final String? id;
  final String? invoiceNumber;
  final DateTime invoiceDate;
  final String? merchantName;
  final String? sellerTaxId; // 賣方統一編號 (8 digits)
  final String? buyerTaxId; // 買方統一編號 (8 digits), null for B2C
  final int? salesAmount; // cents
  final int totalAmount; // cents
  final String currency;
  final int? categoryId;
  final String source; // 'carrier' | 'qr_scan' | 'ocr' | 'manual'
  final String kind; // 'expense' | 'income'
  final Map<String, dynamic>? rawPayload;
  final DateTime? createdAt;
  final List<InvoiceItem> items;

  const Invoice({
    this.id,
    this.invoiceNumber,
    required this.invoiceDate,
    this.merchantName,
    this.sellerTaxId,
    this.buyerTaxId,
    this.salesAmount,
    required this.totalAmount,
    this.currency = 'TWD',
    this.categoryId,
    required this.source,
    this.kind = 'expense',
    this.rawPayload,
    this.createdAt,
    this.items = const [],
  });

  /// Whether this record is money coming in (income) rather than going out
  /// (expense). Amounts are stored positive regardless; the sign is applied by
  /// the UI/aggregation based on this.
  bool get isIncome => kind == 'income';

  /// True when the row mirrors an official government e-invoice — pulled by
  /// carrier sync or scanned from an e-invoice QR. Its merchant/date/amount/items
  /// must match the official record, so the user may only change the category;
  /// the rest is read-only and the invoice can't be deleted.
  bool get isOfficial => source == 'carrier' || source == 'qr_scan';

  /// Whether every field (not just the category) may be edited. Only true for
  /// user-originated rows (manual entry, OCR best-effort) which may need fixing.
  bool get canEditDetails => !isOfficial;

  /// Whether the user may delete this invoice. Official rows would just re-sync,
  /// so deletion is reserved for user-originated rows.
  bool get canDelete => !isOfficial;

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['invoice_items'] as List<dynamic>?) ?? const [];
    final items = rawItems
        .map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Invoice(
      id: json['id'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      invoiceDate: DateTime.parse(json['invoice_date'] as String),
      merchantName: json['merchant_name'] as String?,
      sellerTaxId: json['seller_tax_id'] as String?,
      buyerTaxId: json['buyer_tax_id'] as String?,
      salesAmount: json['sales_amount'] as int?,
      totalAmount: json['total_amount'] as int,
      currency: (json['currency'] as String?) ?? 'TWD',
      categoryId: json['category_id'] as int?,
      source: json['source'] as String,
      kind: json['kind'] as String? ?? 'expense',
      rawPayload: json['raw_payload'] as Map<String, dynamic>?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      items: items,
    );
  }

  /// For insert. `id`, `created_at`, `updated_at` are DB-managed.
  Map<String, dynamic> toInsertJson() => {
        'invoice_number': invoiceNumber,
        'invoice_date': _dateOnly.format(invoiceDate),
        'merchant_name': merchantName,
        'seller_tax_id': sellerTaxId,
        'buyer_tax_id': buyerTaxId,
        'sales_amount': salesAmount,
        'total_amount': totalAmount,
        'currency': currency,
        'category_id': categoryId,
        'source': source,
        'kind': kind,
        'raw_payload': rawPayload,
      };

  /// For a full update of the header. `source`/`raw_payload`/`created_at` are
  /// left untouched; `updated_at` is DB-managed (trigger).
  Map<String, dynamic> toUpdateJson() => {
        'invoice_number': invoiceNumber,
        'invoice_date': _dateOnly.format(invoiceDate),
        'merchant_name': merchantName,
        'sales_amount': salesAmount,
        'total_amount': totalAmount,
        'currency': currency,
        'category_id': categoryId,
        'kind': kind,
      };
}
