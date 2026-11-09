/// Конфігурація Supabase — з `--dart-define-from-file=.env` (див. `.env.example`).
///
/// Лише публічні значення (URL і publishable/anon key). Секрети в клієнт не потрапляють.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Базовий URL Edge Functions: `<SUPABASE_URL>/functions/v1`.
  static String get functionsUrl => '$url/functions/v1';

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
