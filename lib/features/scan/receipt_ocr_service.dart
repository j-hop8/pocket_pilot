import 'package:pp_core/pp_core.dart';

import '../../core/category_resolver.dart';
import '../../data/invoice_repository.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';
import '../../models/trip.dart';
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
  ///
  /// A receipt is *foreign* whenever its printed currency is not TWD — regardless
  /// of whether it's tied to a [trip]. For a foreign receipt the original amount +
  /// currency are always kept, and when a usable [fxRate] is available it's also
  /// converted so `total_amount` stores TWD cents (keeping every dashboard/budget
  /// aggregation correct). With no rate the foreign amount is stored unconverted
  /// (fx_rate null) — flagged foreign so it stays visible and fixable rather than
  /// silently counted as TWD. [trip] may be null even for a foreign receipt (its
  /// trip is "to be decided"); an already-TWD receipt is unchanged.
  Future<String> save(
    ExtractedReceipt receipt, {
    required String? merchantName,
    required List<Category> categories,
    Trip? trip,
    double? fxRate,
  }) async {
    final isForeign = receipt.currency.toUpperCase() != 'TWD';
    final hasRate = fxRate != null && fxRate > 0;
    final rate = (isForeign && hasRate) ? fxRate : 1.0;

    // Original amount stays in the receipt's own minor units; total_amount is
    // the TWD-converted value (rate == 1 for TWD / an unconverted foreign row).
    final originalCents = dollarsToCents(receipt.totalDollars);
    final totalCents = dollarsToCents(receipt.totalDollars * rate);

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
      merchantNameTranslated: receipt.merchantNameTranslated,
      sellerTaxId: receipt.sellerTaxId,
      salesAmount: (receipt.salesDollars != null && receipt.salesDollars! > 0)
          ? dollarsToCents(receipt.salesDollars! * rate)
          : null,
      totalAmount: totalCents,
      tripId: trip?.id,
      originalAmount: isForeign ? originalCents : null,
      originalCurrency: isForeign ? receipt.currency.toUpperCase() : null,
      fxRate: (isForeign && hasRate) ? rate : null,
      categoryId: headerCatId,
      source: 'ocr',
      kind: receipt.kind,
    );

    final items = receipt.items.isNotEmpty
        ? [
            for (var i = 0; i < receipt.items.length; i++)
              InvoiceItem(
                name: receipt.items[i].name,
                nameTranslated: receipt.items[i].nameTranslated,
                quantity: receipt.items[i].quantity,
                unitPrice:
                    dollarsToCents(receipt.items[i].unitPriceDollars * rate),
                amount: dollarsToCents(receipt.items[i].amountDollars * rate),
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
