import 'package:pp_core/pp_core.dart';

import '../../core/category_resolver.dart';
import '../../data/invoice_repository.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';
import 'extracted_receipt.dart';

/// Turns one AI-extracted receipt into a stored invoice — the OCR counterpart of
/// [EinvoiceQrService]. Categorisation and dedup behave identically to the QR
/// path (item history + keyword on the item name per line; merchant history,
/// merchant keyword then the item mode for the header), but the saved row is
/// `source='ocr'` so it stays fully editable (the model can misread).
class ReceiptOcrService {
  ReceiptOcrService(this._invoices);

  final InvoiceRepository _invoices;

  /// Whether [invoiceNumber] is already stored. Only relevant when the model
  /// read an e-invoice number off the photo — shares the `invoice_number`
  /// UNIQUE constraint with the QR + carrier records, so an OCR of an already-
  /// synced e-invoice is caught as a duplicate instead of UNIQUE-violating.
  Future<bool> alreadyExists(String invoiceNumber) async =>
      (await _invoices.existingInvoiceNumbers([invoiceNumber])).isNotEmpty;

  /// Inserts the extracted receipt, resolving the header and each line item's
  /// category independently (items never inherit the header). Item: its own
  /// history → keyword on the item name. Header: merchant history → keyword on
  /// the merchant name → the most common line-item category. [categories]
  /// resolves keyword keys to ids. Returns the new invoice id.
  Future<String> save(
    ExtractedReceipt receipt, {
    required String? merchantName,
    required List<Category> categories,
  }) async {
    final totalCents = dollarsToCents(receipt.totalDollars);
    final catIdByKey = {for (final c in categories) c.key: c.id};

    // Item and merchant history are independent reads — fetch them concurrently.
    final itemNames = receipt.items.map((i) => i.name).toList();
    final histories = await Future.wait([
      itemNames.isEmpty
          ? Future.value(const <String, int>{})
          : _invoices.recentCategoryByItemName(itemNames),
      merchantName == null
          ? Future.value(const <String, int>{})
          : _invoices.recentCategoryByMerchant([merchantName]),
    ]);
    final itemHist = histories[0];
    final merchantHist = histories[1];

    // Per item: its own history → keyword on the item name. Resolved first so
    // the header can fall back to their most common category.
    final itemCatIds = [
      for (final it in receipt.items)
        resolveItemCategory(
          itemName: it.name,
          itemHistory: itemHist,
          keywordFallback: catIdByKey[categorizeKey(itemNames: [it.name])],
        ),
    ];

    // Header: merchant history → keyword on the merchant name → item mode.
    final headerCatId = resolveInvoiceCategory(
      merchant: merchantName,
      merchantHistory: merchantHist,
      keywordFallback: catIdByKey[categorizeKey(merchant: merchantName)],
      itemCategoryIds: itemCatIds,
    );

    final invoice = Invoice(
      invoiceNumber: receipt.invoiceNumber,
      invoiceDate: receipt.date,
      merchantName: merchantName,
      sellerTaxId: receipt.sellerTaxId,
      salesAmount: (receipt.salesDollars != null && receipt.salesDollars! > 0)
          ? dollarsToCents(receipt.salesDollars!)
          : null,
      totalAmount: totalCents,
      categoryId: headerCatId,
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
                categoryId: itemCatIds[i],
                sortOrder: i,
              ),
          ]
        // No legible line items: one synthetic line equal to the receipt total,
        // taking the header category — mirroring the QR header-only fallback.
        : [
            InvoiceItem(
              name: merchantName ?? '消費',
              quantity: 1,
              unitPrice: totalCents,
              amount: totalCents,
              categoryId: headerCatId,
            ),
          ];

    return _invoices.insert(invoice, items);
  }
}
