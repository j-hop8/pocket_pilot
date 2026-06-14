import '../core/category_resolver.dart';
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

  /// Returns the subset of [numbers] that already exist, so carrier sync can
  /// skip them (invoice_number is UNIQUE — dedup avoids re-importing).
  Future<Set<String>> existingInvoiceNumbers(List<String> numbers) async {
    if (numbers.isEmpty) return {};
    final rows = await supabase
        .from('invoices')
        .select('invoice_number')
        .inFilter('invoice_number', numbers);
    return {
      for (final r in rows)
        if (r['invoice_number'] != null) r['invoice_number'] as String,
    };
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

  /// Changes the invoice's category and cascades it to every line item, so the
  /// whole receipt is recategorized in one tap. Individual items can then be
  /// fine-tuned via [updateItemCategory]. Category is the one field editable on
  /// official (synced) invoices, which must otherwise mirror the government
  /// record.
  Future<void> updateCategory(String id, int? categoryId) async {
    await supabase
        .from('invoices')
        .update({'category_id': categoryId}).eq('id', id);
    await supabase
        .from('invoice_items')
        .update({'category_id': categoryId}).eq('invoice_id', id);
  }

  /// Sets the invoice's merchant name — used when a tax-id lookup that came back
  /// empty at scan time is retried from History. Only the header's name changes;
  /// items and category are untouched.
  Future<void> updateMerchantName(String id, String name) async {
    await supabase
        .from('invoices')
        .update({'merchant_name': name}).eq('id', id);
  }

  /// Overrides a single line item's category — for receipts from one store that
  /// mix categories (e.g. groceries + a household item). Leaves the invoice
  /// header and sibling items untouched.
  Future<void> updateItemCategory(String itemId, int? categoryId) async {
    await supabase
        .from('invoice_items')
        .update({'category_id': categoryId}).eq('id', itemId);
  }

  /// Full update of a user-originated invoice: rewrites the header, then
  /// replaces all line items (delete-all + re-insert keeps it simple and avoids
  /// per-row diffing). The id is taken from [invoice].
  Future<void> update(Invoice invoice, List<InvoiceItem> items) async {
    final id = invoice.id!;
    await supabase.from('invoices').update(invoice.toUpdateJson()).eq('id', id);
    await supabase.from('invoice_items').delete().eq('invoice_id', id);
    if (items.isNotEmpty) {
      await supabase
          .from('invoice_items')
          .insert(items.map((i) => i.toInsertJson(id)).toList());
    }
  }

  Future<void> delete(String id) async {
    // invoice_items rows cascade via the FK ON DELETE CASCADE.
    await supabase.from('invoices').delete().eq('id', id);
  }

  // ── Category history (learning from past categorizations) ────────────────────
  // Auto-categorization consults these before the keyword categorizer: an item or
  // merchant the user has categorized before should keep that category. Keys are
  // normalized (trimmed + lower-cased); the *most recent* past choice wins. RLS
  // scopes every read to the signed-in user.

  /// Most-recent `category_id` the user assigned to a line item with each of
  /// [names]. Item recency comes from the parent invoice's date (items carry no
  /// timestamp of their own). Rows with no category are ignored.
  Future<Map<String, int>> recentCategoryByItemName(List<String> names) async {
    final distinct = _distinctTrimmed(names);
    if (distinct.isEmpty) return {};
    final rows = await supabase
        .from('invoice_items')
        .select('name, category_id, invoices!inner(invoice_date, created_at)')
        .inFilter('name', distinct)
        .not('category_id', 'is', null);
    return foldMostRecentCategory([
      for (final raw in rows)
        _historyRow(raw,
            keyField: 'name',
            recency: raw['invoices'] as Map<String, dynamic>?),
    ]);
  }

  /// Most-recent `category_id` the user assigned to invoices from each of
  /// [merchants]. Rows with no category are ignored.
  Future<Map<String, int>> recentCategoryByMerchant(List<String> merchants) async {
    final distinct = _distinctTrimmed(merchants);
    if (distinct.isEmpty) return {};
    final rows = await supabase
        .from('invoices')
        .select('merchant_name, category_id, invoice_date, created_at')
        .inFilter('merchant_name', distinct)
        .not('category_id', 'is', null);
    return foldMostRecentCategory([
      for (final raw in rows)
        _historyRow(raw, keyField: 'merchant_name', recency: raw),
    ]);
  }

  List<String> _distinctTrimmed(List<String> values) {
    final out = <String>{};
    for (final v in values) {
      final t = v.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out.toList();
  }

  /// Maps a Supabase row into a [HistoryRow]. [recency] carries `invoice_date`
  /// and `created_at` (both ISO strings, so the joined stamp sorts chronologically).
  HistoryRow _historyRow(
    Map<String, dynamic> row, {
    required String keyField,
    required Map<String, dynamic>? recency,
  }) {
    final rec = recency ?? const {};
    return (
      key: row[keyField] as String?,
      categoryId: row['category_id'] as int?,
      stamp: '${rec['invoice_date'] ?? ''}|${rec['created_at'] ?? ''}',
    );
  }
}
