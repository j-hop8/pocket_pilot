import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/carrier_repository.dart';
import '../data/category_repository.dart';
import '../data/invoice_repository.dart';
import '../features/carrier_sync/carrier_sync_service.dart';
import '../features/categorize/auto_categorize_service.dart';
import '../features/scan/einvoice_qr_service.dart';
import '../features/scan/merchant_lookup_service.dart';
import '../features/scan/receipt_extraction_service.dart';
import '../features/scan/receipt_ocr_service.dart';
import '../models/carrier_config.dart';
import '../models/category.dart';
import '../models/invoice.dart';

final invoiceRepositoryProvider =
    Provider<InvoiceRepository>((ref) => InvoiceRepository());

final categoryRepositoryProvider =
    Provider<CategoryRepository>((ref) => CategoryRepository());

final carrierRepositoryProvider =
    Provider<CarrierRepository>((ref) => CarrierRepository());

/// Saved carrier credentials + last-sync state (null until first saved).
final carrierConfigProvider = FutureProvider<CarrierConfig?>((ref) {
  return ref.watch(carrierRepositoryProvider).getConfig();
});

final carrierSyncServiceProvider = Provider<CarrierSyncService>((ref) {
  return CarrierSyncService(
    ref.watch(invoiceRepositoryProvider),
    ref.watch(carrierRepositoryProvider),
  );
});

/// Ingests a single scanned e-invoice QR (parse → categorize → dedup → store).
final einvoiceQrServiceProvider = Provider<EinvoiceQrService>((ref) {
  return EinvoiceQrService(ref.watch(invoiceRepositoryProvider));
});

/// Resolves a seller tax id to a merchant name (best-effort, cached).
final merchantLookupServiceProvider = Provider<MerchantLookupService>((ref) {
  return MerchantLookupService();
});

/// Reads a receipt / invoice photo with Gemini (via the extract-receipt Edge
/// Function) into structured fields.
final receiptExtractionServiceProvider =
    Provider<ReceiptExtractionService>((ref) {
  return ReceiptExtractionService();
});

/// Ingests an AI-extracted receipt (categorize → dedup → store as `ocr`).
final receiptOcrServiceProvider = Provider<ReceiptOcrService>((ref) {
  return ReceiptOcrService(ref.watch(invoiceRepositoryProvider));
});

/// AI fallback that categorizes the rows history + the keyword rules left
/// uncategorized (via the categorize Edge Function).
final autoCategorizeServiceProvider = Provider<AutoCategorizeService>((ref) {
  return AutoCategorizeService(ref.watch(invoiceRepositoryProvider));
});

/// All invoices (newest first), with line items joined.
final invoiceListProvider = FutureProvider<List<Invoice>>((ref) {
  return ref.watch(invoiceRepositoryProvider).list();
});

final invoiceByIdProvider =
    FutureProvider.family<Invoice, String>((ref, id) {
  return ref.watch(invoiceRepositoryProvider).getById(id);
});

/// How many invoices still need categorization — a null header, or any line item
/// with no category. Drives the History auto-categorize banner. Derived from
/// [invoiceListProvider] so the O(invoices × items) scan runs only when the list
/// changes, not on every History rebuild (filter taps, view-mode toggles).
final uncategorizedCountProvider = Provider<int>((ref) {
  final invoices = ref.watch(invoiceListProvider).asData?.value ?? const [];
  return invoices
      .where((i) =>
          i.categoryId == null || i.items.any((it) => it.categoryId == null))
      .length;
});

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).list();
});

/// Expense-only categories — the set offered when recording an expense.
final expenseCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final list = await ref.watch(categoriesProvider.future);
  return list.where((c) => !c.isIncome).toList();
});

/// Income-only categories (Salary, Bonus, …) — offered when recording income.
final incomeCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final list = await ref.watch(categoriesProvider.future);
  return list.where((c) => c.isIncome).toList();
});

/// Lookup map id -> Category, for resolving an invoice/item's category_id.
final categoriesByIdProvider = FutureProvider<Map<int, Category>>((ref) async {
  final list = await ref.watch(categoriesProvider.future);
  return {for (final c in list) c.id: c};
});

/// The selected bottom-nav tab index, published by [ShellScaffold] so tab-aware
/// widgets can react to becoming active. The e-invoice scanner watches this to
/// turn the camera on only while the Add tab is showing (iPhone-camera style)
/// and release it the moment the user leaves.
class BottomTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final bottomTabIndexProvider =
    NotifierProvider<BottomTabIndex, int>(BottomTabIndex.new);

/// The month currently shown on the dashboard (first day of month).
class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void set(DateTime month) => state = DateTime(month.year, month.month);
}

final selectedMonthProvider =
    NotifierProvider<SelectedMonth, DateTime>(SelectedMonth.new);
