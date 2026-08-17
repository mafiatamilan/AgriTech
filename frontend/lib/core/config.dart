/// Build-time configuration via --dart-define.
///
/// Defaults target the AgriTech Supabase project and a local backend; override
/// for other environments:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
///               --dart-define=SUPABASE_URL=... \
///               --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.8:8000',
  );

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://enoduwmsjvpodbnrnxoi.supabase.co/',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVub2R1d21zanZwb2RibnJueG9pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY4OTU3MDUsImV4cCI6MjEwMjQ3MTcwNX0.8TvXG6LmlaqVdZpr8p64dxrczBlMg1gdgtM7zaNXyF0',
  );

  static const deepLinkScheme = String.fromEnvironment(
    'DEEP_LINK_SCHEME',
    defaultValue: 'io.agritech.app',
  );

  /// The OAuth redirect URI used with Google sign-in.
  static const oauthRedirectUri = 'io.agritech.app://login-callback';
}