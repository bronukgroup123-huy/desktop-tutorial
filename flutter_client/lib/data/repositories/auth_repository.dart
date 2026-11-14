import 'package:supabase_flutter/supabase_flutter.dart';

/// Вхід / вихід через Supabase Auth.
///
/// Гість (ADR-001) — Anonymous Sign-In: реальний UUID і JWT. Після реєстрації UUID
/// не змінюється, тому дані гостя не губляться.
class AuthRepository {
  AuthRepository(this._auth);

  final GoTrueClient _auth;

  Session? get currentSession => _auth.currentSession;
  String? get accessToken => _auth.currentSession?.accessToken;
  bool get isSignedIn => _auth.currentSession != null;
  String? get userId => _auth.currentSession?.user.id;
  bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  /// «Продовжити як гість».
  Future<void> signInAsGuest() => _auth.signInAnonymously();

  /// Google OAuth. [redirectTo] — deep link застосунку (мобільний) або origin (web).
  /// Сторінка входу відкривається у зовнішньому браузері: Google блокує вхід у
  /// вбудованих WebView, а повернення в застосунок іде через deep link.
  Future<void> signInWithGoogle({required String redirectTo}) => _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: const {'prompt': 'select_account'},
      );

  /// Гість → зареєстрований Google-акаунт зі збереженням UUID і даних (ADR-001).
  Future<void> linkGoogle({required String redirectTo}) => _auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

  Future<void> signOut() => _auth.signOut();
}
