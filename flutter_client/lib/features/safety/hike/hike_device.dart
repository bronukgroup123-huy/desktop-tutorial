import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:flutter_client/features/safety/hike/hike_geo.dart';

/// Можливості телефона для походу (ADR-022 §22.3 п.3, 4, 11, 13): місце, курс компаса, заряд,
/// сповіщення, голос. Усе — на телефоні, без сервера (гостю теж). У тестах — підміна.
abstract class HikeDevice {
  /// Потік місць для треку. [economy] — рідше (батарея < 20 %). Поки потік слухають, Android
  /// показує постійне сповіщення «Похід триває» — трек пишеться й з вимкненим екраном.
  Stream<TrackPoint> positions({required bool economy});

  /// Магнітний курс телефона 0…360°; `null` у потоці — датчиків немає / телефон «на ребрі».
  Stream<double?> heading();

  /// Заряд батареї, %; `null` — невідомо.
  Future<int?> battery();

  Future<void> notify(int id, String title, String body);

  Future<void> speak(String text);

  /// Чи є дозвіл на геолокацію (за потреби — попросити).
  Future<bool> ensureLocation();
}

class PhoneHikeDevice implements HikeDevice {
  static const _battery = MethodChannel('mushroomradar/battery');
  FlutterLocalNotificationsPlugin? _notifications;
  FlutterTts? _tts;

  @override
  Future<bool> ensureLocation() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<TrackPoint> positions({required bool economy}) => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: economy ? 25 : 10,
          intervalDuration: Duration(seconds: economy ? 30 : 10),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Похід триває',
            notificationText: 'Записуємо шлях, щоб ви повернулися тим самим маршрутом',
            enableWakeLock: true,
          ),
        ),
      ).map((p) => (lat: p.latitude, lng: p.longitude, t: p.timestamp, acc: p.accuracy));

  @override
  Stream<double?> heading() {
    List<double>? g, m;
    final out = StreamController<double?>();
    final subs = <StreamSubscription<dynamic>>[];
    void emit() {
      if (g != null && m != null) out.add(headingFromSensors(g!, m!));
    }

    try {
      subs.add(accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
        g = [e.x, e.y, e.z];
        emit();
      }, onError: (_) => out.add(null)));
      subs.add(magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
        m = [e.x, e.y, e.z];
        emit();
      }, onError: (_) => out.add(null)));
    } catch (_) {
      out.add(null);
    }
    out.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };
    return out.stream;
  }

  @override
  Future<int?> battery() async {
    try {
      return await _battery.invokeMethod<int>('level');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> notify(int id, String title, String body) async {
    try {
      final n = _notifications ??= FlutterLocalNotificationsPlugin();
      await n.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await n
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await n.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('hike', 'Похід', channelDescription: 'Час повертатися, батарея', importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (_) {
      // Сповіщення недоступні — підказка лишається на екрані.
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      final t = _tts ??= FlutterTts();
      await t.setLanguage('uk-UA');
      await t.speak(text);
    } catch (_) {}
  }
}

final hikeDeviceProvider = Provider<HikeDevice>((ref) => PhoneHikeDevice());
