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

  /// Deep link, на який Supabase повертає користувача після OAuth (Google).
  /// Схема — власна для застосунку (= applicationId), щоб не перетинатися з іншими
  /// застосунками на Supabase. Має збігатися з intent-filter в AndroidManifest.xml
  /// і бути в Supabase → Authentication → URL Configuration → Redirect URLs.
  static const String authRedirectUrl = 'ua.mushroomradar.app://login-callback/';
}
