import '../core/supabase.dart';
import '../models/trip.dart';

/// The only place trip rows are read/written. RLS scopes every query to the
/// signed-in user; `user_id` self-fills from auth.uid() on insert.
class TripRepository {
  /// All of the user's trips, most recent first.
  Future<List<Trip>> list() async {
    final rows = await supabase
        .from('trips')
        .select()
        .order('start_date', ascending: false);
    return rows.map((r) => Trip.fromJson(r)).toList();
  }

  Future<Trip> create(Trip trip) async {
    final row = await supabase
        .from('trips')
        .insert(trip.toInsertJson())
        .select()
        .single();
    return Trip.fromJson(row);
  }

  Future<void> update(Trip trip) async {
    await supabase.from('trips').update(trip.toUpdateJson()).eq('id', trip.id!);
  }

  /// Deletes the trip. Linked invoices keep their data; their `trip_id` is set
  /// to NULL by the FK (ON DELETE SET NULL).
  Future<void> delete(String id) async {
    await supabase.from('trips').delete().eq('id', id);
  }
}
