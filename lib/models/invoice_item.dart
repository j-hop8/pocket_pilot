/// A single line item. Money fields are INTEGER TWD cents.
class InvoiceItem {
  final String? id;
  final String? invoiceId;
  final String name;
  final num quantity;
  final int? unitPrice; // cents
  final int amount; // cents
  final int? categoryId;
  final int sortOrder;

  const InvoiceItem({
    this.id,
    this.invoiceId,
    required this.name,
    this.quantity = 1,
    this.unitPrice,
    required this.amount,
    this.categoryId,
    this.sortOrder = 0,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> json) => InvoiceItem(
        id: json['id'] as String?,
        invoiceId: json['invoice_id'] as String?,
        name: json['name'] as String,
        quantity: (json['quantity'] as num?) ?? 1,
        unitPrice: json['unit_price'] as int?,
        amount: json['amount'] as int,
        categoryId: json['category_id'] as int?,
        sortOrder: (json['sort_order'] as int?) ?? 0,
      );

  /// For insert. `id` is DB-generated; `invoiceId` is supplied by the repository
  /// after the parent invoice row exists.
  Map<String, dynamic> toInsertJson(String invoiceId) => {
        'invoice_id': invoiceId,
        // Trim on write so the stored value matches the trimmed keys every
        // name-based lookup uses (history recency + the auto-categorize
        // write-back filter by `name`); an untrimmed row would silently never
        // match. See InvoiceRepository._applyCategoryByName.
        'name': name.trim(),
        'quantity': quantity,
        'unit_price': unitPrice,
        'amount': amount,
        'category_id': categoryId,
        'sort_order': sortOrder,
      };
}
