import '../../core/categorizer.dart';
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

      final key = categorizeKey(
        merchant: p.merchantName,
        itemNames: p.items.map((i) => i.name),
      );
      final categoryId = catIdByKey[key] ?? fallbackCatId;

      final invoice = Invoice(
        invoiceNumber: p.invoiceNumber,
        invoiceDate: p.date,
        merchantName: p.merchantName,
        totalAmount: dollarsToCents(p.totalDollars),
        categoryId: categoryId,
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
            categoryId: categoryId,
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
