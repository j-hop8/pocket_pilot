import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pp_core/pp_core.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../models/category.dart';

/// Shows the confirm-before-save sheet for a scanned e-invoice. Returns `true`
/// when the user saved it. The invoice is "official" (`source = qr_scan`), so
/// only the category is editable — everything else mirrors the QR.
Future<bool?> showScanReviewSheet(BuildContext context, ParsedQrInvoice qr) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScanReviewSheet(qr: qr),
  );
}

class _ScanReviewSheet extends ConsumerStatefulWidget {
  final ParsedQrInvoice qr;
  const _ScanReviewSheet({required this.qr});

  @override
  ConsumerState<_ScanReviewSheet> createState() => _ScanReviewSheetState();
}

class _ScanReviewSheetState extends ConsumerState<_ScanReviewSheet> {
  List<Category> _categories = const [];
  final _merchantCtrl = TextEditingController();
  bool _merchantTouched = false; // don't overwrite the user's edit on lookup
  bool _lookingUp = true;
  int? _categoryId;
  bool _categoryTouched = false;
  bool _ready = false;
  bool _saving = false;

  ParsedQrInvoice get _qr => widget.qr;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final all = await ref.read(categoriesProvider.future);
    final expense = all.where((c) => !c.isIncome).toList();
    final svc = ref.read(einvoiceQrServiceProvider);
    // Preliminary category (no merchant name yet) so the picker isn't empty.
    final preliminary =
        await svc.defaultCategoryId(_qr, merchantName: null, categories: expense);
    if (!mounted) return;
    setState(() {
      _categories = expense;
      _categoryId = preliminary;
      _ready = true;
    });

    // Resolve the merchant name, then refine the default category from it.
    final name =
        await ref.read(merchantLookupServiceProvider).nameForTaxId(_qr.sellerTaxId);
    final refined = await svc.defaultCategoryId(_qr,
        merchantName: name, categories: expense);
    if (!mounted) return;
    setState(() {
      // Prefill the resolved name unless the user already typed their own.
      if (!_merchantTouched && name != null) _merchantCtrl.text = name;
      _lookingUp = false;
      if (!_categoryTouched) _categoryId = refined;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final s = ref.read(stringsProvider);
    final merchant = _merchantCtrl.text.trim();
    try {
      await ref.read(einvoiceQrServiceProvider).save(
            _qr,
            merchantName: merchant.isEmpty ? null : merchant,
            categoryId: _categoryId,
          );
      ref.invalidate(invoiceListProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.scanSaveFailed(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final totalCents = dollarsToCents(_qr.totalDollars);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: !_ready
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.scanReviewTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),

                // Merchant: auto-resolved from the seller tax id, but editable
                // (the name isn't part of the official QR, so the user may fix it).
                _Field(
                  label: s.merchantLabel,
                  child: TextField(
                    controller: _merchantCtrl,
                    onChanged: (_) => _merchantTouched = true,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText:
                          _lookingUp ? s.scanLookingUp : (_qr.sellerTaxId ?? s.unknownMerchant),
                      border: const UnderlineInputBorder(),
                      suffixIcon: _lookingUp
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),

                _Field(
                  label: s.scanInvoiceNoLabel,
                  child: Text(_qr.invoiceNumber),
                ),
                _Field(label: s.dateLabel, child: Text(formatDate(_qr.date))),
                _Field(
                  label: s.totalLabel,
                  child: Text(
                    formatTwd(totalCents),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 8),
                if (_qr.hasFullItems)
                  ..._qr.items.map((i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(i.name)),
                            Text(formatTwd(dollarsToCents(i.amount))),
                          ],
                        ),
                      ))
                else
                  Text(
                    s.scanNoItemsNote,
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor),
                  ),

                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _categoryId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: s.invoiceCategory,
                    border: const OutlineInputBorder(),
                  ),
                  items: _categories
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(s.catName(c)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _categoryId = v;
                    _categoryTouched = true;
                  }),
                ),

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(s.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: Text(s.save),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: DefaultTextStyle.merge(child: child)),
        ],
      ),
    );
  }
}
