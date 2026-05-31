import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../widgets/category_badge.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/source_icon.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoiceListProvider);
    final catMap = ref.watch(categoriesByIdProvider).asData?.value ?? const {};

    return invoicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (invoices) {
        if (invoices.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No invoices yet',
            subtitle: 'Tap Add to record your first one.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: invoices.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final inv = invoices[index];
            final cat = inv.categoryId == null ? null : catMap[inv.categoryId];
            return Card(
              child: ListTile(
                leading: SourceIcon(source: inv.source),
                title: Text(
                  inv.merchantName?.isNotEmpty == true
                      ? inv.merchantName!
                      : 'Unknown merchant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Text(formatDate(inv.invoiceDate)),
                      const SizedBox(width: 8),
                      Flexible(child: CategoryBadge(category: cat)),
                    ],
                  ),
                ),
                trailing: Text(
                  formatTwd(inv.totalAmount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                onTap: () => context.push('/invoice/${inv.id}'),
                onLongPress: () => _confirmDelete(context, ref, inv.id!),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete invoice?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(invoiceRepositoryProvider).delete(id);
      ref.invalidate(invoiceListProvider);
    }
  }
}
