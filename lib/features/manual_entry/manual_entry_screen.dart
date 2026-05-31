import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';

class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ItemDraft {
  final nameController = TextEditingController();
  final qtyController = TextEditingController(text: '1');
  final priceController = TextEditingController();
  int? categoryId;

  _ItemDraft({this.categoryId});

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
  }

  num get qty => num.tryParse(qtyController.text.trim()) ?? 1;
  num get price => num.tryParse(priceController.text.trim()) ?? 0;
  bool get isFilled => nameController.text.trim().isNotEmpty;
  int get amountCents => (qty * dollarsToCents(price)).round();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _merchantController = TextEditingController();
  DateTime _date = DateTime.now();
  int? _invoiceCategoryId;
  final List<_ItemDraft> _items = [_ItemDraft()];
  bool _saving = false;

  @override
  void dispose() {
    _merchantController.dispose();
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

  int get _totalCents =>
      _items.where((i) => i.isFilled).fold(0, (s, i) => s + i.amountCents);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(int? defaultCategoryId) async {
    final filled = _items.where((i) => i.isFilled).toList();
    if (filled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item with a name.')),
      );
      return;
    }
    final invoiceCat = _invoiceCategoryId ?? defaultCategoryId;
    setState(() => _saving = true);

    final invoice = Invoice(
      invoiceDate: _date,
      merchantName: _merchantController.text.trim().isEmpty
          ? null
          : _merchantController.text.trim(),
      totalAmount: _totalCents,
      categoryId: invoiceCat,
      source: 'manual',
    );
    final items = [
      for (var idx = 0; idx < filled.length; idx++)
        InvoiceItem(
          name: filled[idx].nameController.text.trim(),
          quantity: filled[idx].qty,
          unitPrice: dollarsToCents(filled[idx].price),
          amount: filled[idx].amountCents,
          categoryId: filled[idx].categoryId ?? invoiceCat,
          sortOrder: idx,
        ),
    ];

    try {
      await ref.read(invoiceRepositoryProvider).insert(invoice, items);
      ref.invalidate(invoiceListProvider);
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add invoice')),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load categories: $e')),
        data: (categories) {
          final defaultCat = _defaultCategoryId(categories);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.event),
                        title: const Text('Date'),
                        subtitle: Text(formatDate(_date)),
                        trailing: const Icon(Icons.edit),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _merchantController,
                      decoration: const InputDecoration(
                        labelText: 'Merchant',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _invoiceCategoryId ?? defaultCat,
                      decoration: const InputDecoration(
                        labelText: 'Invoice category',
                        border: OutlineInputBorder(),
                      ),
                      items: categories
                          .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.label),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _invoiceCategoryId = v),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Items',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        TextButton.icon(
                          onPressed: () => setState(() =>
                              _items.add(_ItemDraft(categoryId: defaultCat))),
                          icon: const Icon(Icons.add),
                          label: const Text('Add item'),
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
                        onChanged: () => setState(() {}),
                        onRemove: () => setState(() {
                          _items.removeAt(i).dispose();
                        }),
                      );
                    }),
                  ],
                ),
              ),
              _SaveBar(
                total: _totalCents,
                saving: _saving,
                onSave: () => _save(defaultCat),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final _ItemDraft draft;
  final List<Category> categories;
  final int? defaultCategoryId;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _ItemCard({
    super.key,
    required this.draft,
    required this.categories,
    required this.defaultCategoryId,
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
                    decoration: const InputDecoration(
                      labelText: 'Item name',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove',
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
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      isDense: true,
                      border: OutlineInputBorder(),
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
                    decoration: const InputDecoration(
                      labelText: 'Unit price (NT\$)',
                      isDense: true,
                      border: OutlineInputBorder(),
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
              decoration: const InputDecoration(
                labelText: 'Item category',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: categories
                  .map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.label)))
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
  final VoidCallback onSave;

  const _SaveBar({
    required this.total,
    required this.saving,
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
                    const Text('Total', style: TextStyle(fontSize: 12)),
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
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
