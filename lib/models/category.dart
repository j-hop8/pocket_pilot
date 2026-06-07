class Category {
  final int id;
  final String key;
  final String label;
  final String kind; // 'expense' | 'income'

  const Category({
    required this.id,
    required this.key,
    required this.label,
    this.kind = 'expense',
  });

  bool get isIncome => kind == 'income';

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int,
        key: json['key'] as String,
        label: json['label'] as String,
        kind: json['kind'] as String? ?? 'expense',
      );
}
