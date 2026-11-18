import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/safety/hike/hike_device.dart';
import 'package:flutter_client/features/safety/hike/hike_geo.dart';

/// Точка маршруту: машина / старт, вхід у ліс, місце.
typedef RoutePoint = ({double lat, double lng, String label});

enum HikeStatus { none, active }

/// Повернення: «За маршрутом» — назад по треку; «Новий маршрут» — компасом прямо до точки.
enum ReturnMode { track, direct }

/// Похід (ADR-022 §22.3 п.4): маршрут (без нього похід не почати), трек від старту, повернення.
/// Лише на телефоні — гостю теж; трек Наглядачу — коли буде Наглядач (§22.2).
class HikeState {
  const HikeState({
    this.route = const [],
    this.status = HikeStatus.none,
    this.startedAt,
    this.track = const [],
    this.rejected = 0,
    this.returnMode,
    this.target = 0,
    this.battery,
    this.economy = false,
    this.sunsetWarned = false,
    this.batteryWarned = false,
    this.here,
    this.returnFrom,
  });

  final List<RoutePoint> route;
  final HikeStatus status;
  final DateTime? startedAt;
  final List<TrackPoint> track;

  /// Точок не взято: погана точність GPS або «стрибок» (глушіння / підміна сигналу).
  final int rejected;
  final ReturnMode? returnMode;

  /// Індекс точки маршруту — ціль для «Новий маршрут» (0 — старт).
  final int target;
  final int? battery;

  /// Економний запис треку (батарея ≤ 20 %).
  final bool economy;
  final bool sunsetWarned;
  final bool batteryWarned;

  /// Останнє добре місце (точність ≤ 100 м) — для компаса; не зберігається.
  final TrackPoint? here;

  /// Скільки точок треку було на початку повернення: «За маршрутом» веде назад саме по
  /// шляху ДО цього моменту (зворотний шлях теж пишеться, але не в ціль).
  final int? returnFrom;

  /// Шлях туди — для «За маршрутом».
  List<TrackPoint> get outbound => track.sublist(0, (returnFrom ?? track.length).clamp(0, track.length));

  bool get active => status == HikeStatus.active;
  bool get hasRoute => route.isNotEmpty;

  /// Довжина пройденого шляху, м.
  double get walkedM => track.length < 2 ? 0 : trackLengthToStart(track, track.length - 1);

  /// Захід сонця в день походу біля старту.
  DateTime? get sunset {
    if (route.isEmpty) return null;
    return sunTimes((lat: route.first.lat, lng: route.first.lng), startedAt ?? DateTime.now())?.sunset;
  }

  HikeState copyWith({
    List<RoutePoint>? route,
    HikeStatus? status,
    DateTime? startedAt,
    bool clearStarted = false,
    List<TrackPoint>? track,
    int? rejected,
    ReturnMode? returnMode,
    bool clearReturn = false,
    int? target,
    int? battery,
    bool? economy,
    bool? sunsetWarned,
    bool? batteryWarned,
    TrackPoint? here,
    int? returnFrom,
  }) =>
      HikeState(
        route: route ?? this.route,
        status: status ?? this.status,
        startedAt: clearStarted ? null : startedAt ?? this.startedAt,
        track: track ?? this.track,
        rejected: rejected ?? this.rejected,
        returnMode: clearReturn ? null : returnMode ?? this.returnMode,
        target: target ?? this.target,
        battery: battery ?? this.battery,
        economy: economy ?? this.economy,
        sunsetWarned: sunsetWarned ?? this.sunsetWarned,
        batteryWarned: batteryWarned ?? this.batteryWarned,
        here: here ?? this.here,
        returnFrom: clearReturn ? null : returnFrom ?? this.returnFrom,
      );

  Map<String, dynamic> toJson() => {
        'route': [for (final p in route) {'lat': p.lat, 'lng': p.lng, 'label': p.label}],
        'status': status.name,
        'started_at': startedAt?.toIso8601String(),
        'track': [for (final p in track) [p.lat, p.lng, p.t.millisecondsSinceEpoch, p.acc]],
        'rejected': rejected,
        'return_mode': returnMode?.name,
        'target': target,
        'sunset_warned': sunsetWarned,
        'battery_warned': batteryWarned,
        'return_from': returnFrom,
      };

  factory HikeState.fromJson(Map<String, dynamic> j) => HikeState(
        route: [
          for (final p in (j['route'] as List? ?? const []).cast<Map<String, dynamic>>())
            (lat: (p['lat'] as num).toDouble(), lng: (p['lng'] as num).toDouble(), label: p['label'] as String),
        ],
        status: j['status'] == 'active' ? HikeStatus.active : HikeStatus.none,
        startedAt: DateTime.tryParse((j['started_at'] as String?) ?? ''),
        track: [
          for (final p in (j['track'] as List? ?? const []).cast<List<dynamic>>())
            (
              lat: (p[0] as num).toDouble(),
              lng: (p[1] as num).toDouble(),
              t: DateTime.fromMillisecondsSinceEpoch((p[2] as num).toInt()),
              acc: (p[3] as num).toDouble(),
            ),
        ],
        rejected: (j['rejected'] as num?)?.toInt() ?? 0,
        returnMode: ReturnMode.values.where((m) => m.name == j['return_mode']).firstOrNull,
        target: (j['target'] as num?)?.toInt() ?? 0,
        sunsetWarned: j['sunset_warned'] == true,
        batteryWarned: j['battery_warned'] == true,
        returnFrom: (j['return_from'] as num?)?.toInt(),
      );
}

/// Сповіщення застосунку (id).
const kSunsetNotification = 7001;
const kBatteryNotification = 7002;

/// Похід: маршрут → «Почати похід» (запис треку) → «Повернутися» → «Я вдома».
class HikeController extends Notifier<HikeState> {
  static const storeKey = 'hike';
  StreamSubscription<TrackPoint>? _sub;
  Timer? _saveTimer;
  DateTime? _lastBatteryCheck;

  /// Користувач уже щось змінив — збережений стан не відновлюємо поверх (гонка з читанням).
  bool _touched = false;

  /// Годинник (тести).
  static DateTime Function() now = DateTime.now;

  @override
  HikeState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _saveTimer?.cancel();
    });
    Future.microtask(_restore);
    return const HikeState();
  }

  HikeDevice get _device => ref.read(hikeDeviceProvider);

  /// Після перезапуску застосунку — той самий маршрут і трек; похід триває.
  Future<void> _restore() async {
    try {
      final e = await ref.read(localStoreProvider).read(storeKey);
      if (e?.data is! Map) return;
      final saved = HikeState.fromJson((e!.data as Map).cast<String, dynamic>());
      if (_touched) return; // уже змінили, поки читали
      state = saved;
      if (saved.active) _listen();
    } catch (_) {}
  }

  void _save({bool now = false}) {
    _touched = true;
    _saveTimer?.cancel();
    Future<void> write() async {
      try {
        await ref.read(localStoreProvider).write(storeKey, state.toJson());
      } catch (_) {}
    }

    if (now) {
      write();
    } else {
      _saveTimer = Timer(const Duration(seconds: 20), write);
    }
  }

  // ─── Маршрут ─────────────────────────────────────────────────────────────

  void addPoint(double lat, double lng, {String? label}) {
    final n = state.route.length;
    state = state.copyWith(route: [...state.route, (lat: lat, lng: lng, label: label ?? (n == 0 ? 'Старт' : 'Точка $n'))]);
    _save(now: true);
  }

  void removeLast() {
    if (state.route.isEmpty) return;
    state = state.copyWith(route: state.route.sublist(0, state.route.length - 1), target: 0);
    _save(now: true);
  }

  void clearRoute() {
    if (state.active) return;
    state = const HikeState();
    _save(now: true);
  }

  // ─── Похід ───────────────────────────────────────────────────────────────

  /// Почати похід: без маршруту — не можна (ADR-022 §22.5 п.4). `false` — немає маршруту чи дозволу.
  Future<bool> start() async {
    if (!state.hasRoute || state.active) return false;
    if (!await _device.ensureLocation()) return false;
    state = state.copyWith(status: HikeStatus.active, startedAt: now(), track: const [], rejected: 0, clearReturn: true, sunsetWarned: false, batteryWarned: false, economy: false);
    _save(now: true);
    _listen();
    return true;
  }

  void _listen() {
    _sub?.cancel();
    _sub = _device.positions(economy: state.economy).listen(_onPosition, onError: (_) {});
  }

  void _onPosition(TrackPoint p) {
    if (!state.active) return;
    final last = state.track.isEmpty ? null : state.track.last;
    final reject = checkTrackPoint(last, p);
    if (reject == null) {
      state = state.copyWith(track: [...state.track, p], here: p);
    } else if (reject == TrackReject.tooClose) {
      state = state.copyWith(here: p);
    } else if (reject != TrackReject.tooClose) {
      state = state.copyWith(rejected: state.rejected + 1);
    }
    _save();
    _checkSunset();
    _checkBattery();
  }

  /// «Час повертатися» — за годину до заходу сонця, один раз (ADR-022 §22.3 п.11).
  void _checkSunset() {
    final s = state.sunset;
    if (s == null || state.sunsetWarned || state.returnMode != null) return;
    final left = s.difference(now());
    if (left <= const Duration(hours: 1)) {
      state = state.copyWith(sunsetWarned: true);
      final mins = left.inMinutes.clamp(0, 60);
      _device.notify(kSunsetNotification, 'Час повертатися',
          mins > 0 ? 'До заходу сонця $mins хв. Увімкніть «Повернутися» на вкладці «Безпека».' : 'Сонце вже зайшло — повертайтеся.');
    }
  }

  /// Батарея ≤ 20 % — попередження й економний запис треку (ADR-022 §22.3 п.13).
  Future<void> _checkBattery() async {
    final t = now();
    if (_lastBatteryCheck != null && t.difference(_lastBatteryCheck!) < const Duration(minutes: 3)) return;
    _lastBatteryCheck = t;
    final level = await _device.battery();
    if (level == null || !state.active) return;
    state = state.copyWith(battery: level);
    if (level <= 20 && !state.economy) {
      state = state.copyWith(economy: true, batteryWarned: true);
      _device.notify(kBatteryNotification, 'Батарея $level %',
          'Трек пишемо рідше. Зменште яскравість і закрийте зайві застосунки — телефон потрібен, щоб повернутися.');
      _listen();
    }
  }

  /// Перевірити батарею зараз (вкладка відкрилась).
  Future<void> refreshBattery() async {
    _lastBatteryCheck = null;
    await _checkBattery();
  }

  void startReturn(ReturnMode mode, {int target = 0}) {
    state = state.copyWith(
      returnMode: mode,
      target: target.clamp(0, state.route.isEmpty ? 0 : state.route.length - 1),
      returnFrom: state.returnFrom ?? state.track.length,
    );
    _save(now: true);
  }

  void stopReturn() {
    state = state.copyWith(clearReturn: true);
    _save(now: true);
  }

  /// «Я вдома»: зупинити запис і стерти трек і маршрут (лише на телефоні — нікуди не надсилались).
  Future<void> finish() async {
    final sub = _sub;
    _sub = null;
    state = const HikeState();
    _save(now: true);
    await sub?.cancel();
  }

  /// Для тестів: передати точку напряму.
  void debugPosition(TrackPoint p) => _onPosition(p);
}

final hikeProvider = NotifierProvider<HikeController, HikeState>(HikeController.new);

/// Мапа: дотик додає точку маршруту (режим «Створити маршрут на карті»).
final routeEditProvider = StateProvider<bool>((ref) => false);
