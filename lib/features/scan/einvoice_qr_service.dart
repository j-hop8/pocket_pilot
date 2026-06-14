import 'package:pp_core/pp_core.dart';

import '../../core/category_resolver.dart';
import '../../data/invoice_repository.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';

/// Turns a single scanned [ParsedQrInvoice] into a stored invoice, mirroring the
/// carrier CSV ingest (`CarrierSyncService`) so categorization and dedup behave
/// identically — just for one receipt at a time.
class EinvoiceQrService {
  EinvoiceQrService(this._invoices);

  final InvoiceRepository _invoices;

  /// Whether this invoice number is already stored (QR + carrier sync share the
  /// `invoice_number` UNIQUE constraint, so a scan can't duplicate a sync).
  Future<bool> alreadyExists(String invoiceNumber) async =>
      (await _invoices.existingInvoiceNumbers([invoiceNumber])).isNotEmpty;

  /// Best-guess category for the receipt: the user's merchant history, else the
  /// keyword categorizer, else 'other'. Used to pre-select the review picker.
  Future<int?> defaultCategoryId(
    ParsedQrInvoice qr, {
    required String? merchantName,
    required List<Category> categories,
  }) async {
    final catIdByKey = {for (final c in categories) c.key: c.id};
    final keywordKey = categorizeKey(
      merchant: merchantName,
      itemNames: qr.items.map((i) => i.name),
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

  /// Inserts the scanned invoice with the chosen [categoryId] (cascaded to every
  /// line item). Returns the new invoice id. Caller should check
  /// [alreadyExists] first to avoid the UNIQUE-violation on a re-scan.
  Future<String> save(
    ParsedQrInvoice qr, {
    required String? merchantName,
    required int? categoryId,
  }) async {
    final totalCents = dollarsToCents(qr.totalDollars);

    final invoice = Invoice(
      invoiceNumber: qr.invoiceNumber,
      invoiceDate: qr.date,
      merchantName: merchantName,
      sellerTaxId: qr.sellerTaxId,
      buyerTaxId: qr.buyerTaxId,
      salesAmount: qr.salesAmountDollars > 0
          ? dollarsToCents(qr.salesAmountDollars)
          : null,
      totalAmount: totalCents,
      categoryId: categoryId,
      source: 'qr_scan',
      rawPayload: {
        'random_code': qr.randomCode,
        if (qr.sellerCustom != null) 'seller_custom': qr.sellerCustom,
        'raw_left': qr.rawLeft,
        if (qr.rawRight != null) 'raw_right': qr.rawRight,
      },
    );

    final items = qr.hasFullItems
        ? [
            for (var i = 0; i < qr.items.length; i++)
              InvoiceItem(
                name: qr.items[i].name,
                quantity: qr.items[i].quantity,
                unitPrice: dollarsToCents(qr.items[i].unitPrice),
                amount: dollarsToCents(qr.items[i].amount),
                categoryId: categoryId,
                sortOrder: i,
              ),
          ]
        // Header-only: one synthetic line equal to the receipt total.
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
