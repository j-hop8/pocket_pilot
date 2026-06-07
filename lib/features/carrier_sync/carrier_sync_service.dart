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
    final fallbackCatId = catIdByKey['other'];

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

      // Keyword categorizer result (current logic) — the fallback for items and
      // merchants with no history.
      final keywordKey = categorizeKey(
        merchant: p.merchantName,
        itemNames: p.items.map((i) => i.name),
      );
      final keywordCatId = catIdByKey[keywordKey] ?? fallbackCatId;

      final invoice = Invoice(
        invoiceNumber: p.invoiceNumber,
        invoiceDate: p.date,
        merchantName: p.merchantName,
        totalAmount: dollarsToCents(p.totalDollars),
        categoryId: resolveInvoiceCategory(
          merchant: p.merchantName,
          merchantHistory: merchantHist,
          keywordFallback: keywordCatId,
        ),
        source: 'carrier',
        rawPayload: {
          if (p.carrierName != null) 'carrier_name': p.carrierName,
          if (p.sellerAddress != null) 'seller_address': p.sellerAddress,
        },
      );
      final items = [
        for (var i = 0; i < p.items.length; i++)
          InvoiceItem(
            name: p.items[i].name,
            quantity: p.items[i].quantity,
            unitPrice: dollarsToCents(p.items[i].unitPrice),
            amount: dollarsToCents(p.items[i].amount),
            // Per item: its own history → merchant history → keyword.
            categoryId: resolveItemCategory(
              itemName: p.items[i].name,
              merchant: p.merchantName,
              itemHistory: itemHist,
              merchantHistory: merchantHist,
              keywordFallback: keywordCatId,
            ),
            sortOrder: i,
          ),
      ];

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
