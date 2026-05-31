import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../models/invoice.dart';
import '../../widgets/category_badge.dart';
import '../../widgets/source_icon.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceByIdProvider(invoiceId));
    final catMap = ref.watch(categoriesByIdProvider).asData?.value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: invoiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (inv) => _DetailBody(invoice: inv, catMap: catMap),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Invoice invoice;
  final Map<int, dynamic> catMap;

  const _DetailBody({required this.invoice, required this.catMap});

  @override
  Widget build(BuildContext context) {
    final cat =
        invoice.categoryId == null ? null : catMap[invoice.categoryId];
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
                    SourceIcon(source: invoice.source, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        invoice.merchantName?.isNotEmpty == true
                            ? invoice.merchantName!
                            : 'Unknown merchant',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Date: ${formatDate(invoice.invoiceDate)}'),
                if (invoice.invoiceNumber != null)
                  Text('Invoice no.: ${invoice.invoiceNumber}'),
                const SizedBox(height: 8),
                CategoryBadge(category: cat),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      formatTwd(invoice.totalAmount),
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('Items',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        if (invoice.items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No line items.'),
          )
        else
          ...invoice.items.map((item) {
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
                      Text(unit == null
                          ? 'Qty ${item.quantity}'
                          : 'Qty ${item.quantity} × ${formatTwd(unit)}'),
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
  }
}
