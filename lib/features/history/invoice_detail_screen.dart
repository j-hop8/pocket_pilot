import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(s.invoiceTitle)),
      body: invoiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text(s.failedToLoadError(e))),
        data: (inv) {
          final cat = inv.categoryId == null ? null : catMap[inv.categoryId];
          return ListView(
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
                      CategoryBadge(category: cat),
                      const Divider(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.totalLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            formatTwd(inv.totalAmount),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
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
                            Flexible(child: CategoryBadge(category: itemCat)),
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
          );
        },
      ),
    );
  }
}
