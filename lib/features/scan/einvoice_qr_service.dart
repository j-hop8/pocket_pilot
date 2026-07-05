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

  /// Inserts the scanned invoice, resolving the header and each line item's
  /// category independently (items never inherit the header). Item: its own
  /// history → keyword on the item name. Header: merchant history → keyword on
  /// the merchant name → the most common line-item category. [categories]
  /// resolves keyword keys to ids. Returns the new invoice id. Caller should
  /// check [alreadyExists] first to avoid the UNIQUE-violation on a re-scan.
  Future<String> save(
    ParsedQrInvoice qr, {
    required String? merchantName,
    required List<Category> categories,
  }) async {
    final totalCents = dollarsToCents(qr.totalDollars);
    final catIdByKey = {for (final c in categories) c.key: c.id};

    // Item and merchant history are independent reads — fetch them concurrently.
    final itemNames = qr.items.map((i) => i.name).toList();
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
      for (final it in qr.items)
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
      invoiceNumber: qr.invoiceNumber,
      invoiceDate: qr.date,
      merchantName: merchantName,
      sellerTaxId: qr.sellerTaxId,
      buyerTaxId: qr.buyerTaxId,
      salesAmount: qr.salesAmountDollars > 0
          ? dollarsToCents(qr.salesAmountDollars)
          : null,
      totalAmount: totalCents,
      categoryId: headerCatId,
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
                categoryId: itemCatIds[i],
                sortOrder: i,
              ),
          ]
        // Header-only: one synthetic line equal to the receipt total, taking the
        // header category.
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
