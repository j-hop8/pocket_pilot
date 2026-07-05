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
  /// categorizer, else 'other' — identical to the QR service so OCR and QR
  /// receipts from the same store land in the same place.
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
    final keywordCatId = catIdByKey[keywordKey] ?? catIdByKey['other'];
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
    required int? categoryId,
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
      categoryId: categoryId,
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
