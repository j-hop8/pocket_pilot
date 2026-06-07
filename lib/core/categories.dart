import 'package:flutter/material.dart';

import 'theme.dart';

class CategoryStyle {
  final Color color;
  final IconData icon;
  const CategoryStyle(this.color, this.icon);
}

// Mapped to the Pocket palette: persimmon/pine/butter/blush as primary category colours.
const Map<String, CategoryStyle> categoryStyles = {
  'dining':        CategoryStyle(PocketColors.persimmon, Icons.restaurant_outlined),
  'groceries':     CategoryStyle(PocketColors.pine,      Icons.shopping_cart_outlined),
  'transport':     CategoryStyle(PocketColors.pine,      Icons.directions_bus_outlined),
  'shopping':      CategoryStyle(PocketColors.butter,    Icons.shopping_bag_outlined),
  'entertainment': CategoryStyle(PocketColors.blush,     Icons.movie_outlined),
  'health':        CategoryStyle(Color(0xFFB85C5C),      Icons.local_hospital_outlined),
  'utilities':     CategoryStyle(PocketColors.pine,      Icons.bolt_outlined),
  'education':     CategoryStyle(Color(0xFF7C75C6),      Icons.school_outlined),
  'travel':        CategoryStyle(PocketColors.butter,    Icons.flight_outlined),
  'other':         CategoryStyle(PocketColors.inkSoft,   Icons.category_outlined),
  // Income categories — pine (the green income family) by default.
  'salary':        CategoryStyle(PocketColors.pine,      Icons.payments_outlined),
  'bonus':         CategoryStyle(PocketColors.pine,      Icons.card_giftcard_outlined),
  'investment':    CategoryStyle(PocketColors.pine,      Icons.trending_up),
  'refund':        CategoryStyle(PocketColors.pine,      Icons.undo),
  'gift':          CategoryStyle(PocketColors.pine,      Icons.redeem_outlined),
  'other_income':  CategoryStyle(PocketColors.pine,      Icons.savings_outlined),
};

const CategoryStyle fallbackCategoryStyle =
    CategoryStyle(PocketColors.inkSoft, Icons.category_outlined);

CategoryStyle styleForKey(String? key) =>
    categoryStyles[key] ?? fallbackCategoryStyle;
