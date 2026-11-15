import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_client/data/api/api_client.dart';

/// Push-сповіщення «Почалась хвиля» (ADR-015 §15.8 п.19). Firebase вмикається, лише коли в
/// збірці є його налаштування (google-services.json із секрету CI); інакше [available] = false
/// і застосунок працює без сповіщень — картка «Сповіщати про хвилі» не показується.
class PushService {
  PushService._();

  static bool _available = false;

  /// Firebase налаштовано в цій збірці.
  static bool get available => _available;

  @visibleForTesting
  static set availableForTest(bool v) => _available = v;

  /// Ініціалізувати Firebase (без налаштувань — тихо вимкнено).
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  /// Дозвіл на сповіщення + токен пристрою на сервер. Відповідь сервера: чи доступні
  /// сповіщення (Pro або «Слідопит») і пояснення, якщо ні. `null` — дозволу немає / збій.
  static Future<({bool allowed, String? lockedLabel})?> enable(ApiClient api, {bool waveAlerts = true}) async {
    if (!_available) return null;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
      // Реєстраційний токен FCM (не FID): серверна відправка (firebase-admin send({token}))
      // працює саме з ним.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return null;
      final res = await _register(api, token, waveAlerts);
      // Токен може змінитися — перереєструвати.
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => _register(api, t, waveAlerts));
      return res;
    } catch (_) {
      return null;
    }
  }

  static Future<({bool allowed, String? lockedLabel})> _register(ApiClient api, String token, bool waveAlerts) async {
    final data = await api.put('/v1-analysis/push', body: {
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'wave_alerts': waveAlerts,
    }) as Map<String, dynamic>;
    return (allowed: data['allowed'] == true, lockedLabel: data['locked_label'] as String?);
  }
}
