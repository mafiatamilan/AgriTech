import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';

/// Initializes Supabase (auth + realtime + storage) and exposes the
/// auth session / user convenience getters used across the app.
Future<void> initSupabase() async {
  assert(AppConfig.supabaseUrl.isNotEmpty && AppConfig.supabaseAnonKey.isNotEmpty,
      'Set SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define');
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    debug: false,
  );
}

class AuthService {
  Future<void> signOut() => supabase.auth.signOut();

  User? get user => supabase.auth.currentUser;
}
