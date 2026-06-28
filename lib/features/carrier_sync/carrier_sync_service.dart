import '../../core/categorizer.dart';
import '../../core/category_resolver.dart';
import '../../core/formatters.dart';
import '../../data/carrier_repository.dart';
import '../../data/invoice_repository.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';
import '../../models/sync_result.dart';
import 'einvoice_csv_parser.dart';

/// Ingests a MOF carrier CSV: parse → auto-categorize → dedupe → store, then
/// records the sync on `carrier_config`.
class CarrierSyncService {
  CarrierSyncService(this._invoices, this._carrier);

  final InvoiceRepository _invoices;
  final CarrierRepository _carrier;

  /// Imports [csvContent]. [categories] resolves category keys to ids. Invoices
  /// already present (by invoice number) are skipped, so re-importing the same
  /// file is a no-op.
  Future<SyncResult> importCsv(
    String csvContent,
    List<Category> categories,
  ) async {
    final parsed = parseEinvoiceCsv(csvContent);
    if (parsed.isEmpty) {
      return const SyncResult(inserted: 0, skipped: 0, items: 0);
    }

    final catIdByKey = {for (final c in categories) c.key: c.id};

    // Learn from the user's own history first: an item or merchant they've
    // categorized before keeps that category (item wins over merchant), and only
    // when there's no history do we fall back to the keyword categorizer below.
    final itemHist = await _invoices.recentCategoryByItemName(
        [for (final p in parsed) for (final i in p.items) i.name]);
    final merchantHist = await _invoices.recentCategoryByMerchant(
        [for (final p in parsed) if (p.merchantName != null) p.merchantName!]);

    final existing = await _invoices
        .existingInvoiceNumbers([for (final p in parsed) p.invoiceNumber]);

    var inserted = 0;
    var itemCount = 0;
    DateTime? from;
    DateTime? to;

    for (final p in parsed) {
      from = (from == null || p.date.isBefore(from)) ? p.date : from;
      to = (to == null || p.date.isAfter(to)) ? p.date : to;

      if (existing.contains(p.invoiceNumber)) continue;

      // Resolve items first (each from its own history → the keyword rules on
      // its own name), so the header can fall back to their most common category.
      int? itemKeywordCatId(String name) {
        final key = categorizeKey(itemNames: [name]);
        return key == null ? null : catIdByKey[key];
      }

      final items = [
        for (var i = 0; i < p.items.length; i++)
          InvoiceItem(
            name: p.items[i].name,
            quantity: p.items[i].quantity,
            unitPrice: dollarsToCents(p.items[i].unitPrice),
            amount: dollarsToCents(p.items[i].amount),
            // Per item: its own history → keyword on the item name.
            categoryId: resolveItemCategory(
              itemName: p.items[i].name,
              itemHistory: itemHist,
              keywordFallback: itemKeywordCatId(p.items[i].name),
            ),
            sortOrder: i,
          ),
      ];

      // Header: merchant history → keyword on the merchant name → item mode.
      final merchantKey = categorizeKey(merchant: p.merchantName);
      final merchantKeywordCatId =
          merchantKey == null ? null : catIdByKey[merchantKey];

      final invoice = Invoice(
        invoiceNumber: p.invoiceNumber,
        invoiceDate: p.date,
        merchantName: p.merchantName,
        totalAmount: dollarsToCents(p.totalDollars),
        categoryId: resolveInvoiceCategory(
          merchant: p.merchantName,
          merchantHistory: merchantHist,
          keywordFallback: merchantKeywordCatId,
          itemCategoryIds: items.map((i) => i.categoryId),
        ),
        source: 'carrier',
        rawPayload: {
          if (p.carrierName != null) 'carrier_name': p.carrierName,
          if (p.sellerAddress != null) 'seller_address': p.sellerAddress,
        },
      );

      await _invoices.insert(invoice, items);
      inserted++;
      itemCount += items.length;
    }

    await _carrier.recordSync(count: inserted);

    return SyncResult(
      inserted: inserted,
      skipped: parsed.length - inserted,
      items: itemCount,
      from: from,
      to: to,
    );
  }
}
