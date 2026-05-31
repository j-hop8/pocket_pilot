import '../core/supabase.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';

/// The only place invoice rows are read/written. Later capture flows (QR, OCR,
/// carrier sync) reuse [insert] rather than touching Supabase directly.
class InvoiceRepository {
  Future<List<Invoice>> list() async {
    final rows = await supabase
        .from('invoices')
        .select('*, invoice_items(*)')
        .order('invoice_date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map((r) => Invoice.fromJson(r)).toList();
  }

  Future<Invoice> getById(String id) async {
    final row = await supabase
        .from('invoices')
        .select('*, invoice_items(*)')
        .eq('id', id)
        .single();
    return Invoice.fromJson(row);
  }

  /// Inserts the header then its items in one logical operation, returning the
  /// new invoice id.
  Future<String> insert(Invoice invoice, List<InvoiceItem> items) async {
    final inserted = await supabase
        .from('invoices')
        .insert(invoice.toInsertJson())
        .select('id')
        .single();
    final id = inserted['id'] as String;
    if (items.isNotEmpty) {
      await supabase
          .from('invoice_items')
          .insert(items.map((i) => i.toInsertJson(id)).toList());
    }
    return id;
  }

  Future<void> delete(String id) async {
    // invoice_items rows cascade via the FK ON DELETE CASCADE.
    await supabase.from('invoices').delete().eq('id', id);
  }
}
