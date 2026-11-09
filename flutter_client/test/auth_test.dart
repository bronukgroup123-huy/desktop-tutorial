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
  });

  test('deep link OAuth збігається з intent-filter в AndroidManifest', () {
    final uri = Uri.parse(SupabaseConfig.authRedirectUrl);
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:scheme="${uri.scheme}"'));
    expect(manifest, contains('android:host="${uri.host}"'));
    expect(manifest, contains('android.permission.INTERNET'));
  });
}
