import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/carrier_repository.dart';
import '../data/category_repository.dart';
import '../data/invoice_repository.dart';
import '../features/carrier_sync/carrier_sync_service.dart';
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

/// All invoices (newest first), with line items joined.
final invoiceListProvider = FutureProvider<List<Invoice>>((ref) {
  return ref.watch(invoiceRepositoryProvider).list();
});

final invoiceByIdProvider =
    FutureProvider.family<Invoice, String>((ref, id) {
  return ref.watch(invoiceRepositoryProvider).getById(id);
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
