import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/categories.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/mascots.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s             = ref.watch(stringsProvider);
    final invoicesAsync = ref.watch(invoiceListProvider);
    final catMap        = ref.watch(categoriesByIdProvider).asData?.value ?? const {};

    return invoicesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: PocketColors.persimmon),
      ),
      error: (e, _) => Center(child: Text(s.failedToLoadError(e))),
      data: (invoices) {
        if (invoices.isEmpty) {
          return EmptyState(
            title: s.noHistory,
            subtitle: s.scanToStart,
            mascot: const ReceiptMascot(size: 72),
          );
        }

        final groups = <String, List<Invoice>>{};
        for (final inv in invoices) {
          final key = formatDate(inv.invoiceDate);
          (groups[key] ??= []).add(inv);
        }
        final dateKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

        final items = <_Item>[];
        for (final key in dateKeys) {
          final dayInvoices = groups[key]!;
          // Net for the day: income adds, expense subtracts.
          final dayNet = dayInvoices.fold<int>(
              0, (sum, i) => sum + (i.isIncome ? i.totalAmount : -i.totalAmount));
          items.add(_Header(date: key, net: dayNet));
          for (final inv in dayInvoices) {
            items.add(_Row(invoice: inv, catMap: catMap));
          }
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final item = items[i];
            return switch (item) {
              _Header h => _DateHeader(header: h),
              _Row r    => _TransactionTile(
                  invoice:  r.invoice,
                  catMap:   r.catMap,
                  s:        s,
                  onTap:    () => context.push('/invoice/${r.invoice.id}'),
                  // Long-press delete only for user-originated invoices; official
                  // (synced) ones can't be deleted — see InvoiceDetailScreen.
                  onDelete: r.invoice.canDelete
                      ? () => _confirmDelete(context, ref, r.invoice.id!, s)
                      : null,
                ),
            };
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String id, AppStrings s) async {
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
    if (ok == true) {
      await ref.read(invoiceRepositoryProvider).delete(id);
      ref.invalidate(invoiceListProvider);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

sealed class _Item {}

class _Header extends _Item {
  final String date;
  final int net; // signed: positive = net income, negative = net spending
  _Header({required this.date, required this.net});
}

class _Row extends _Item {
  final Invoice invoice;
  final Map<int, Category> catMap;
  _Row({required this.invoice, required this.catMap});
}

// ─────────────────────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final _Header header;
  const _DateHeader({required this.header});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Row(
        children: [
          Text(
            header.date,
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              letterSpacing: 0.1,
              color: PocketColors.inkSoft,
            ),
          ),
          const Spacer(),
          Text(
            '${header.net >= 0 ? '+' : '−'}${header.net.abs() ~/ 100}',
            style: GoogleFonts.spaceMono(
              fontSize: 11,
              color: PocketColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Invoice invoice;
  final Map<int, Category> catMap;
  final AppStrings s;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _TransactionTile({
    required this.invoice,
    required this.catMap,
    required this.s,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cat      = invoice.categoryId == null ? null : catMap[invoice.categoryId];
    final style    = styleForKey(cat?.key);
    final merchant = invoice.merchantName?.isNotEmpty == true
        ? invoice.merchantName!
        : s.unknownMerchant;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PocketColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: PocketColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.categoryName(cat?.key),
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      color: PocketColors.inkSoft,
                      letterSpacing: 0.04,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${invoice.isIncome ? '+' : '−'}${invoice.totalAmount ~/ 100}',
              style: GoogleFonts.spaceMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: invoice.isIncome ? PocketColors.pine : PocketColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
