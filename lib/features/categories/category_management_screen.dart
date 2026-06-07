import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/categories.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/category.dart';

/// Manage the signed-in user's categories: separate Expense / Income sets, each
/// with create / edit / delete. Built-in defaults are editable too (editing one
/// detaches it from the localized name + curated style).
class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen> {
  String _kind = 'expense';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openEditor({Category? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PocketColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CategoryEditorSheet(kind: _kind, existing: existing),
    );
    if (saved == true) ref.invalidate(categoriesProvider);
  }

  Future<void> _delete(Category c, AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteCategoryTitle),
        content: Text(s.deleteCategoryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PocketColors.persimmon),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(categoryRepositoryProvider).delete(c.id);
      ref.invalidate(categoriesProvider);
      ref.invalidate(invoiceListProvider); // categorizations may now read as null
    } catch (e) {
      _snack(s.categoryDeleteFailed(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.categoriesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: PocketColors.ink,
        icon: const Icon(Icons.add, color: PocketColors.paper),
        label: Text(
          s.addCategory,
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w600,
            color: PocketColors.paper,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                _KindChip(
                  label: s.expenseLabel,
                  active: _kind == 'expense',
                  onTap: () => setState(() => _kind = 'expense'),
                ),
                const SizedBox(width: 10),
                _KindChip(
                  label: s.incomeLabel,
                  active: _kind == 'income',
                  onTap: () => setState(() => _kind = 'income'),
                ),
              ],
            ),
          ),
          Expanded(
            child: categories.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(s.failedToLoadError(e))),
              data: (all) {
                final list =
                    all.where((c) => c.kind == _kind).toList();
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      s.noCategoriesYet,
                      style: GoogleFonts.spaceMono(
                        fontSize: 13,
                        color: PocketColors.inkSoft,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _CategoryRow(
                    category: list[i],
                    name: s.catName(list[i]),
                    onEdit: () => _openEditor(existing: list[i]),
                    onDelete: () => _delete(list[i], s),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  final Category category;
  final String name;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryRow({
    required this.category,
    required this.name,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleForCategory(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined,
                size: 20, color: PocketColors.inkSoft),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline,
                size: 20, color: PocketColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _KindChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color: active ? PocketColors.ink : PocketColors.paper2,
          borderRadius: BorderRadius.circular(999),
          border:
              active ? null : Border.all(color: PocketColors.line, width: 1),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: active ? PocketColors.paper : PocketColors.inkSoft,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Create/edit form shown in a bottom sheet. Returns true on a successful save.
class _CategoryEditorSheet extends ConsumerStatefulWidget {
  final String kind;
  final Category? existing;

  const _CategoryEditorSheet({required this.kind, this.existing});

  @override
  ConsumerState<_CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<_CategoryEditorSheet> {
  late final TextEditingController _name;
  late String _iconName;
  late Color _color;
  // True once the user is on the free-form picker — either they tapped the
  // custom swatch, or the category's stored color isn't one of the presets.
  late bool _showCustom;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    final s = ref.read(stringsProvider);
    _name = TextEditingController(text: c == null ? '' : s.catName(c));
    _iconName = _initialIconName(c);
    _color = _initialColor(c);
    _showCustom = !_isPreset(_color);
  }

  /// Whether [color] matches one of the curated palette swatches.
  bool _isPreset(Color color) {
    final hex = hexFromColor(color);
    return categoryPalette.any((c) => hexFromColor(c) == hex);
  }

  /// Pick a starting icon name: the stored one, else the matching name for the
  /// built-in style's icon, else the generic fallback.
  String _initialIconName(Category? c) {
    if (c?.icon != null) return c!.icon!;
    if (c != null) {
      final icon = styleForCategory(c).icon;
      for (final e in categoryIcons.entries) {
        if (e.value == icon) return e.key;
      }
    }
    return 'category';
  }

  Color _initialColor(Category? c) {
    if (c?.color != null) return colorFromHex(c!.color);
    if (c != null) return styleForCategory(c).color;
    return categoryPalette.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.enterCategoryName)));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(categoryRepositoryProvider);
    final hex = hexFromColor(_color);
    try {
      if (widget.existing == null) {
        await repo.create(
          name: name,
          kind: widget.kind,
          iconName: _iconName,
          colorHex: hex,
        );
      } else {
        await repo.update(
          widget.existing!.id,
          name: name,
          iconName: _iconName,
          colorHex: hex,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.categorySaveFailed(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? s.addCategory : s.editCategory,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: PocketColors.ink,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              decoration: InputDecoration(
                labelText: s.categoryNameLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            _FieldLabel(s.chooseColor),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in categoryPalette)
                  _ColorSwatch(
                    color: color,
                    selected: !_showCustom &&
                        hexFromColor(color) == hexFromColor(_color),
                    onTap: () => setState(() {
                      _color = color;
                      _showCustom = false;
                    }),
                  ),
                _CustomColorButton(
                  color: _color,
                  selected: _showCustom,
                  onTap: () => setState(() => _showCustom = true),
                ),
              ],
            ),
            if (_showCustom) ...[
              const SizedBox(height: 16),
              _CustomColorPicker(
                color: _color,
                onChanged: (c) => setState(() => _color = c),
              ),
            ],
            const SizedBox(height: 20),
            _FieldLabel(s.chooseIcon),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in categoryIcons.entries)
                  _IconChoice(
                    icon: entry.value,
                    color: _color,
                    selected: entry.key == _iconName,
                    onTap: () => setState(() => _iconName = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 24),
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
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

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

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: PocketColors.ink, width: 3)
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}

/// Trailing swatch that opens the free-form HSV picker. Shows a rainbow ring
/// when inactive; once selected it fills with the chosen custom colour.
class _CustomColorButton extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CustomColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  static const _rainbow = SweepGradient(colors: [
    Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
    Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ]);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? color : null,
          gradient: selected ? null : _rainbow,
          shape: BoxShape.circle,
          border:
              selected ? Border.all(color: PocketColors.ink, width: 3) : null,
        ),
        child: Icon(
          selected ? Icons.check : Icons.colorize,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

/// Dependency-free HSV picker: hue / saturation / brightness gradient sliders
/// plus a live swatch + hex readout. Reports every change up to the editor.
class _CustomColorPicker extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onChanged;

  const _CustomColorPicker({required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GradientSlider(
          value: hsv.hue / 360,
          thumbColor: hueColor,
          gradient: const [
            Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
            Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
          onChanged: (t) => onChanged(hsv.withHue(t * 360).toColor()),
        ),
        const SizedBox(height: 14),
        _GradientSlider(
          value: hsv.saturation,
          thumbColor: color,
          gradient: [
            HSVColor.fromAHSV(1, hsv.hue, 0, hsv.value).toColor(),
            HSVColor.fromAHSV(1, hsv.hue, 1, hsv.value).toColor(),
          ],
          onChanged: (t) => onChanged(hsv.withSaturation(t).toColor()),
        ),
        const SizedBox(height: 14),
        _GradientSlider(
          value: hsv.value,
          thumbColor: color,
          gradient: [
            HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 0).toColor(),
            HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor(),
          ],
          onChanged: (t) => onChanged(hsv.withValue(t).toColor()),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: PocketColors.line),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              hexFromColor(color),
              style: GoogleFonts.spaceMono(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: PocketColors.ink,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A horizontal gradient track with a draggable thumb, value normalised 0..1.
class _GradientSlider extends StatelessWidget {
  final double value;
  final List<Color> gradient;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  const _GradientSlider({
    required this.value,
    required this.gradient,
    required this.thumbColor,
    required this.onChanged,
  });

  static const _thumb = 24.0;
  static const _track = 14.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        void handle(double dx) =>
            onChanged(((dx - _thumb / 2) / (w - _thumb)).clamp(0.0, 1.0));
        return GestureDetector(
          onTapDown: (d) => handle(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => handle(d.localPosition.dx),
          child: SizedBox(
            height: _thumb,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: _track,
                  margin: const EdgeInsets.symmetric(horizontal: _thumb / 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_track / 2),
                    gradient: LinearGradient(colors: gradient),
                  ),
                ),
                Positioned(
                  left: value.clamp(0.0, 1.0) * (w - _thumb),
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IconChoice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : PocketColors.paper2,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: color, width: 2)
              : Border.all(color: PocketColors.line, width: 1),
        ),
        child: Icon(icon,
            size: 22, color: selected ? color : PocketColors.inkSoft),
      ),
    );
  }
}
