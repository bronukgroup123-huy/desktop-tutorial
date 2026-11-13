import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'forest_zone.dart';
import 'geo.dart';

/// Рівень деталізації лісів на карті.
///
/// Чому: у файлі області ~13 тис. лісів (половина — гаї до 1 га). Коли видно всю
/// область, гай займає частку пікселя, а малювання всіх контурів щокадру гальмувало
/// карту. Тому при віддаленні малюємо лише ліси, помітні на екрані, і спрощені контури.
class ForestLodLevel {
  const ForestLodLevel({
    required this.minZoom,
    required this.minAreaM2,
    required this.toleranceDeg,
    required this.borders,
  });

  /// З якого масштабу діє рівень.
  final double minZoom;

  /// Менші ліси на цьому рівні не малюються (≈ 2×2 пікселі на мінімальному масштабі рівня).
  final double minAreaM2;

  /// Допуск спрощення контурів, градуси широти (≈ пів пікселя). 0 — як у файлі.
  final double toleranceDeg;

  /// Чи малювати контури (при віддаленні — лише заливка).
  final bool borders;
}

/// Розмір пікселя на широті 50° (Україна): z9 ≈ 200 м, z10 ≈ 100 м, z11 ≈ 50 м, z12 ≈ 25 м.
const forestLodLevels = <ForestLodLevel>[
  ForestLodLevel(minZoom: 0, minAreaM2: 500000, toleranceDeg: 0.0018, borders: false),
  ForestLodLevel(minZoom: 9, minAreaM2: 150000, toleranceDeg: 0.0009, borders: false),
  ForestLodLevel(minZoom: 10, minAreaM2: 40000, toleranceDeg: 0.00045, borders: false),
  ForestLodLevel(minZoom: 11, minAreaM2: 10000, toleranceDeg: 0.0002, borders: true),
  ForestLodLevel(minZoom: 12, minAreaM2: 0, toleranceDeg: 0, borders: true),
];

/// Індекс рівня для масштабу карти.
int forestLodLevelFor(double zoom) {
  var level = 0;
  for (var i = 0; i < forestLodLevels.length; i++) {
    if (zoom >= forestLodLevels[i].minZoom) level = i;
  }
  return level;
}

/// Контур лісу на рівні деталізації: [zone] — індекс у списку лісів.
class LodPolygon {
  const LodPolygon({required this.zone, required this.outer, this.holes = const []});

  final int zone;
  final List<LatLng> outer;
  final List<List<LatLng>> holes;
}

/// Ліси області, підготовлені для карти: контури за рівнями і просторовий індекс для тапу.
/// Будується один раз (в ізоляті разом із розбором файлу) — на карті лише вибір рівня.
class ForestLod {
  ForestLod._(this.levels, this.areas, this._bboxes, this._cells);

  /// Контури для кожного рівня [forestLodLevels], упорядковані за кольором типу —
  /// так карта малює однакові ліси одним викликом, а не кожен окремо.
  final List<List<LodPolygon>> levels;

  /// Площа кожного лісу, м².
  final Float64List areas;

  /// minLat, minLng, maxLat, maxLng для кожного лісу.
  final Float64List _bboxes;

  /// Клітинка сітки → ліси, чий bbox її перетинає.
  final Map<int, List<int>> _cells;

  static const double _cellDeg = 0.02; // ≈ 2 км

  static int _cellKey(int iy, int ix) => iy * 100000 + ix;

  /// Ліси під точкою [p], видимі на рівні [level] (менші за поріг рівня — ні: їх не видно).
  List<ForestZone> zonesAt(LatLng p, List<ForestZone> zones, {required int level}) {
    final minArea = forestLodLevels[level].minAreaM2;
    final candidates = _cells[_cellKey((p.latitude / _cellDeg).floor(), (p.longitude / _cellDeg).floor())];
    if (candidates == null) return const [];
    final hits = <ForestZone>[];
    for (final i in candidates) {
      if (areas[i] < minArea) continue;
      final b = i * 4;
      if (p.latitude < _bboxes[b] || p.latitude > _bboxes[b + 2] || p.longitude < _bboxes[b + 1] || p.longitude > _bboxes[b + 3]) {
        continue;
      }
      final zone = zones[i];
      if (zone.polygons.any((poly) => _inPolygon(p, poly))) hits.add(zone);
    }
    return hits;
  }
}

/// Підготувати ліси для карти. Чиста функція — запускається в ізоляті.
ForestLod buildForestLod(List<ForestZone> zones) {
  final areas = Float64List(zones.length);
  final bboxes = Float64List(zones.length * 4);
  final cells = <int, List<int>>{};

  for (var i = 0; i < zones.length; i++) {
    final z = zones[i];
    var minLat = double.infinity, minLng = double.infinity, maxLat = -double.infinity, maxLng = -double.infinity;
    for (final poly in z.polygons) {
      for (final p in poly.outer) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    areas[i] = z.areaM2 ?? z.polygons.fold<double>(0, (s, poly) => s + geoPolygonAreaM2(poly));
    bboxes.setAll(i * 4, [minLat, minLng, maxLat, maxLng]);
    if (minLat > maxLat) continue; // порожня геометрія
    for (var iy = (minLat / ForestLod._cellDeg).floor(); iy <= (maxLat / ForestLod._cellDeg).floor(); iy++) {
      for (var ix = (minLng / ForestLod._cellDeg).floor(); ix <= (maxLng / ForestLod._cellDeg).floor(); ix++) {
        (cells[ForestLod._cellKey(iy, ix)] ??= <int>[]).add(i);
      }
    }
  }

  final levels = [
    for (final level in forestLodLevels) _buildLevel(zones, areas, level),
  ];
  return ForestLod._(levels, areas, bboxes, cells);
}

List<LodPolygon> _buildLevel(List<ForestZone> zones, Float64List areas, ForestLodLevel level) {
  final out = <LodPolygon>[];
  for (var i = 0; i < zones.length; i++) {
    if (areas[i] < level.minAreaM2) continue;
    for (final poly in zones[i].polygons) {
      if (level.toleranceDeg == 0) {
        out.add(LodPolygon(zone: i, outer: poly.outer, holes: poly.holes));
        continue;
      }
      final outer = simplifyRing(poly.outer, level.toleranceDeg);
      if (outer.length < 4) continue; // контур зник при спрощенні — на цьому масштабі не видно
      final holes = [
        for (final h in poly.holes)
          if (geoRingAreaM2(h) >= level.minAreaM2) simplifyRing(h, level.toleranceDeg),
      ].where((h) => h.length >= 4).toList(growable: false);
      out.add(LodPolygon(zone: i, outer: outer, holes: holes));
    }
  }
  // Однаковий колір і напрямок обходу — підряд (карта малює їх одним шляхом).
  // Ліси з дірками — наприкінці: їх карта малює кожен окремо.
  int key(LodPolygon p) =>
      (p.holes.isEmpty ? 0 : 1 << 40) + (zones[p.zone].typeColor.toARGB32() << 1) + (_clockwise(p.outer) ? 1 : 0);
  out.sort((a, b) => key(a).compareTo(key(b)));
  return out;
}

/// Спрощення замкнутого контуру (Дуглас — Пекер), довгота масштабується cos(широти).
/// Перша й остання точки (однакові в GeoJSON) зберігаються.
List<LatLng> simplifyRing(List<LatLng> ring, double toleranceDeg) {
  if (ring.length <= 4 || toleranceDeg <= 0) return ring;
  final k = math.cos(ring.first.latitude * math.pi / 180);
  final keep = List<bool>.filled(ring.length, false);
  keep[0] = true;
  keep[ring.length - 1] = true;
  // Замкнутий контур: спершу ділимо на дві половини найдальшою від першої точкою.
  var far = 0;
  var farD = -1.0;
  for (var i = 1; i < ring.length - 1; i++) {
    final dx = (ring[i].longitude - ring[0].longitude) * k;
    final dy = ring[i].latitude - ring[0].latitude;
    final d = dx * dx + dy * dy;
    if (d > farD) {
      farD = d;
      far = i;
    }
  }
  keep[far] = true;
  final tol2 = toleranceDeg * toleranceDeg;
  final stack = <int>[0, far, far, ring.length - 1];
  while (stack.isNotEmpty) {
    final last = stack.removeLast();
    final first = stack.removeLast();
    if (last - first < 2) continue;
    final ax = ring[first].longitude * k, ay = ring[first].latitude;
    final bx = ring[last].longitude * k, by = ring[last].latitude;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var maxD = -1.0;
    var idx = -1;
    for (var i = first + 1; i < last; i++) {
      final px = ring[i].longitude * k, py = ring[i].latitude;
      double d;
      if (len2 == 0) {
        d = (px - ax) * (px - ax) + (py - ay) * (py - ay);
      } else {
        final t = (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
        final qx = ax + t * dx - px, qy = ay + t * dy - py;
        d = qx * qx + qy * qy;
      }
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > tol2) {
      keep[idx] = true;
      stack
        ..add(first)
        ..add(idx)
        ..add(idx)
        ..add(last);
    }
  }
  return [
    for (var i = 0; i < ring.length; i++)
      if (keep[i]) ring[i],
  ];
}

const double _mPerDeg = 111320;

/// Площа кільця, м² (локальна рівнопроміжна апроксимація — для порогів видимості досить).
double geoRingAreaM2(List<LatLng> ring) {
  if (ring.length < 3) return 0;
  final k = math.cos(ring.first.latitude * math.pi / 180);
  var s = 0.0;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    s += ring[j].longitude * ring[i].latitude - ring[i].longitude * ring[j].latitude;
  }
  return (s / 2).abs() * _mPerDeg * _mPerDeg * k;
}

double geoPolygonAreaM2(GeoPolygon p) =>
    math.max(0, geoRingAreaM2(p.outer) - p.holes.fold<double>(0, (s, h) => s + geoRingAreaM2(h)));

bool _clockwise(List<LatLng> ring) {
  var s = 0.0;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    s += (ring[i].longitude - ring[j].longitude) * (ring[i].latitude + ring[j].latitude);
  }
  return s > 0;
}

bool _inRing(LatLng p, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
        p.longitude < (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude) {
      inside = !inside;
    }
  }
  return inside;
}

bool _inPolygon(LatLng p, GeoPolygon poly) => _inRing(p, poly.outer) && !poly.holes.any((h) => _inRing(p, h));
