import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/categories.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../models/trip.dart';
import '../../widgets/category_badge.dart';
import '../../widgets/source_icon.dart';
import '../travel/countries.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s            = ref.watch(stringsProvider);
    final invoiceAsync = ref.watch(invoiceByIdProvider(invoiceId));
    final catMap       = ref.watch(categoriesByIdProvider).asData?.value ?? const {};
    final categories   = ref.watch(categoriesProvider).asData?.value ?? const [];
    final trips        = ref.watch(tripsProvider).asData?.value ?? const <Trip>[];

    return invoiceAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(s.invoiceTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(s.invoiceTitle)),
        body: Center(child: Text(s.failedToLoadError(e))),
      ),
      data: (inv) {
        final cat = inv.categoryId == null ? null : catMap[inv.categoryId];
        Trip? currentTrip;
        for (final t in trips) {
          if (t.id == inv.tripId) {
            currentTrip = t;
            break;
          }
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(s.invoiceTitle),
            actions: [
              if (inv.canEditDetails)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: s.edit,
                  onPressed: () => context.push('/invoice/$invoiceId/edit', extra: inv),
                ),
              if (inv.canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: s.delete,
                  onPressed: () => _confirmDelete(context, ref, s),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SourceIcon(source: inv.source, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inv.merchantNameTranslated?.isNotEmpty == true
                                      ? inv.merchantNameTranslated!
                                      : (inv.merchantName?.isNotEmpty == true
                                          ? inv.merchantName!
                                          : s.unknownMerchantLong),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (inv.merchantNameTranslated?.isNotEmpty == true &&
                                    inv.merchantName?.isNotEmpty == true &&
                                    inv.merchantName != inv.merchantNameTranslated)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      inv.merchantName!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(s.datePrefix(formatDate(inv.invoiceDate))),
                      if (inv.invoiceNumber != null)
                        Text('${s.invoiceNoPrefix}${inv.invoiceNumber}'),
                      const SizedBox(height: 8),
                      // Category is editable on every invoice (the one field an
                      // official, synced invoice allows changing).
                      Row(
                        children: [
                          CategoryBadge(
                            category: cat,
                            onTap: () => _changeCategory(
                                context, ref, inv, categories, s),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.edit, size: 14, color: Colors.grey.shade500),
                        ],
                      ),
                      if (inv.isOfficial) ...[
                        const SizedBox(height: 10),
                        Text(
                          s.officialLockedHint,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                      // Which trip this belongs to — shown for foreign receipts
                      // (and any already tied to a trip). Editable, so a wrong
                      // bucket or an undecided receipt can be assigned by hand.
                      if (inv.canEditDetails &&
                          (inv.isForeign || inv.tripId != null)) ...[
                        const SizedBox(height: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () =>
                              _changeTrip(context, ref, inv, trips, s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.luggage_outlined,
                                    size: 18, color: Colors.grey.shade600),
                                const SizedBox(width: 8),
                                Text('${s.tripFieldLabel}: ',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Expanded(
                                  child: Text(
                                    currentTrip != null
                                        ? '${countryByCode(currentTrip.countryCode)?.flag ?? ''} ${currentTrip.name}'
                                            .trim()
                                        : s.notAssignedTrip,
                                    style: TextStyle(
                                      color: currentTrip != null
                                          ? null
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                                Icon(Icons.edit,
                                    size: 14, color: Colors.grey.shade500),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const Divider(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.totalLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${inv.isIncome ? '+' : '−'}${formatTwd(inv.totalAmount)}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: inv.isIncome ? PocketColors.pine : null,
                                ),
                              ),
                              if (inv.isForeign && inv.originalAmount != null)
                                Text(
                                  formatForeign(
                                      inv.originalAmount!, inv.originalCurrency!),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  s.itemsLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (inv.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.noLineItems),
                )
              else
                ...inv.items.map((item) {
                  final itemCat =
                      item.categoryId == null ? null : catMap[item.categoryId];
                  final unit = item.unitPrice;
                  final showOriginalItem =
                      item.nameTranslated?.isNotEmpty == true &&
                          item.nameTranslated != item.name;
                  return Card(
                    child: ListTile(
                      title: Text(item.nameTranslated?.isNotEmpty == true
                          ? item.nameTranslated!
                          : item.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showOriginalItem)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Text(s.qtyText(
                                  item.quantity,
                                  unit,
                                  unit != null ? formatTwd(unit) : '',
                                )),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: CategoryBadge(
                                    category: itemCat,
                                    onTap: item.id == null
                                        ? null
                                        : () => _changeItemCategory(
                                            context, ref, item.id!,
                                            item.categoryId, categories, s),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      trailing: Text(
                        formatTwd(item.amount),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  /// Changes the invoice category (cascading to all items) — the only edit
  /// allowed on official (synced) invoices.
  Future<void> _changeCategory(
    BuildContext context,
    WidgetRef ref,
    Invoice inv,
    List<Category> categories,
    AppStrings s,
  ) async {
    final selected = await _pickCategory(context, categories, inv.categoryId, s);
    if (selected == null || selected == inv.categoryId) return;
    await ref.read(invoiceRepositoryProvider).updateCategory(inv.id!, selected);
    ref.invalidate(invoiceByIdProvider(invoiceId));
    ref.invalidate(invoiceListProvider);
  }

  /// Re-assigns the receipt's trip (or clears it → undecided). Only the bucket
  /// moves; the stored foreign amount / currency / rate are untouched.
  Future<void> _changeTrip(
    BuildContext context,
    WidgetRef ref,
    Invoice inv,
    List<Trip> trips,
    AppStrings s,
  ) async {
    final picked = await _pickTrip(context, trips, inv.tripId, s);
    if (picked == null) return; // sheet dismissed
    final newTripId = picked.isEmpty ? null : picked; // '' → No trip (undecided)
    if (newTripId == inv.tripId) return;
    await ref.read(invoiceRepositoryProvider).updateTrip(inv.id!, newTripId);
    ref.invalidate(invoiceByIdProvider(invoiceId));
    ref.invalidate(invoiceListProvider);
  }

  /// Bottom-sheet trip picker. Returns the chosen trip id, '' for "No trip", or
  /// null if dismissed. [current] is ticked.
  Future<String?> _pickTrip(
    BuildContext context,
    List<Trip> trips,
    String? current,
    AppStrings s,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                s.chooseTrip,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.grey),
              title: Text(s.noTripOption),
              trailing: current == null
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final t in trips)
              ListTile(
                leading: Text(
                  countryByCode(t.countryCode)?.flag ?? '✈️',
                  style: const TextStyle(fontSize: 22),
                ),
                title: Text(t.name),
                subtitle: Text(
                  '${s.tripDateRange(formatDate(t.startDate), formatDate(t.endDate))} · ${t.currencyCode}',
                ),
                trailing: t.id == current
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(ctx, t.id),
              ),
          ],
        ),
      ),
    );
  }

  /// Overrides a single line item's category, for receipts mixing categories.
  Future<void> _changeItemCategory(
    BuildContext context,
    WidgetRef ref,
    String itemId,
    int? currentCategoryId,
    List<Category> categories,
    AppStrings s,
  ) async {
    final selected = await _pickCategory(context, categories, currentCategoryId, s);
    if (selected == null || selected == currentCategoryId) return;
    await ref
        .read(invoiceRepositoryProvider)
        .updateItemCategory(itemId, selected);
    ref.invalidate(invoiceByIdProvider(invoiceId));
    ref.invalidate(invoiceListProvider);
  }

  /// Bottom-sheet category picker. Returns the chosen category id, or null if
  /// dismissed. [current] is ticked.
  Future<int?> _pickCategory(
    BuildContext context,
    List<Category> categories,
    int? current,
    AppStrings s,
  ) {
    return showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                s.changeCategory,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final c in categories)
              ListTile(
                leading: Icon(styleForCategory(c).icon,
                    color: styleForCategory(c).color),
                title: Text(s.catName(c)),
                trailing: c.id == current
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTitle),
        content: Text(s.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(invoiceRepositoryProvider).delete(invoiceId);
    ref.invalidate(invoiceListProvider);
    if (context.mounted) context.pop();
  }
}
