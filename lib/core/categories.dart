import 'package:flutter/material.dart';

import '../models/category.dart';
import 'theme.dart';

class CategoryStyle {
  final Color color;
  final IconData icon;
  const CategoryStyle(this.color, this.icon);
}

// Income — green/teal family (salary uses PocketColors.pine, the dashboard
// income/positive colour). All income categories read as one green family.
const _emerald = Color(0xFF2F9E6B);
const _forest  = Color(0xFF1E6E50);
const _leaf    = Color(0xFF7BA66A);
const _seafoam = Color(0xFF5FA88B);
const _sage    = Color(0xFF6B8A80);
// Expense — brand hues + brightness/saturation siblings, no green (so green
// unambiguously means income). dining uses PocketColors.persimmon, other inkSoft.
const _terracotta = Color(0xFFC2632E); // persimmon darkened
const _steel      = Color(0xFF4A90A4); // existing accent
const _sky        = Color(0xFF79B3C4); // steel lightened
const _rose       = Color(0xFFCF7E94); // blush darkened/saturated
const _red        = Color(0xFFB85C5C); // existing health accent
const _gold       = Color(0xFFBC8E2A); // butter darkened
const _amber      = Color(0xFFE3B441); // butter brightened
const _purple     = Color(0xFF7C75C6); // existing edu accent

// Colour signals income (green family) vs expense (warm/brand hues). Icons unchanged.
const Map<String, CategoryStyle> categoryStyles = {
  'dining':        CategoryStyle(PocketColors.persimmon, Icons.restaurant_outlined),
  'groceries':     CategoryStyle(_terracotta,           Icons.shopping_cart_outlined),
  'transport':     CategoryStyle(_steel,                Icons.directions_bus_outlined),
  'shopping':      CategoryStyle(_gold,                 Icons.shopping_bag_outlined),
  'entertainment': CategoryStyle(_rose,                 Icons.movie_outlined),
  'health':        CategoryStyle(_red,                  Icons.local_hospital_outlined),
  'utilities':     CategoryStyle(_amber,                Icons.bolt_outlined),
  'education':     CategoryStyle(_purple,               Icons.school_outlined),
  'travel':        CategoryStyle(_sky,                  Icons.flight_outlined),
  'other':         CategoryStyle(PocketColors.inkSoft,  Icons.category_outlined),
  // Income categories — distinct shades within the green family.
  'salary':        CategoryStyle(PocketColors.pine,     Icons.payments_outlined),
  'bonus':         CategoryStyle(_emerald,              Icons.card_giftcard_outlined),
  'investment':    CategoryStyle(_forest,               Icons.trending_up),
  'refund':        CategoryStyle(_leaf,                 Icons.undo),
  'gift':          CategoryStyle(_seafoam,              Icons.redeem_outlined),
  'other_income':  CategoryStyle(_sage,                 Icons.savings_outlined),
};

const CategoryStyle fallbackCategoryStyle =
    CategoryStyle(PocketColors.inkSoft, Icons.category_outlined);

CategoryStyle styleForKey(String? key) =>
    categoryStyles[key] ?? fallbackCategoryStyle;

// ─────────────────────────────────────────────────────────────────────────────
// User-editable categories: name-keyed icon allow-list + palette for the picker,
// and resolution of a stored icon/color (custom) vs the built-in style map.

/// Icons a user can choose from when creating/editing a category. The name is
/// what gets stored in `categories.icon`; it is a superset of the built-in icons
/// so an edited built-in keeps a sensible default in the grid.
const Map<String, IconData> categoryIcons = {
  'restaurant':  Icons.restaurant_outlined,
  'cart':        Icons.shopping_cart_outlined,
  'bag':         Icons.shopping_bag_outlined,
  'bus':         Icons.directions_bus_outlined,
  'car':         Icons.directions_car_outlined,
  'flight':      Icons.flight_outlined,
  'movie':       Icons.movie_outlined,
  'music':       Icons.music_note_outlined,
  'sports':      Icons.sports_basketball_outlined,
  'hospital':    Icons.local_hospital_outlined,
  'fitness':     Icons.fitness_center_outlined,
  'bolt':        Icons.bolt_outlined,
  'home':        Icons.home_outlined,
  'phone':       Icons.phone_iphone_outlined,
  'school':      Icons.school_outlined,
  'book':        Icons.menu_book_outlined,
  'pet':         Icons.pets_outlined,
  'coffee':      Icons.local_cafe_outlined,
  'gift':        Icons.card_giftcard_outlined,
  'redeem':      Icons.redeem_outlined,
  'payments':    Icons.payments_outlined,
  'trending_up': Icons.trending_up,
  'savings':     Icons.savings_outlined,
  'undo':        Icons.undo,
  'wallet':      Icons.account_balance_wallet_outlined,
  'category':    Icons.category_outlined,
};

/// Colors offered in the category editor — the same on-brand vocabulary used by
/// the built-in styles: expense hues + a couple of income greens + neutral.
const List<Color> categoryPalette = [
  PocketColors.persimmon, // dining
  _terracotta,            // groceries
  _gold,                  // shopping
  _amber,                 // utilities
  _rose,                  // entertainment
  _red,                   // health
  _purple,                // education
  _steel,                 // transport
  _sky,                   // travel
  PocketColors.pine,      // income (salary)
  _emerald,               // income
  PocketColors.inkSoft,   // other / neutral
];

IconData iconByName(String? name) =>
    categoryIcons[name] ?? fallbackCategoryStyle.icon;

/// Parses a '#RRGGBB' string into a [Color]; falls back to the neutral ink color.
Color colorFromHex(String? hex) {
  if (hex == null) return fallbackCategoryStyle.color;
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallbackCategoryStyle.color : Color(v);
}

/// '#RRGGBB' for a palette [Color], used when saving a chosen color.
String hexFromColor(Color color) {
  int c(double channel) => (channel * 255).round() & 0xff;
  final rgb = (c(color.r) << 16) | (c(color.g) << 8) | c(color.b);
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Style for a category: a custom row's stored icon/color wins; otherwise the
/// built-in style map keyed by [Category.key] (so untouched defaults stay curated).
CategoryStyle styleForCategory(Category? c) {
  if (c == null) return fallbackCategoryStyle;
  if (c.icon != null && c.color != null) {
    return CategoryStyle(colorFromHex(c.color), iconByName(c.icon));
  }
  return styleForKey(c.key);
}
