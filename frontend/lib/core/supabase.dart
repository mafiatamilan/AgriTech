import 'package:supabase_flutter/supabase_flutter.dart';

/// Global access to the initialized Supabase client (auth, realtime, storage).
SupabaseClient get supabase => Supabase.instance.client;