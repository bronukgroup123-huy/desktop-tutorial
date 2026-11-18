import 'dart:math' as math;

import 'package:flutter_client/features/safety/hike/hike_geo.dart';

/// Навігація маршрутом (ADR-022 §22.7): шлях ділиться на відрізки «йдіть на схід … до повороту»;
/// з одного розрахунку [guide] беруться стрілка компаса, мітки на циферблаті, текст і голос —
/// тож усе синхронно. Без інтернету й сервера.

/// Тип відрізка шляху — для підказки «… стежкою», «… своїм слідом».
/// `own` — власний трек; `direct` — навпростець; `route` — маршрут, створений користувачем;
/// `road` / `track` / `path` — дорога, лісова дорога, стежка (автоматичний маршрут).
typedef NavKind = String;

enum Turn { straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn }

/// Відрізок без поворотів: від точки [from] до [to] шляху.
typedef NavLeg = ({int from, int to, double bearing, double lengthM, NavKind kind});

/// Шлях до цілі: точки (спрощені), тип кожного сегмента, відрізки з поворотами.
class NavPlan {
  NavPlan._(this.points, this.kinds, this.destination, this.cum, this.legs);

  /// [points] — від місця, звідки йдемо, до цілі. [kinds] — тип сегмента i→i+1 (або один на всіх).
  /// Шлях спрощується (Дуглас — Пекер, [toleranceM]) — дрібні петлі треку не дають зайвих
  /// «поверніть»; сусідні сегменти з поворотом < [turnDeg]° і того самого типу — один відрізок.
  factory NavPlan(
    List<Geo> points, {
    required List<NavKind> kinds,
    required String destination,
    double toleranceM = 12,
    double turnDeg = 30,
  }) {
    assert(points.length >= 2);
    final kindAt = kinds.length == 1 ? List.filled(points.length - 1, kinds.first) : kinds;
    // Спрощуємо в межах ділянок одного типу, щоб не загубити місце, де дорога стає стежкою.
    final keep = <int>{0, points.length - 1};
    var runStart = 0;
    for (var i = 1; i < kindAt.length; i++) {
      if (kindAt[i] != kindAt[i - 1]) {
        keep.addAll(_douglasPeucker(points, runStart, i, toleranceM));
        runStart = i;
      }
    }
    keep.addAll(_douglasPeucker(points, runStart, points.length - 1, toleranceM));
    final idx = keep.toList()..sort();
    final pts = <Geo>[];
    final ks = <NavKind>[];
    for (var j = 0; j < idx.length; j++) {
      final p = points[idx[j]];
      if (pts.isNotEmpty && distanceM(pts.last, p) < 1) continue;
      if (pts.isNotEmpty) ks.add(kindAt[idx[j - 1].clamp(0, kindAt.length - 1)]);
      pts.add(p);
    }
    if (pts.length < 2) {
      pts.add(points.last);
      ks.add(kindAt.last);
    }
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + distanceM(pts[i - 1], pts[i]));
    }
    // Відрізки: зливаємо сегменти без помітного повороту й того самого типу.
    final legs = <NavLeg>[];
    var from = 0;
    for (var i = 1; i < pts.length; i++) {
      final last = i == pts.length - 1;
      final split = !last &&
          (ks[i] != ks[i - 1] ||
              relativeDeg(bearingDeg(pts[i], pts[i + 1]), bearingDeg(pts[i - 1], pts[i])).abs() >= turnDeg);
      if (last || split) {
        legs.add((from: from, to: i, bearing: bearingDeg(pts[from], pts[i]), lengthM: cum[i] - cum[from], kind: ks[from]));
        from = i;
      }
    }
    return NavPlan._(pts, ks, destination, cum, _mergeShort(legs, pts, cum));
  }

  final List<Geo> points;
  final List<NavKind> kinds;

  /// «до «Старт»» — назва цілі.
  final String destination;

  /// Відстань від початку шляху до кожної точки, м.
  final List<double> cum;
  final List<NavLeg> legs;

  double get lengthM => cum.last;
}

/// Відрізки коротші за 20 м (тремтіння на поворотах) — частина попереднього.
List<NavLeg> _mergeShort(List<NavLeg> legs, List<Geo> pts, List<double> cum) {
  final out = <NavLeg>[];
  for (final l in legs) {
    if (out.isNotEmpty && l.lengthM < 20 && l.kind == out.last.kind) {
      final p = out.removeLast();
      out.add((from: p.from, to: l.to, bearing: bearingDeg(pts[p.from], pts[l.to]), lengthM: cum[l.to] - cum[p.from], kind: p.kind));
    } else {
      out.add(l);
    }
  }
  return out;
}

Set<int> _douglasPeucker(List<Geo> pts, int a, int b, double tol) {
  final keep = <int>{a, b};
  if (b - a < 2) return keep;
  var maxD = -1.0;
  var at = a;
  for (var i = a + 1; i < b; i++) {
    final d = _project(pts[i], pts[a], pts[b]).dist;
    if (d > maxD) {
      maxD = d;
      at = i;
    }
  }
  if (maxD > tol) {
    keep.addAll(_douglasPeucker(pts, a, at, tol));
    keep.addAll(_douglasPeucker(pts, at, b, tol));
  }
  return keep;
}

/// Проєкція [p] на відрізок a→b (локальна площина): частка 0…1 і відстань, м.
({double t, double dist}) _project(Geo p, Geo a, Geo b) {
  final k = math.cos(a.lat * math.pi / 180) * 111320;
  final bx = (b.lng - a.lng) * k, by = (b.lat - a.lat) * 111320;
  final px = (p.lng - a.lng) * k, py = (p.lat - a.lat) * 111320;
  final len2 = bx * bx + by * by;
  final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
  final dx = px - bx * t, dy = py - by * t;
  return (t: t, dist: math.sqrt(dx * dx + dy * dy));
}

Geo _lerp(Geo a, Geo b, double t) => (lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t);

/// Точка шляху на відстані [along] від початку.
Geo pointAlong(NavPlan plan, double along) {
  final a = along.clamp(0.0, plan.lengthM);
  for (var i = 1; i < plan.points.length; i++) {
    if (plan.cum[i] >= a) {
      final seg = plan.cum[i] - plan.cum[i - 1];
      return _lerp(plan.points[i - 1], plan.points[i], seg == 0 ? 0 : (a - plan.cum[i - 1]) / seg);
    }
  }
  return plan.points.last;
}

/// Ціль ближче — «Ви на місці».
const kArrivedM = 25.0;

/// Далі від шляху — «Ви зійшли з маршруту».
const kOffRouteM = 40.0;

/// Що робити зараз — один розрахунок для стрілки, циферблата, тексту й голосу.
class Guidance {
  const Guidance({
    required this.along,
    required this.offRouteM,
    required this.remainingM,
    required this.legIndex,
    required this.leg,
    required this.toTurnM,
    required this.next,
    required this.nextTurn,
    required this.aim,
    required this.aimBearing,
    required this.arrived,
  });

  /// Пройдено вздовж шляху, м (для наступного виклику — щоб не «перескочити» на петлю).
  final double along;
  final double offRouteM;
  final double remainingM;
  final int legIndex;
  final NavLeg leg;

  /// До кінця відрізка (повороту чи цілі), м.
  final double toTurnM;
  final NavLeg? next;
  final Turn? nextTurn;

  /// Куди показує стрілка: точка на шляху трохи попереду або (зійшли) — найближча точка шляху.
  final Geo aim;
  final double aimBearing;
  final bool arrived;

  bool get offRoute => offRouteM > kOffRouteM;
  bool get lastLeg => next == null;
}

/// Де ми на шляху й куди йти. [fromAlong] — попереднє [Guidance.along]: шлях назад власним
/// треком може проходити тим самим місцем двічі — беремо ділянку не позаду пройденого.
Guidance guide(NavPlan plan, Geo here, {double? fromAlong, double lookAheadM = 30}) {
  var best = double.infinity;
  var along = 0.0;
  ({double dist, double along})? fallback;
  for (var i = 1; i < plan.points.length; i++) {
    final pr = _project(here, plan.points[i - 1], plan.points[i]);
    final a = plan.cum[i - 1] + (plan.cum[i] - plan.cum[i - 1]) * pr.t;
    if (fallback == null || pr.dist < fallback.dist) fallback = (dist: pr.dist, along: a);
    if (fromAlong != null && a < fromAlong - 60) continue;
    if (pr.dist < best) {
      best = pr.dist;
      along = a;
    }
  }
  // Пройдена частина ближча, а попереду — далеко: людина повернулась назад; беремо найближче.
  if (best == double.infinity || (fallback != null && best > kOffRouteM && fallback.dist <= kOffRouteM)) {
    best = fallback!.dist;
    along = fallback.along;
  }
  var li = plan.legs.length - 1;
  for (var i = 0; i < plan.legs.length; i++) {
    if (along < plan.cum[plan.legs[i].to] - 0.01) {
      li = i;
      break;
    }
  }
  final leg = plan.legs[li];
  final next = li + 1 < plan.legs.length ? plan.legs[li + 1] : null;
  final remaining = plan.lengthM - along + best;
  final offRoute = best > kOffRouteM;
  final end = plan.points.last;
  final arrived = distanceM(here, end) <= kArrivedM || (!offRoute && plan.lengthM - along <= kArrivedM && best <= kArrivedM);
  final aim = offRoute ? pointAlong(plan, along) : pointAlong(plan, along + lookAheadM);
  return Guidance(
    along: along,
    offRouteM: best,
    remainingM: remaining,
    legIndex: li,
    leg: leg,
    toTurnM: math.max(0, plan.cum[leg.to] - along),
    next: next,
    nextTurn: next == null ? null : turnOf(relativeDeg(next.bearing, leg.bearing)),
    aim: aim,
    aimBearing: distanceM(here, aim) < 3 ? leg.bearing : bearingDeg(here, aim),
    arrived: arrived,
  );
}

Turn turnOf(double angle) {
  final a = angle.abs();
  final right = angle > 0;
  if (a < 20) return Turn.straight;
  if (a < 45) return right ? Turn.slightRight : Turn.slightLeft;
  if (a < 120) return right ? Turn.right : Turn.left;
  if (a < 160) return right ? Turn.sharpRight : Turn.sharpLeft;
  return Turn.uTurn;
}

String turnWord(Turn t) => switch (t) {
      Turn.straight => 'прямо',
      Turn.slightLeft => 'трохи ліворуч',
      Turn.left => 'ліворуч',
      Turn.sharpLeft => 'різко ліворуч',
      Turn.slightRight => 'трохи праворуч',
      Turn.right => 'праворуч',
      Turn.sharpRight => 'різко праворуч',
      Turn.uTurn => 'розверніться',
    };

/// «на північ», «на південний схід».
String directionWord(double bearing) {
  const names = ['північ', 'північний схід', 'схід', 'південний схід', 'південь', 'південний захід', 'захід', 'північний захід'];
  return names[(((bearing % 360) + 22.5) ~/ 45) % 8];
}

String kindWord(NavKind k) => switch (k) {
      'own' => 'своїм слідом',
      'direct' => 'навпростець',
      'road' => 'дорогою',
      'track' => 'лісовою дорогою',
      'path' => 'стежкою',
      _ => 'за маршрутом',
    };

/// Головна підказка: «Йдіть на схід своїм слідом».
String legInstruction(NavLeg leg) => 'Йдіть на ${directionWord(leg.bearing)} ${kindWord(leg.kind)}';

/// «Далі — ліворуч, на північ стежкою».
String nextInstruction(Guidance g) {
  final n = g.next;
  if (n == null) return '';
  final t = g.nextTurn!;
  final turn = t == Turn.straight ? 'прямо' : turnWord(t);
  return 'Далі — $turn, на ${directionWord(n.bearing)} ${kindWord(n.kind)}';
}

/// Як тримати телефон відносно стрілки: «Так тримати», «трохи правіше», «Розверніться».
enum Cue { onTrack, slightRight, slightLeft, right, left, turnAround }

Cue cueOf(double relative) {
  final a = relative.abs();
  if (a < 15) return Cue.onTrack;
  if (a < 45) return relative > 0 ? Cue.slightRight : Cue.slightLeft;
  if (a < 135) return relative > 0 ? Cue.right : Cue.left;
  return Cue.turnAround;
}

String cueText(Cue c) => switch (c) {
      Cue.onTrack => 'Правильно — так тримати',
      Cue.slightRight => 'Трохи правіше',
      Cue.slightLeft => 'Трохи лівіше',
      Cue.right => 'Поверніть праворуч',
      Cue.left => 'Поверніть ліворуч',
      Cue.turnAround => 'Розверніться',
    };

String spokenDistance(double m) {
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} кілометра';
  return '${math.max(10, (m / 10).round() * 10)} метрів';
}

/// Голос (ADR-022 §22.7): старт відрізка, «через 50 метрів поверніть…», «зійшли з маршруту»,
/// «знову на маршруті», «поверніть / розверніться» (стабільно 4 с, не частіше 12 с),
/// кожні 500 м — залишок, «Ви на місці». Бере той самий [Guidance], що й екран.
class NavVoice {
  NavVoice({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  int? _leg;
  int? _warnedLeg;
  bool _off = false;
  bool _arrived = false;
  int? _bucket;
  DateTime? _offCourseSince;
  DateTime? _lastCue;

  String? next(Guidance g, {double? relative}) {
    if (g.arrived) {
      if (_arrived) return null;
      _arrived = true;
      return 'Ви на місці';
    }
    _arrived = false;
    if (g.offRoute) {
      if (_off) return _courseCue(relative);
      _off = true;
      return 'Ви зійшли з маршруту на ${spokenDistance(g.offRouteM)}. Поверніться на ${directionWord(g.aimBearing)}';
    }
    if (_off) {
      _off = false;
      _leg = g.legIndex;
      return 'Ви знову на маршруті. ${legInstruction(g.leg)}, ${spokenDistance(g.toTurnM)}';
    }
    if (_leg == null) {
      _leg = g.legIndex;
      _bucket = (g.remainingM / 500).ceil();
      final tail = g.lastLeg ? 'до мети' : 'до повороту';
      return '${legInstruction(g.leg)}, ${spokenDistance(g.toTurnM)} $tail';
    }
    if (g.legIndex != _leg) {
      _leg = g.legIndex;
      final tail = g.lastLeg ? ' до мети' : '';
      return 'Тепер ${legInstruction(g.leg).replaceFirst('Йдіть', 'йдіть')}, ${spokenDistance(g.toTurnM)}$tail';
    }
    if (!g.lastLeg && g.toTurnM <= 60 && _warnedLeg != g.legIndex) {
      _warnedLeg = g.legIndex;
      final t = g.nextTurn!;
      final turn = t == Turn.straight ? 'йдіть прямо' : (t == Turn.uTurn ? 'розверніться' : 'поверніть ${turnWord(t)}');
      return 'Через ${spokenDistance(g.toTurnM)} $turn, на ${directionWord(g.next!.bearing)}';
    }
    final bucket = (g.remainingM / 500).ceil();
    if (_bucket != null && bucket < _bucket!) {
      _bucket = bucket;
      return 'Залишилось ${spokenDistance(g.remainingM)}';
    }
    return _courseCue(relative);
  }

  /// Телефон дивиться не туди, куди стрілка, 4 с поспіль — «Поверніть праворуч» / «Розверніться».
  String? _courseCue(double? relative) {
    if (relative == null || relative.abs() <= 60) {
      _offCourseSince = null;
      return null;
    }
    final t = _now();
    _offCourseSince ??= t;
    final steady = t.difference(_offCourseSince!) >= const Duration(seconds: 4);
    final rested = _lastCue == null || t.difference(_lastCue!) >= const Duration(seconds: 12);
    if (!steady || !rested) return null;
    _lastCue = t;
    _offCourseSince = null;
    return cueText(cueOf(relative));
  }
}
