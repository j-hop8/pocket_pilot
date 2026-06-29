import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/categories.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';

/// Set recurring monthly limits: an overall cap plus a per-expense-category
/// limit. Tapping a row opens an editor to set / change / remove that budget.
class BudgetManagementScreen extends ConsumerWidget {
  const BudgetManagementScreen({super.key});

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Category? category,
    Budget? existing,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PocketColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BudgetEditorSheet(category: category, existing: existing),
    );
    if (saved == true) ref.invalidate(budgetListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final budgetsByCat = ref.watch(budgetsByCategoryProvider);
    final expenseCats = ref.watch(expenseCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.budgetsTitle)),
      body: budgetsByCat.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(s.failedToLoadError(e))),
        data: (byCat) {
          final cats = expenseCats.asData?.value ?? const <Category>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            children: [
              _SectionLabel(s.overallBudgetLabel),
              const SizedBox(height: 10),
              _BudgetTile(
                leading: const _OverallIcon(),
                name: s.overallBudgetLabel,
                budget: byCat[null],
                s: s,
                onTap: () =>
                    _openEditor(context, ref, existing: byCat[null]),
              ),
              const SizedBox(height: 24),
              _SectionLabel(s.expenseLabel),
              const SizedBox(height: 10),
              for (final c in cats) ...[
                _BudgetTile(
                  leading: _CategoryIcon(category: c),
                  name: s.catName(c),
                  budget: byCat[c.id],
                  s: s,
                  onTap: () => _openEditor(
                    context,
                    ref,
                    category: c,
                    existing: byCat[c.id],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.spaceMono(
        fontSize: 10,
        letterSpacing: 0.14,
        color: PocketColors.inkSoft,
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  final Widget leading;
  final String name;
  final Budget? budget;
  final AppStrings s;
  final VoidCallback onTap;

  const _BudgetTile({
    required this.leading,
    required this.name,
    required this.budget,
    required this.s,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = budget;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: PocketColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: PocketColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              b == null ? s.notSetLabel : s.budgetPerMonth(b.amount),
              style: GoogleFonts.spaceMono(
                fontSize: 13,
                fontWeight: b == null ? FontWeight.w400 : FontWeight.w600,
                color: b == null ? PocketColors.inkSoft : PocketColors.ink,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: PocketColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final Category category;
  const _CategoryIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    final style = styleForCategory(category);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: style.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(style.icon, color: Colors.white, size: 20),
    );
  }
}

class _OverallIcon extends StatelessWidget {
  const _OverallIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: PocketColors.ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.savings_outlined, color: Colors.white, size: 20),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Create/edit a single budget. Returns true on a successful save or delete.
class _BudgetEditorSheet extends ConsumerStatefulWidget {
  final Category? category; // null => overall budget
  final Budget? existing;

  const _BudgetEditorSheet({this.category, this.existing});

  @override
  ConsumerState<_BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends ConsumerState<_BudgetEditorSheet> {
  late final TextEditingController _amount;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final cents = widget.existing?.amount;
    _amount = TextEditingController(
      text: cents == null ? '' : (cents ~/ 100).toString(),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String _title(AppStrings s) {
    if (widget.category == null) return s.overallBudgetLabel;
    return s.catName(widget.category);
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    final cents = dollarsToCents(num.tryParse(_amount.text.trim()) ?? 0);
    if (cents <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.enterValidBudget)));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(budgetRepositoryProvider);
    try {
      if (widget.existing == null) {
        await repo.create(
          categoryId: widget.category?.id,
          amountCents: cents,
        );
      } else {
        await repo.update(widget.existing!.id, amountCents: cents);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.budgetSaveFailed(e))));
    }
  }

  Future<void> _remove() async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.removeBudgetTitle),
        content: Text(s.removeBudgetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: PocketColors.persimmon),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.removeBudget),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(budgetRepositoryProvider).delete(widget.existing!.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.budgetDeleteFailed(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title(s),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: PocketColors.ink,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: s.budgetAmountLabel,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saving ? null : _save(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: PocketColors.ink),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(s.save),
            ),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _saving ? null : _remove,
                icon: const Icon(Icons.delete_outline, size: 18),
                style: TextButton.styleFrom(
                    foregroundColor: PocketColors.persimmon),
                label: Text(s.removeBudget),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
