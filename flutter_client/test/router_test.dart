import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data/models_test.dart' show meJson;

void main() {
  final onboardingMe = Me.fromJson(meJson(nextStep: 'select_region'));
  final readyMe = Me.fromJson(meJson(region: {'id': 10, 'slug': 'kyivska', 'name': 'Київська'}));

  String? go({bool authLoading = false, bool signedIn = true, AsyncValue<Me?>? me, required String at}) =>
      resolveRedirect(
        authLoading: authLoading,
        signedIn: signedIn,
        me: me ?? AsyncData(readyMe),
        location: at,
      );

  test('сесія відновлюється → splash', () => expect(go(authLoading: true, at: '/map'), Routes.splash));
  test('без сесії → екран входу', () => expect(go(signedIn: false, at: '/map'), Routes.auth));
  test('без сесії на екрані входу — лишаємось', () => expect(go(signedIn: false, at: Routes.auth), isNull));
  test('профіль вантажиться → splash', () => expect(go(me: const AsyncLoading(), at: Routes.auth), Routes.splash));
  test('помилка профілю → splash (з кнопкою «Повторити»)',
      () => expect(go(me: AsyncError(Exception('x'), StackTrace.empty), at: '/map'), Routes.splash));
  test('сервер каже select_region → онбординг, карта недоступна',
      () => expect(go(me: AsyncData(onboardingMe), at: '/map'), Routes.onboarding));
  test('онбординг завершено → карта', () => expect(go(at: Routes.onboarding), Routes.map));
  test('онбординг завершено, вже на вкладці — лишаємось', () => expect(go(at: '/profile'), isNull));
}
