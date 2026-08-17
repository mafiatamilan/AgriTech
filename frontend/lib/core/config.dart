/// Build-time configuration via --dart-define.
///
/// Provide at build/run time:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
///               --dart-define=SUPABASE_URL=... \
///               --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const deepLinkScheme = String.fromEnvironment(
    'DEEP_LINK_SCHEME',
    defaultValue: 'io.agritech.app',
  );

  /// The OAuth redirect URI used with Google sign-in.
  static const oauthRedirectUri = 'io.agritech.app://login-callback';
}