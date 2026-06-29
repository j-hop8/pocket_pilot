/// A recurring monthly spending limit. [categoryId] null means the overall
/// budget (the total monthly cap); otherwise it's the limit for that expense
/// category. [amount] is the limit in TWD cents. Budgets carry no month — the
/// dashboard compares them against the spending of the month it's showing.
class Budget {
  final int id;
  final int? categoryId;
  final int amount; // cents

  const Budget({
    required this.id,
    required this.categoryId,
    required this.amount,
  });

  bool get isOverall => categoryId == null;

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        id: json['id'] as int,
        categoryId: json['category_id'] as int?,
        amount: json['amount'] as int,
      );
}
