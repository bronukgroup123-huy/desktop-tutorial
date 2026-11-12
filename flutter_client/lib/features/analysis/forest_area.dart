import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/models/forest_zone.dart';

/// Ліс у квадраті ділянки: загальна площа і площа за типами, км².
class ForestAreaSummary {
  const ForestAreaSummary({required this.forestKm2, required this.byType});

  final double forestKm2;

  /// Тип лісу (`null` — невідомий) → км².
  final Map<String?, double> byType;

  /// Тіло `forest` для `POST /v1-analysis`.
  Map<String, dynamic> toJson() {
    final types = byType.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return {
      'forest_km2': _round(forestKm2),
      'types': [
        for (final e in types.take(12)) {'forest_type': e.key, 'km2': _round(e.value)},
      ],
    };
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}

const double _kmPerDegLat = 111.32;

/// Скільки лісу з [zones] (ті самі полігони, що на карті) лежить у квадраті [square]
/// (4 кути, осі вздовж меридіанів і паралелей — як у [squareAround]).
///
/// Чому на клієнті: полігони лісів областей зберігаються у файлі області (OSM), а в
/// БД — лише частина областей. Сервер, рахуючи ліс по БД, казав «лісів немає» під
/// видимим лісовим масивом.
ForestAreaSummary forestInSquare(List<ForestZone> zones, List<LatLng> square) {
  final minLat = square.map((p) => p.latitude).reduce(math.min);
  final maxLat = square.map((p) => p.latitude).reduce(math.max);
  final minLng = square.map((p) => p.longitude).reduce(math.min);
  final maxLng = square.map((p) => p.longitude).reduce(math.max);
  final midLat = (minLat + maxLat) / 2;
  final kmPerDegLng = _kmPerDegLat * math.cos(midLat * math.pi / 180);
  final squareKm2 = (maxLat - minLat) * _kmPerDegLat * (maxLng - minLng) * kmPerDegLng;

  // Локальна проєкція в км відносно південно-західного кута.
  math.Point<double> km(LatLng p) =>
      math.Point((p.longitude - minLng) * kmPerDegLng, (p.latitude - minLat) * _kmPerDegLat);
  final w = (maxLng - minLng) * kmPerDegLng;
  final h = (maxLat - minLat) * _kmPerDegLat;

  double clippedArea(List<LatLng> ring) => _area(_clip(ring.map(km).toList(), w, h)).abs();

  final byType = <String?, double>{};
  var total = 0.0;
  for (final z in zones) {
    for (final poly in z.polygons) {
      if (!_overlaps(poly.outer, minLat, maxLat, minLng, maxLng)) continue;
      var a = clippedArea(poly.outer);
      for (final hole in poly.holes) {
        a -= clippedArea(hole);
      }
      if (a <= 0) continue;
      byType[z.forestType] = (byType[z.forestType] ?? 0) + a;
      total += a;
    }
  }
  // Полігони «landuse=forest» і «natural=wood» з OSM інколи перекриваються.
  return ForestAreaSummary(forestKm2: math.min(total, squareKm2), byType: byType);
}

bool _overlaps(List<LatLng> ring, double minLat, double maxLat, double minLng, double maxLng) {
  var lo = double.infinity, hi = -double.infinity, lw = double.infinity, le = -double.infinity;
  for (final p in ring) {
    lo = math.min(lo, p.latitude);
    hi = math.max(hi, p.latitude);
    lw = math.min(lw, p.longitude);
    le = math.max(le, p.longitude);
  }
  return hi >= minLat && lo <= maxLat && le >= minLng && lw <= maxLng;
}

/// Площа многокутника (формула шнурка), знак залежить від напрямку обходу.
double _area(List<math.Point<double>> pts) {
  if (pts.length < 3) return 0;
  var s = 0.0;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    s += (pts[j].x * pts[i].y) - (pts[i].x * pts[j].y);
  }
  return s / 2;
}

/// Відсікання многокутника прямокутником [0..w]×[0..h] (Сазерленд — Ходжмен).
List<math.Point<double>> _clip(List<math.Point<double>> pts, double w, double h) {
  var out = pts;
  for (final edge in const [0, 1, 2, 3]) {
    if (out.isEmpty) break;
    final input = out;
    out = [];
    bool inside(math.Point<double> p) => switch (edge) {
          0 => p.x >= 0,
          1 => p.x <= w,
          2 => p.y >= 0,
          _ => p.y <= h,
        };
    math.Point<double> cross(math.Point<double> a, math.Point<double> b) {
      final t = switch (edge) {
        0 => (0 - a.x) / (b.x - a.x),
        1 => (w - a.x) / (b.x - a.x),
        2 => (0 - a.y) / (b.y - a.y),
        _ => (h - a.y) / (b.y - a.y),
      };
      return math.Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
    }

    for (var i = 0; i < input.length; i++) {
      final cur = input[i];
      final prev = input[(i + input.length - 1) % input.length];
      if (inside(cur)) {
        if (!inside(prev)) out.add(cross(prev, cur));
        out.add(cur);
      } else if (inside(prev)) {
        out.add(cross(prev, cur));
      }
    }
  }
  return out;
}
