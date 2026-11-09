import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Зрозумілий текст помилки входу. Раніше будь-яка помилка показувалась як
/// «перевірте інтернет», і справжня причина (вимкнений провайдер, CAPTCHA, ліміт)
/// губилась. Тут — розпізнавання за кодом Supabase Auth.
///
/// [action] — що намагався зробити користувач: «увійти через Google» тощо.
String authErrorMessage(Object error, {required String action}) {
  if (error is SocketException || error is TimeoutException || error is AuthRetryableFetchException) {
    return 'Немає зв\'язку з сервером. Перевірте інтернет і спробуйте ще раз.';
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'anonymous_provider_disabled':
        return 'Вхід без реєстрації вимкнено на сервері (Supabase → Authentication → Sign In / Providers → Anonymous).';
      case 'provider_disabled':
        return 'Цей спосіб входу вимкнено на сервері.';
      case 'captcha_failed':
        return 'Сервер вимагає CAPTCHA для входу. Вимкніть CAPTCHA в Supabase або додайте її в застосунок.';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'Забагато спроб входу. Спробуйте через кілька хвилин.';
    }
    final details = [
      if (error.statusCode != null) 'HTTP ${error.statusCode}',
      if (error.code != null) error.code!,
    ].join(', ');
    return 'Не вдалося $action: ${error.message}${details.isEmpty ? '' : ' ($details)'}';
  }
  return 'Не вдалося $action. Спробуйте ще раз.';
}
