import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';

class ManualEntryScreen extends ConsumerStatefulWidget {
  /// When non-null the screen edits this existing (user-originated) invoice
  /// instead of creating a new one. Official invoices are never passed here —
  /// they only allow a category change (see the detail screen).
  final Invoice? existing;

  const ManualEntryScreen({super.key, this.existing});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ItemDraft {
  final nameController  = TextEditingController();
  final qtyController   = TextEditingController(text: '1');
  final priceController = TextEditingController();
  int? categoryId;

  _ItemDraft({this.categoryId});

  /// Rebuilds an editable draft from a saved line item. Price is shown in
  /// dollars (the controller's unit), derived from the stored unit-price cents.
  factory _ItemDraft.fromItem(InvoiceItem item) {
    final draft = _ItemDraft(categoryId: item.categoryId);
    draft.nameController.text  = item.name;
    draft.qtyController.text   = _trimNum(item.quantity);
    final dollars = centsToDollars(item.unitPrice ?? item.amount);
    draft.priceController.text = _trimNum(dollars);
    return draft;
  }

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
  }

  num get qty   => num.tryParse(qtyController.text.trim()) ?? 1;
  num get price => num.tryParse(priceController.text.trim()) ?? 0;
  bool get isFilled => nameController.text.trim().isNotEmpty;
  int get amountCents => (qty * dollarsToCents(price)).round();
}

/// "350.0" -> "350", "1.5" -> "1.5" — keeps prefilled numeric fields tidy.
String _trimNum(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _merchantController = TextEditingController();
  final _incomeAmountController = TextEditingController();
  DateTime _date = DateTime.now();
  int? _invoiceCategoryId;
  String _kind = 'expense'; // 'expense' | 'income'
  late final List<_ItemDraft> _items;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;
  bool get _isIncome => _kind == 'income';

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) {
      _items = [_ItemDraft()];
      return;
    }
    _kind = existing.kind;
    _merchantController.text = existing.merchantName ?? '';
    _date = existing.invoiceDate;
    _invoiceCategoryId = existing.categoryId;
    if (existing.isIncome) {
      _incomeAmountController.text = _trimNum(centsToDollars(existing.totalAmount));
    }
    _items = existing.items.isEmpty
        ? [_ItemDraft()]
        : existing.items.map(_ItemDraft.fromItem).toList();
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _incomeAmountController.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  int? _defaultCategoryId(List<Category> categories) {
    if (categories.isEmpty) return null;
    return categories
        .firstWhere((c) => c.key == 'other', orElse: () => categories.first)
        .id;
  }

  int get _itemsTotalCents =>
      _items.where((i) => i.isFilled).fold(0, (s, i) => s + i.amountCents);

  int get _incomeCents =>
      dollarsToCents(num.tryParse(_incomeAmountController.text.trim()) ?? 0);

  /// The figure shown in the save bar — income amount, or the sum of expense items.
  int get _totalCents => _isIncome ? _incomeCents : _itemsTotalCents;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(int? defaultCategoryId, AppStrings s) async {
    final cat = _invoiceCategoryId ?? defaultCategoryId;
    final existing = widget.existing;
    final merchant = _merchantController.text.trim().isEmpty
        ? null
        : _merchantController.text.trim();

    // Built directly (not copyWith) so a cleared merchant/category persists as
    // null rather than being treated as "unchanged".
    final Invoice invoice;
    final List<InvoiceItem> items;

    if (_isIncome) {
      final amountCents = _incomeCents;
      if (amountCents <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.enterAmount)),
        );
        return;
      }
      invoice = Invoice(
        id: existing?.id,
        invoiceNumber: existing?.invoiceNumber,
        invoiceDate: _date,
        merchantName: merchant,
        salesAmount: existing?.salesAmount,
        totalAmount: amountCents,
        currency: existing?.currency ?? 'TWD',
        categoryId: cat,
        source: existing?.source ?? 'manual',
        kind: 'income',
        rawPayload: existing?.rawPayload,
        createdAt: existing?.createdAt,
      );
      // One synthetic line item so the detail screen and item-based totals stay
      // consistent with expenses (which always carry items).
      items = [
        InvoiceItem(
          name: merchant ?? s.incomeLabel,
          quantity: 1,
          unitPrice: amountCents,
          amount: amountCents,
          categoryId: cat,
          sortOrder: 0,
        ),
      ];
    } else {
      final filled = _items.where((i) => i.isFilled).toList();
      if (filled.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.addAtLeastOneItem)),
        );
        return;
      }
      invoice = Invoice(
        id: existing?.id,
        invoiceNumber: existing?.invoiceNumber,
        invoiceDate: _date,
        merchantName: merchant,
        salesAmount: existing?.salesAmount,
        totalAmount: _itemsTotalCents,
        currency: existing?.currency ?? 'TWD',
        categoryId: cat,
        source: existing?.source ?? 'manual',
        kind: 'expense',
        rawPayload: existing?.rawPayload,
        createdAt: existing?.createdAt,
      );
      items = [
        for (var idx = 0; idx < filled.length; idx++)
          InvoiceItem(
            name: filled[idx].nameController.text.trim(),
            quantity: filled[idx].qty,
            unitPrice: dollarsToCents(filled[idx].price),
            amount: filled[idx].amountCents,
            categoryId: filled[idx].categoryId ?? cat,
            sortOrder: idx,
          ),
      ];
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(invoiceRepositoryProvider);
      if (existing == null) {
        await repo.insert(invoice, items);
      } else {
        await repo.update(invoice, items);
        ref.invalidate(invoiceByIdProvider(existing.id!));
      }
      ref.invalidate(invoiceListProvider);
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.saveFailedError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s              = ref.watch(stringsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final title = _isIncome
        ? (_isEditing ? s.editIncome : s.addIncome)
        : (_isEditing ? s.editInvoice : s.addInvoice);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text(s.failedToLoadError(e))),
        data: (allCategories) {
          // Show only the category set that matches the current kind.
          final categories = allCategories
              .where((c) => _isIncome ? c.isIncome : !c.isIncome)
              .toList();
          final defaultCat = _defaultCategoryId(categories);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'expense',
                          label: Text(s.expenseLabel),
                          icon: const Icon(Icons.south_west),
                        ),
                        ButtonSegment(
                          value: 'income',
                          label: Text(s.incomeLabel),
                          icon: const Icon(Icons.north_east),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (sel) => setState(() {
                        _kind = sel.first;
                        // The previously-picked category belongs to the other
                        // set; fall back to the new set's default.
                        _invoiceCategoryId = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.event),
                        title: Text(s.dateLabel),
                        subtitle: Text(formatDate(_date)),
                        trailing: const Icon(Icons.edit),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isIncome)
                      ..._incomeFields(s, categories, defaultCat)
                    else
                      ..._expenseFields(s, categories, defaultCat),
                  ],
                ),
              ),
              _SaveBar(
                total: _totalCents,
                saving: _saving,
                totalLabel: s.totalLabel,
                saveLabel: s.save,
                onSave: () => _save(defaultCat, s),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Simplified income form: source + a single amount + an income category.
  List<Widget> _incomeFields(
      AppStrings s, List<Category> categories, int? defaultCat) {
    return [
      TextField(
        controller: _merchantController,
        decoration: InputDecoration(
          labelText: s.incomeSourceLabel,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _incomeAmountController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: s.amountLabel,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        value: _invoiceCategoryId ?? defaultCat,
        decoration: InputDecoration(
          labelText: s.invoiceCategory,
          border: const OutlineInputBorder(),
        ),
        items: categories
            .map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(s.categoryName(c.key)),
                ))
            .toList(),
        onChanged: (v) => setState(() => _invoiceCategoryId = v),
      ),
    ];
  }

  /// Full expense form: merchant + invoice category + line items.
  List<Widget> _expenseFields(
      AppStrings s, List<Category> categories, int? defaultCat) {
    return [
      TextField(
        controller: _merchantController,
        decoration: InputDecoration(
          labelText: s.merchantLabel,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        value: _invoiceCategoryId ?? defaultCat,
        decoration: InputDecoration(
          labelText: s.invoiceCategory,
          border: const OutlineInputBorder(),
        ),
        items: categories
            .map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(s.categoryName(c.key)),
                ))
            .toList(),
        onChanged: (v) => setState(() => _invoiceCategoryId = v),
      ),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            s.itemsLabel,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(
                () => _items.add(_ItemDraft(categoryId: defaultCat))),
            icon: const Icon(Icons.add),
            label: Text(s.addItem),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ...List.generate(_items.length, (i) {
        return _ItemCard(
          key: ObjectKey(_items[i]),
          draft: _items[i],
          categories: categories,
          defaultCategoryId: _invoiceCategoryId ?? defaultCat,
          s: s,
          onChanged: () => setState(() {}),
          onRemove: () => setState(() {
            _items.removeAt(i).dispose();
          }),
        );
      }),
    ];
  }
}

class _ItemCard extends StatelessWidget {
  final _ItemDraft draft;
  final List<Category> categories;
  final int? defaultCategoryId;
  final AppStrings s;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _ItemCard({
    super.key,
    required this.draft,
    required this.categories,
    required this.defaultCategoryId,
    required this.s,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.nameController,
                    decoration: InputDecoration(
                      labelText: s.itemName,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: s.remove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.qtyController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: s.qtyLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: draft.priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: s.unitPrice,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: draft.categoryId ?? defaultCategoryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: s.itemCategory,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: categories
                  .map((c) => DropdownMenuItem(
                      value: c.id, child: Text(s.categoryName(c.key))))
                  .toList(),
              onChanged: (v) {
                draft.categoryId = v;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final int total;
  final bool saving;
  final String totalLabel;
  final String saveLabel;
  final VoidCallback onSave;

  const _SaveBar({
    required this.total,
    required this.saving,
    required this.totalLabel,
    required this.saveLabel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(totalLabel,
                        style: const TextStyle(fontSize: 12)),
                    Text(
                      formatTwd(total),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(saveLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
