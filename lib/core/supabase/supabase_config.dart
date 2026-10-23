// lib/core/supabase/supabase_config.dart
//
// Environment / configuration for the future Supabase backend. Values come
// from compile-time defines (--dart-define), never hardcoded, and the
// publishable (anon) key is the ONLY key that ever ships in the client —
// the service-role key must never be present here. RLS on the database is
// the real security boundary; this key is not a secret.
//
// Set up:
//   flutter run --dart-define=SUPABASE_URL=https://<project>.supabase.co \
//                --dart-define=SUPABASE_ANON_KEY=<publishable-key>
// or put them in your run configuration / CI secrets.

class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// The client-side publishable (anon) key. Not a secret — RLS is the
  /// security boundary. The service-role key must never be set here.
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// True only when both values are provided. When false, BOS runs entirely
  /// on the local Drift database and no Supabase client is created.
  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// Google OAuth **Web** client ID from Google Cloud Console. Used as the
  /// `serverClientId` for google_sign_in so Android can obtain an ID token
  /// that Supabase accepts. Register this ID (plus the Android/iOS client
  /// IDs) in the Supabase dashboard Google provider settings.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  /// Google OAuth iOS client ID (only needed for iOS/macOS builds).
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  /// Native Google sign-in requires the web client ID at minimum. Client
  /// IDs are not secrets (they identify the app, they don't authorize it).
  static bool get isGoogleAuthConfigured =>
      isConfigured && googleServerClientId.isNotEmpty;
}
