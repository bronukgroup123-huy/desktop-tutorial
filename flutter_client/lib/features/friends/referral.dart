import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_install_referrer/play_install_referrer.dart';

import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/providers.dart';

/// Запрошення через Google Play (B9.5, ADR-021 §21.4).
///
/// Посилання запрошення веде лише в Google Play: `…&referrer=ref%3D<КОД>`. Після встановлення
/// Play віддає застосунку рядок `ref=<КОД>` (Install Referrer). Один раз після входу застосунок
/// передає код серверу (`PATCH v1-me {referral_code}`); усі правила (14 днів, свій код, гість) —
/// на сервері. Веб-сторінок і даних про людину тут немає — лише код.

/// Ключ «вже перевірено» у LocalStore: читати referrer і надсилати код — лише раз.
const referralCheckedKey = 'referral_checked';

final _codeRe = RegExp(r'^[A-Za-z0-9]{6,12}$');

/// Код запрошення з рядка Install Referrer: `ref=ABCD2345` (також закодований `ref%3DABCD2345`
/// чи серед інших параметрів). Без коду (звичайне встановлення, `utm_source=…`) — `null`.
String? referralCodeFromReferrer(String? raw) {
  if (raw == null) return null;
  var text = raw.trim();
  if (text.isEmpty) return null;
  for (var i = 0; i < 2 && text.contains('%'); i++) {
    try {
      text = Uri.decodeComponent(text);
    } catch (_) {
      break; // зламане кодування — шукаємо як є
    }
  }
  for (final part in text.split('&')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    if (part.substring(0, eq).trim().toLowerCase() != 'ref') continue;
    final code = part.substring(eq + 1).trim();
    if (_codeRe.hasMatch(code)) return code.toUpperCase();
  }
  return null;
}

/// Рядок Install Referrer. Лише Android із Google Play; інакше або при помилці — `null`.
/// У тестах підміняється.
final installReferrerProvider = Provider<Future<String?> Function()>((ref) => () async {
      if (!Platform.isAndroid) return null;
      try {
        final details = await PlayInstallReferrer.installReferrer;
        return details.installReferrer;
      } catch (_) {
        return null; // немає Google Play / таймаут — встановлено не за посиланням
      }
    });

/// Один раз після входу: прочитати код запрошення й передати серверу.
/// Повертає текст для підказки («Запрошення від @Олена прийнято…») або `null`, якщо показувати нічого.
/// Без інтернету — нічого не позначає: спробуємо при наступному запуску.
Future<String?> redeemInstallReferral(WidgetRef ref) async {
  try {
    final store = ref.read(localStoreProvider);
    if (await store.read(referralCheckedKey) != null) return null;
    final code = referralCodeFromReferrer(await ref.read(installReferrerProvider)());
    if (code == null) {
      await store.write(referralCheckedKey, {'code': null});
      return null;
    }
    try {
      final r = await ref.read(meRepositoryProvider).redeemReferral(code);
      await store.write(referralCheckedKey, {'code': code, 'applied': r.applied});
      ref.read(meProvider.notifier).replace(r.me);
      if (r.applied) ref.invalidate(friendsProvider);
      return r.label;
    } on ApiException catch (e) {
      if (e.isNetworkError) return null; // повторимо при наступному запуску
      await store.write(referralCheckedKey, {'code': code, 'applied': false});
      return null;
    }
  } catch (_) {
    return null; // запрошення не повинне заважати користуватися застосунком
  }
}
