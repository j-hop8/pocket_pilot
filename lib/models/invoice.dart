import 'package:intl/intl.dart';

import 'invoice_item.dart';

final _dateOnly = DateFormat('yyyy-MM-dd');

/// Invoice header + (when joined) its line items. Money fields are TWD cents.
class Invoice {
  final String? id;
  final String? invoiceNumber;
  final DateTime invoiceDate;
  final String? merchantName;
  final String? sellerTaxId;
  final String? buyerTaxId;
  final int? salesAmount; // cents
  final int totalAmount; // cents
  final String currency;
  final int? categoryId;
  final String source; // 'carrier' | 'qr_scan' | 'ocr' | 'manual'
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
    this.rawPayload,
    this.createdAt,
    this.items = const [],
  });

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
        'raw_payload': rawPayload,
      };
}
