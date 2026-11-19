import 'dart:io';

import 'package:flutter_client/core/auth_errors.dart';
import 'package:flutter_client/core/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('authErrorMessage', () {
    test('вимкнений анонімний вхід — назва причини, а не «перевірте інтернет»', () {
      final msg = authErrorMessage(
        const AuthApiException('Anonymous sign-ins are disabled', statusCode: '422', code: 'anonymous_provider_disabled'),
        action: 'продовжити без реєстрації',
      );
      expect(msg, contains('вимкнено на сервері'));
      expect(msg, isNot(contains('інтернет')));
    });

    test('CAPTCHA', () {
      expect(
        authErrorMessage(const AuthApiException('captcha', statusCode: '400', code: 'captcha_failed'), action: 'x'),
        contains('CAPTCHA'),
      );
    });

    test('мережа → «перевірте інтернет»', () {
      expect(authErrorMessage(const SocketException('no route'), action: 'x'), contains('інтернет'));
      expect(authErrorMessage(AuthRetryableFetchException(message: 'fetch failed'), action: 'x'), contains('інтернет'));
    });

    test('невідомий код → повідомлення сервера з HTTP-статусом і кодом', () {
      final msg = authErrorMessage(
        const AuthApiException('Something odd', statusCode: '500', code: 'unexpected_failure'),
        action: 'увійти через Google',
      );
      expect(msg, 'Не вдалося увійти через Google: Something odd (HTTP 500, unexpected_failure)');
    });

    test('Google уже має свій акаунт (помилка з адреси повернення) — розпізнано', () {
      // getSessionFromUrl: code = error, statusCode = error_code.
      const e = AuthException('Identity is already linked to another user', statusCode: 'identity_already_exists', code: 'server_error');
      expect(isIdentityTaken(e), isTrue);
      expect(authErrorMessage(e, action: 'x'), contains('уже має свій профіль'));
      expect(isIdentityTaken(const AuthApiException('odd', statusCode: '500', code: 'unexpected_failure')), isFalse);
    });

    test('ручну прив\'язку вимкнено — куди натиснути в Supabase', () {
      const api = AuthApiException('Manual linking is disabled', statusCode: '404', code: 'manual_linking_disabled');
      const url = AuthException('Manual linking is disabled', statusCode: 'manual_linking_disabled', code: 'invalid_request');
      for (final e in [api, url]) {
        expect(authErrorMessage(e, action: 'x'), contains('Allow manual linking'));
      }
    });
  });

  test('deep link OAuth збігається з intent-filter в AndroidManifest', () {
    final uri = Uri.parse(SupabaseConfig.authRedirectUrl);
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:scheme="${uri.scheme}"'));
    expect(manifest, contains('android:host="${uri.host}"'));
    expect(manifest, contains('android.permission.INTERNET'));
    // Посилання повернення — Supabase, не маршрутизатору.
    expect(manifest, contains('android:name="flutter_deeplinking_enabled" android:value="false"'));
  });
}
