import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared Supabase client. Repositories are the only place that touch this.
SupabaseClient get supabase => Supabase.instance.client;
