import 'package:flutter/material.dart';

/// Visual style (color + icon) per category key. The list of categories and
/// their labels live in the DB; this is purely presentational and shared by
/// every badge/chart so colors stay consistent across screens.
class CategoryStyle {
  final Color color;
  final IconData icon;
  const CategoryStyle(this.color, this.icon);
}

const Map<String, CategoryStyle> categoryStyles = {
  'groceries': CategoryStyle(Color(0xFF4CAF50), Icons.shopping_cart),
  'dining': CategoryStyle(Color(0xFFFF7043), Icons.restaurant),
  'transport': CategoryStyle(Color(0xFF42A5F5), Icons.directions_bus),
  'entertainment': CategoryStyle(Color(0xFFAB47BC), Icons.movie),
  'health': CategoryStyle(Color(0xFFEF5350), Icons.local_hospital),
  'utilities': CategoryStyle(Color(0xFF26A69A), Icons.bolt),
  'shopping': CategoryStyle(Color(0xFFEC407A), Icons.shopping_bag),
  'education': CategoryStyle(Color(0xFF5C6BC0), Icons.school),
  'travel': CategoryStyle(Color(0xFF29B6F6), Icons.flight),
  'other': CategoryStyle(Color(0xFF78909C), Icons.category),
};

const CategoryStyle fallbackCategoryStyle =
    CategoryStyle(Color(0xFF78909C), Icons.category);

CategoryStyle styleForKey(String? key) =>
    categoryStyles[key] ?? fallbackCategoryStyle;
