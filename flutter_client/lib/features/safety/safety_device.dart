import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Місце телефона для «Мої координати» / SOS: координати й точність, м.
class SafetyFix {
  const SafetyFix({required this.lat, required this.lng, required this.accuracyM});

  final double lat;
  final double lng;
  final double accuracyM;

  /// Гірше за 100 м — можливі глушіння / підміна GPS (ADR-022 §22.5 п.5) або густий ліс.
  bool get lowAccuracy => accuracyM > 100;

  /// «50.45123, 30.52341» — так диктують диспетчеру 112.
  String get decimal => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  /// «50°27′04.4″ пн. ш., 30°31′24.3″ сх. д.»
  String get dms => '${_dms(lat)} ${lat >= 0 ? 'пн. ш.' : 'пд. ш.'}, ${_dms(lng)} ${lng >= 0 ? 'сх. д.' : 'зх. д.'}';

  static String _dms(double v) {
    final a = v.abs();
    var d = a.floor();
    var m = ((a - d) * 60).floor();
    var s = double.parse(((a - d - m / 60) * 3600).toStringAsFixed(1));
    if (s >= 60) {
      s = 0;
      m++;
    }
    if (m >= 60) {
      m = 0;
      d++;
    }
    return '$d°${m.toString().padLeft(2, '0')}′${s.toStringAsFixed(1).padLeft(4, '0')}″';
  }
}

/// Чому координат немає.
enum LocateError { denied, unavailable }

/// Можливості телефона для вкладки «Безпека» — усе працює без сервера й без акаунта (гостю теж,
/// ADR-001 уточнення 2026-11-17). У тестах — підміна.
abstract class SafetyDevice {
  Future<void> dial(String number);
  Future<({SafetyFix? fix, LocateError? error})> locate();
  Future<void> copy(String text);

  /// Сирена (гучний тон, що наростає й спадає, по колу).
  Future<void> siren(bool on);

  /// Ліхтарик (спалах камери). `false` — на цьому телефоні немає / не вдалося.
  Future<bool> torch(bool on);

  /// Екран не гасне, поки йде сигнал.
  Future<void> keepAwake(bool on);
}

class PhoneSafetyDevice implements SafetyDevice {
  AudioPlayer? _player;
  CameraController? _camera;

  @override
  Future<void> dial(String number) async {
    await launchUrl(Uri(scheme: 'tel', path: number));
  }

  @override
  Future<({SafetyFix? fix, LocateError? error})> locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return (fix: null, error: LocateError.denied);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 25)),
      );
      return (fix: SafetyFix(lat: pos.latitude, lng: pos.longitude, accuracyM: pos.accuracy), error: null);
    } catch (_) {
      // Немає супутників — останнє відоме місце краще, ніж нічого.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return (fix: SafetyFix(lat: last.latitude, lng: last.longitude, accuracyM: math.max(last.accuracy, 101)), error: null);
        }
      } catch (_) {}
      return (fix: null, error: LocateError.unavailable);
    }
  }

  @override
  Future<void> copy(String text) => Clipboard.setData(ClipboardData(text: text));

  @override
  Future<void> siren(bool on) async {
    if (!on) {
      await _player?.stop();
      return;
    }
    final p = _player ??= AudioPlayer();
    await p.setReleaseMode(ReleaseMode.loop);
    await p.setVolume(1);
    await p.play(BytesSource(sirenWav(), mimeType: 'audio/wav'));
  }

  @override
  Future<bool> torch(bool on) async {
    try {
      if (!on) {
        await _camera?.setFlashMode(FlashMode.off);
        return true;
      }
      if (_camera == null) {
        final cams = await availableCameras();
        final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull;
        if (back == null) return false;
        final c = CameraController(back, ResolutionPreset.low, enableAudio: false);
        await c.initialize();
        _camera = c;
      }
      await _camera!.setFlashMode(FlashMode.torch);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> keepAwake(bool on) async {
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {}
  }

  /// Звільнити камеру й плеєр, коли сигнал вимкнено.
  Future<void> release() async {
    final c = _camera;
    _camera = null;
    await c?.dispose();
    await _player?.dispose();
    _player = null;
  }
}

final safetyDeviceProvider = Provider<SafetyDevice>((ref) {
  final d = PhoneSafetyDevice();
  ref.onDispose(d.release);
  return d;
});

/// Сирена: 16-біт моно WAV, тон 700 → 1400 → 700 Гц за [seconds] (по колу — безперервне виття).
Uint8List sirenWav({int sampleRate = 16000, double seconds = 1.2}) {
  final n = (sampleRate * seconds).round();
  final data = ByteData(44 + n * 2);
  void str(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // моно
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / n; // 0…1 — один «вий»
    final freq = 1050 - 350 * math.cos(2 * math.pi * t);
    phase += 2 * math.pi * freq / sampleRate;
    // Трохи «квадратний» тон — чутніший у лісі.
    final v = (math.sin(phase) * 1.6).clamp(-1.0, 1.0) * 0.9;
    data.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Світловий сигнал SOS азбукою Морзе (··· — — — ···): кроки «світло / темно» з тривалістю.
/// Крапка — [unit], тире — 3 одиниці, пауза між знаками — 1, між літерами — 3, після слова — 7.
List<({bool on, Duration d})> morseSos({Duration unit = const Duration(milliseconds: 250)}) {
  final out = <({bool on, Duration d})>[];
  void sign(int units) {
    out.add((on: true, d: unit * units));
    out.add((on: false, d: unit));
  }

  void letterGap() => out[out.length - 1] = (on: false, d: unit * 3);
  for (final letter in const [
    [1, 1, 1],
    [3, 3, 3],
    [1, 1, 1],
  ]) {
    letter.forEach(sign);
    letterGap();
  }
  out[out.length - 1] = (on: false, d: unit * 7);
  return out;
}

/// Екстрені служби (ADR-022 §22.3 п.15).
const kEmergencyNumbers = <({String number, String title, String note})>[
  (number: '112', title: 'Єдиний номер екстреної допомоги', note: 'Будь-яка небезпека; дзвінок безкоштовний'),
  (number: '101', title: 'ДСНС — рятувальники', note: 'Заблукали, пожежа, нещасний випадок'),
  (number: '102', title: 'Поліція', note: ''),
  (number: '103', title: 'Швидка допомога', note: 'Отруєння грибами, травма'),
];
