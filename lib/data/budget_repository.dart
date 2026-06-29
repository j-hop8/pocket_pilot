import '../core/supabase.dart';
import '../models/budget.dart';

class BudgetRepository {
  /// All of the signed-in user's budgets (overall + per-category).
  Future<List<Budget>> list() async {
    final rows =
        await supabase.from('budgets').select().order('id', ascending: true);
    return rows.map((r) => Budget.fromJson(r)).toList();
  }

  /// Create a budget. `user_id` self-fills from the DEFAULT auth.uid().
  /// [categoryId] null creates the overall budget.
  Future<void> create({int? categoryId, required int amountCents}) async {
    await supabase.from('budgets').insert({
      'category_id': categoryId,
      'amount': amountCents,
    });
  }

  Future<void> update(int id, {required int amountCents}) async {
    await supabase.from('budgets').update({
      'amount': amountCents,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> delete(int id) async {
    await supabase.from('budgets').delete().eq('id', id);
  }
}
