import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/trails_repository.dart' show trailsFilesFor;
import 'package:flutter_client/features/safety/hike/hike_device.dart';
import 'package:flutter_client/features/safety/hike/hike_geo.dart';
import 'package:flutter_client/features/safety/hike/hike_nav.dart';
import 'package:flutter_client/features/safety/hike/trails.dart';
import 'package:flutter_client/features/safety/safety_content.dart' show homeRegionSlugProvider;

/// Точка маршруту: машина / старт, вхід у ліс, місце.
typedef RoutePoint = ({double lat, double lng, String label});

enum HikeStatus { none, active }

/// Повернення (ADR-022 §22.7): «Авто» — дорогами й стежками (мережа OSM на телефоні);
/// «Своїм слідом» — назад по треку; «Навпростець» — компасом прямо до точки.
enum ReturnMode { auto, track, direct }

/// Шлях з типом кожного сегмента (дорога, лісова дорога, стежка, навпростець).
typedef PathLeg = ({List<Geo> points, List<NavKind> kinds});

List<dynamic> _legJson(PathLeg l) => [
      [for (final p in l.points) [p.lat, p.lng]],
      l.kinds,
    ];

PathLeg _legFrom(dynamic j) {
  final l = j as List;
  return (
    points: [for (final p in (l[0] as List).cast<List<dynamic>>()) (lat: (p[0] as num).toDouble(), lng: (p[1] as num).toDouble())],
    kinds: [for (final k in l[1] as List) k as String],
  );
}

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
    this.routeLegs = const [],
    this.home,
    this.homeWarning,
    this.homeReason,
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

  /// Шлях між точками маршруту, прокладений автоматично (стежками): `routeLegs[i]` — від
  /// `route[i]` до `route[i + 1]`; `null` — пряма (маршрут «Власний»).
  final List<PathLeg?> routeLegs;

  /// Автоматичний маршрут «Додому» (ReturnMode.auto).
  final PathLeg? home;

  /// Відрізок до стежки все ж через воду / болото (`water` / `wetland` / `river`).
  final String? homeWarning;

  /// Чому обрано цей шлях додому — показується на екрані.
  final String? homeReason;

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
    List<PathLeg?>? routeLegs,
    PathLeg? home,
    String? homeWarning,
    String? homeReason,
    bool clearHome = false,
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
        routeLegs: routeLegs ?? this.routeLegs,
        home: clearHome || clearReturn ? null : home ?? this.home,
        homeWarning: clearHome || clearReturn ? null : homeWarning ?? this.homeWarning,
        homeReason: clearHome || clearReturn ? null : homeReason ?? this.homeReason,
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
        'route_legs': [for (final l in routeLegs) l == null ? null : _legJson(l)],
        'home': home == null ? null : _legJson(home!),
        'home_warning': homeWarning,
        'home_reason': homeReason,
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
        routeLegs: [for (final l in (j['route_legs'] as List? ?? const [])) l == null ? null : _legFrom(l)],
        home: j['home'] == null ? null : _legFrom(j['home']),
        homeWarning: j['home_warning'] as String?,
        homeReason: j['home_reason'] as String?,
      );
}

/// Сповіщення застосунку (id).
const kSunsetNotification = 7001;
const kBatteryNotification = 7002;

/// Похід: маршрут → «Почати похід» (запис треку) → «Додому» → «Я вдома».
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
    final n = state.route.length - 1;
    state = state.copyWith(
      route: state.route.sublist(0, n),
      routeLegs: state.routeLegs.length > n - 1 ? state.routeLegs.sublist(0, (n - 1).clamp(0, n)) : state.routeLegs,
      target: 0,
    );
    _save(now: true);
  }

  /// Точка маршруту з шляхом стежками від попередньої (маршрут «Автоматичний», ADR-022 §22.7).
  /// `true` — проклали стежками; `false` — поруч немає доріг, буде пряма; `null` — мережі стежок
  /// ще немає на телефоні (завантажте офлайн-карту).
  Future<bool?> addAutoPoint(double lat, double lng) async {
    addPoint(lat, lng);
    final n = state.route.length;
    if (n < 2) return true;
    final graph = await _graph();
    if (graph == null) return null;
    final a = state.route[n - 2], b = state.route[n - 1];
    final r = planRoute(graph, (lat: a.lat, lng: a.lng), (lat: b.lat, lng: b.lng));
    if (state.route.length != n) return r != null; // точку вже прибрали
    final legs = [...state.routeLegs];
    while (legs.length < n - 1) {
      legs.add(null);
    }
    legs[n - 2] = r == null ? null : (points: r.points, kinds: r.kinds);
    state = state.copyWith(routeLegs: legs);
    _save(now: true);
    return r != null;
  }

  Future<TrailGraph?> _graph() async {
    final slug = ref.read(homeRegionSlugProvider);
    if (slug == null) return null;
    try {
      return await ref.read(trailGraphProvider(slug).future);
    } catch (_) {
      return null;
    }
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
    _checkReroute();
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
          mins > 0 ? 'До заходу сонця $mins хв. Натисніть «Додому» на вкладці «Безпека».' : 'Сонце вже зайшло — повертайтеся.');
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
    if (mode == ReturnMode.auto && state.home == null) unawaited(planHome());
  }

  /// Кнопка «Додому» (ADR-022 §22.7): одразу — свій слід (або навпростець, якщо сліду ще
  /// немає); тим часом прокладаємо маршрут дорогами й стежками й беремо його, якщо він
  /// коротший за слід на 30 % і більше. Вибір і причина — на екрані.
  Future<void> goHome() async {
    if (state.returnMode == null) startReturn(state.track.length >= 2 ? ReturnMode.track : ReturnMode.direct);
    await planHome(choose: true);
  }

  DateTime? _plannedAt;

  /// Прокласти маршрут додому дорогами й стежками від поточного місця. [choose] — порівняти зі
  /// своїм слідом і обрати; інакше — увімкнути «Авто» (вибір користувача / перебудова).
  Future<void> planHome({bool choose = false}) async {
    final here = state.here;
    if (state.route.isEmpty || here == null) return;
    _plannedAt = now();
    final graph = await _graph();
    final start = (lat: state.route.first.lat, lng: state.route.first.lng);
    final r = graph == null ? null : planRoute(graph, geoOf(here), start);
    if (state.returnMode == null) return; // уже вдома
    final own = state.outbound.length >= 2 ? backtrackTarget(state.outbound, geoOf(here)).remainingM : double.infinity;
    if (r == null) {
      final why = graph == null
          ? 'Стежок області ще немає на телефоні — завантажте офлайн-карту на вкладці «Карта»'
          : 'Поруч немає доріг і стежок з карти';
      final fallback = own.isFinite ? ReturnMode.track : ReturnMode.direct;
      final switchMode = choose || state.returnMode == ReturnMode.auto;
      state = state.copyWith(clearHome: true).copyWith(
            homeReason: switchMode ? (own.isFinite ? '$why — ведемо вашим слідом' : '$why — ведемо навпростець') : why,
            returnMode: switchMode ? fallback : null,
          );
      _save(now: true);
      return;
    }
    final home = (points: r.points, kinds: r.kinds);
    if (choose) {
      final auto = !own.isFinite || r.lengthM <= own * 0.7;
      final pct = own.isFinite ? ((1 - r.lengthM / own) * 100).round() : 0;
      state = state.copyWith(
        home: home,
        homeWarning: r.warning,
        returnMode: auto ? ReturnMode.auto : state.returnMode,
        homeReason: auto
            ? (own.isFinite ? 'Дорогами й стежками коротше на $pct % за ваш слід' : 'Дорогами й стежками — в обхід води й боліт')
            : 'Ваш слід надійніший: дорогами й стежками — ${distanceLabel(r.lengthM)}, не коротше',
      );
    } else {
      state = state.copyWith(home: home, homeWarning: r.warning, returnMode: ReturnMode.auto, homeReason: 'Дорогами й стежками — в обхід води й боліт');
    }
    _save(now: true);
  }

  /// Зійшли з автоматичного маршруту (> 60 м) — перебудувати, не частіше раз на 30 с.
  void _checkReroute() {
    final home = state.home, here = state.here;
    if (state.returnMode != ReturnMode.auto || home == null || here == null || home.points.length < 2) return;
    if (_plannedAt != null && now().difference(_plannedAt!) < const Duration(seconds: 30)) return;
    final g = guide(NavPlan(home.points, kinds: home.kinds, destination: ''), geoOf(here));
    if (g.offRouteM > 60 && !g.arrived) unawaited(planHome());
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

/// Мережа стежок області на телефоні (`null` — ще не завантажена).
final trailGraphProvider = FutureProvider.family<TrailGraph?, String>((ref, slug) async {
  try {
    return await ref.watch(trailsRepositoryProvider).load(slug);
  } catch (_) {
    return null;
  }
});

/// Мережу стежок підтягуємо тихо разом з офлайн-картою: немає на телефоні чи вийшла нова
/// версія — завантажуємо (без мережі — наступного разу). `true` — мережа є.
final trailsSyncProvider = FutureProvider.family<bool, String>((ref, slug) async {
  final repo = ref.read(trailsRepositoryProvider);
  try {
    final geo = await ref.read(regionGeometryProvider(slug).future);
    final before = await repo.localMeta(slug);
    final ok = await repo.download(slug, trailsFilesFor(geo));
    if (ok && (await repo.localMeta(slug))?.version != before?.version) ref.invalidate(trailGraphProvider(slug));
    return ok;
  } catch (_) {
    return await repo.localMeta(slug) != null;
  }
});

/// Створення маршруту на карті: «Стежками» — шлях між точками прокладається автоматично.
final routeAutoProvider = StateProvider<bool>((ref) => true);

/// Мапа: дотик додає точку маршруту (режим «Створити маршрут на карті»).
final routeEditProvider = StateProvider<bool>((ref) => false);
