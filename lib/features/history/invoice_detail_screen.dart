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
import '../../widgets/category_badge.dart';
import '../../widgets/source_icon.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s            = ref.watch(stringsProvider);
    final invoiceAsync = ref.watch(invoiceByIdProvider(invoiceId));
    final catMap       = ref.watch(categoriesByIdProvider).asData?.value ?? const {};
    final categories   = ref.watch(categoriesProvider).asData?.value ?? const [];

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
                            child: Text(
                              inv.merchantName?.isNotEmpty == true
                                  ? inv.merchantName!
                                  : s.unknownMerchantLong,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
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
                      const Divider(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.totalLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${inv.isIncome ? '+' : '−'}${formatTwd(inv.totalAmount)}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: inv.isIncome ? PocketColors.pine : null,
                            ),
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
                  return Card(
                    child: ListTile(
                      title: Text(item.name),
                      subtitle: Padding(
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
                                        context, ref, item.id!, item.categoryId,
                                        categories, s),
                              ),
                            ),
                          ],
                        ),
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
                leading: Icon(styleForKey(c.key).icon,
                    color: styleForKey(c.key).color),
                title: Text(s.categoryName(c.key)),
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
