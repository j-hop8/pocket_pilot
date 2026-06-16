import 'dart:math';

import '../core/supabase.dart';
import '../models/category.dart';

class CategoryRepository {
  /// All of the signed-in user's categories. On first use (a brand-new account
  /// with no rows) the default set is seeded, then re-read.
  Future<List<Category>> list() async {
    // ascending: the postgrest-dart `order` defaults to DESC, which would list
    // categories newest-id first (income before expense, seed order reversed).
    // Ascending keeps the seed order: expense categories first, then income.
    var rows =
        await supabase.from('categories').select().order('id', ascending: true);
    if (rows.isEmpty) {
      await _seedDefaults();
      rows = await supabase
          .from('categories')
          .select()
          .order('id', ascending: true);
    }
    return rows.map((r) => Category.fromJson(r)).toList();
  }

  /// Create a user category. `user_id` self-fills from the DEFAULT auth.uid().
  Future<Category> create({
    required String name,
    required String kind,
    required String iconName,
    required String colorHex,
  }) async {
    final row = await supabase
        .from('categories')
        .insert({
          'key': _customKey(),
          'label': name,
          'kind': kind,
          'icon': iconName,
          'color': colorHex,
        })
        .select()
        .single();
    return Category.fromJson(row);
  }

  /// Edit a category. The `key` is deliberately left untouched — even for a
  /// built-in — so auto-categorization (which resolves categorizer keys → ids)
  /// keeps working after a rename. Storing icon/color is what makes an edited
  /// built-in render with the user's chosen name/style (see Category.isBuiltin).
  Future<void> update(
    int id, {
    required String name,
    required String iconName,
    required String colorHex,
  }) async {
    await supabase.from('categories').update({
      'label': name,
      'icon': iconName,
      'color': colorHex,
    }).eq('id', id);
  }

  /// Delete a category. Records using it become uncategorized (FK ON DELETE SET NULL).
  Future<void> delete(int id) async {
    await supabase.from('categories').delete().eq('id', id);
  }

  // ── helpers ──────────────────────────────────────────────────────────────────

  String _customKey() =>
      'c_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

  Future<void> _seedDefaults() async {
    await supabase.from('categories').insert(_defaultSeed);
  }
}

/// The starter set handed to a new account. icon/color are left unset so they
/// render via the in-app style map keyed by `key` (matching the old global seed).
const List<Map<String, String>> _defaultSeed = [
  {'key': 'groceries',     'label': 'Groceries 超市',         'kind': 'expense'},
  {'key': 'dining',        'label': 'Dining 餐飲',            'kind': 'expense'},
  {'key': 'transport',     'label': 'Transport 交通',         'kind': 'expense'},
  {'key': 'entertainment', 'label': 'Entertainment 娛樂',     'kind': 'expense'},
  {'key': 'health',        'label': 'Health 醫療健康',        'kind': 'expense'},
  {'key': 'utilities',     'label': 'Utilities 水電費',       'kind': 'expense'},
  {'key': 'shopping',      'label': 'Shopping 購物',          'kind': 'expense'},
  {'key': 'education',     'label': 'Education 教育',         'kind': 'expense'},
  {'key': 'travel',        'label': 'Travel 旅遊',            'kind': 'expense'},
  {'key': 'other',         'label': 'Other 其他',             'kind': 'expense'},
  {'key': 'salary',        'label': 'Salary 薪資',            'kind': 'income'},
  {'key': 'bonus',         'label': 'Bonus 獎金',             'kind': 'income'},
  {'key': 'investment',    'label': 'Investment 投資',        'kind': 'income'},
  {'key': 'refund',        'label': 'Refund 退款',            'kind': 'income'},
  {'key': 'gift',          'label': 'Gift 禮金',              'kind': 'income'},
  {'key': 'other_income',  'label': 'Other income 其他收入',  'kind': 'income'},
];
