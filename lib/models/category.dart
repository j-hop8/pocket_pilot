/// The keys of the built-in (seeded) categories. A category whose [Category.key]
/// is in this set is rendered via the in-app localized name + style maps; any
/// other key is a user-created/edited category that carries its own label/icon/color.
const Set<String> builtinCategoryKeys = {
  // expense
  'groceries', 'dining', 'transport', 'entertainment', 'health',
  'utilities', 'shopping', 'education', 'travel', 'other',
  // income
  'salary', 'bonus', 'investment', 'refund', 'gift', 'other_income',
};

class Category {
  final int id;
  final String key;
  final String label;
  final String kind; // 'expense' | 'income'
  final String? userId;
  final String? icon;  // icon name (see categoryIcons); null => use the code style map
  final String? color; // '#RRGGBB'; null => use the code style map

  const Category({
    required this.id,
    required this.key,
    required this.label,
    this.kind = 'expense',
    this.userId,
    this.icon,
    this.color,
  });

  bool get isIncome => kind == 'income';

  /// An *untouched* seeded category: a built-in key the user hasn't customized
  /// (rendered via the localized name + curated style map). Editing one stores an
  /// icon/color, which flips this to false so the user's label/style take over —
  /// while the key itself stays stable so auto-categorization keeps resolving it.
  bool get isBuiltin =>
      builtinCategoryKeys.contains(key) && icon == null && color == null;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int,
        key: json['key'] as String,
        label: json['label'] as String,
        kind: json['kind'] as String? ?? 'expense',
        userId: json['user_id'] as String?,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
      );
}
