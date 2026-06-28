import 'package:pp_core/pp_core.dart';

import '../../core/category_resolver.dart';
import '../../data/invoice_repository.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';
import 'extracted_receipt.dart';

/// Turns one AI-extracted receipt into a stored invoice — the OCR counterpart of
/// [EinvoiceQrService]. Categorisation and dedup behave identically to the QR
/// path (same keyword categorizer + merchant-history resolver), but the saved
/// row is `source='ocr'` so it stays fully editable (the model can misread).
class ReceiptOcrService {
  ReceiptOcrService(this._invoices);

  final InvoiceRepository _invoices;

  /// Whether [invoiceNumber] is already stored. Only relevant when the model
  /// read an e-invoice number off the photo — shares the `invoice_number`
  /// UNIQUE constraint with the QR + carrier records, so an OCR of an already-
  /// synced e-invoice is caught as a duplicate instead of UNIQUE-violating.
  Future<bool> alreadyExists(String invoiceNumber) async =>
      (await _invoices.existingInvoiceNumbers([invoiceNumber])).isNotEmpty;

  /// Best-guess category: the user's merchant history, else the keyword
  /// categorizer, else null (uncategorized) — identical to the QR service so OCR
  /// and QR receipts from the same store land in the same place.
  Future<int?> defaultCategoryId(
    ExtractedReceipt receipt, {
    required String? merchantName,
    required List<Category> categories,
  }) async {
    final catIdByKey = {for (final c in categories) c.key: c.id};
    final keywordKey = categorizeKey(
      merchant: merchantName,
      itemNames: receipt.items.map((i) => i.name),
    );
    final keywordCatId = keywordKey == null ? null : catIdByKey[keywordKey];
    final merchantHist = merchantName == null
        ? const <String, int>{}
        : await _invoices.recentCategoryByMerchant([merchantName]);
    return resolveInvoiceCategory(
      merchant: merchantName,
      merchantHistory: merchantHist,
      keywordFallback: keywordCatId,
    );
  }

  /// Inserts the extracted receipt with the chosen [categoryId] (cascaded to
  /// every line item). Returns the new invoice id.
  Future<String> save(
    ExtractedReceipt receipt, {
    required String? merchantName,
    required int? categoryId,
  }) async {
    final totalCents = dollarsToCents(receipt.totalDollars);

    final invoice = Invoice(
      invoiceNumber: receipt.invoiceNumber,
      invoiceDate: receipt.date,
      merchantName: merchantName,
      sellerTaxId: receipt.sellerTaxId,
      salesAmount: (receipt.salesDollars != null && receipt.salesDollars! > 0)
          ? dollarsToCents(receipt.salesDollars!)
          : null,
      totalAmount: totalCents,
      categoryId: categoryId,
      source: 'ocr',
      kind: receipt.kind,
    );

    final items = receipt.items.isNotEmpty
        ? [
            for (var i = 0; i < receipt.items.length; i++)
              InvoiceItem(
                name: receipt.items[i].name,
                quantity: receipt.items[i].quantity,
                unitPrice: dollarsToCents(receipt.items[i].unitPriceDollars),
                amount: dollarsToCents(receipt.items[i].amountDollars),
                categoryId: categoryId,
                sortOrder: i,
              ),
          ]
        // No legible line items: one synthetic line equal to the receipt total,
        // mirroring the QR service's header-only fallback.
        : [
            InvoiceItem(
              name: merchantName ?? '消費',
              quantity: 1,
              unitPrice: totalCents,
              amount: totalCents,
              categoryId: categoryId,
            ),
          ];

    return _invoices.insert(invoice, items);
  }
}
