/// Outcome of a carrier CSV import, shown to the user after a sync.
class SyncResult {
  /// New invoices written to the DB.
  final int inserted;

  /// Invoices in the file that were already stored (deduped by invoice number).
  final int skipped;

  /// Line items written (for the [inserted] invoices).
  final int items;

  /// Date range covered by the file (earliest / latest invoice date).
  final DateTime? from;
  final DateTime? to;

  const SyncResult({
    required this.inserted,
    required this.skipped,
    required this.items,
    this.from,
    this.to,
  });

  /// Total invoices found in the file.
  int get total => inserted + skipped;

  bool get isEmpty => total == 0;
}
