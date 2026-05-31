import '../core/supabase.dart';
import '../models/category.dart';

class CategoryRepository {
  Future<List<Category>> list() async {
    final rows = await supabase.from('categories').select().order('id');
    return rows.map((r) => Category.fromJson(r)).toList();
  }
}
