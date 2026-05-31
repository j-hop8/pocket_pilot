class Category {
  final int id;
  final String key;
  final String label;

  const Category({required this.id, required this.key, required this.label});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int,
        key: json['key'] as String,
        label: json['label'] as String,
      );
}
