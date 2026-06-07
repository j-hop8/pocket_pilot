import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/categories.dart';
import '../core/settings_provider.dart';
import '../models/category.dart';

/// Small colored chip showing a category. Tap is optional (used in pickers /
/// future override UI). Pass a resolved [Category]; null renders "Uncategorized".
class CategoryBadge extends ConsumerWidget {
  final Category? category;
  final VoidCallback? onTap;

  const CategoryBadge({super.key, required this.category, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final style = styleForKey(category?.key);
    final label = s.categoryName(category?.key);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: style.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: chip,
    );
  }
}
