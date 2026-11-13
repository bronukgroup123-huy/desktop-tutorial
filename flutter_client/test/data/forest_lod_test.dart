import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/models/forest_lod.dart';
import 'package:flutter_client/data/models/forest_zone.dart';
import 'package:flutter_client/data/models/geo.dart';

/// Квадрат зі стороною [sideM] метрів з центром (lat, lng), замкнутий (як у GeoJSON).
List<LatLng> square(double lat, double lng, double sideM) {
  final dLat = sideM / 111320 / 2;
  final dLng = sideM / (111320 * math.cos(lat * math.pi / 180)) / 2;
  return [
    LatLng(lat - dLat, lng - dLng),
    LatLng(lat - dLat, lng + dLng),
    LatLng(lat + dLat, lng + dLng),
    LatLng(lat + dLat, lng - dLng),
    LatLng(lat - dLat, lng - dLng),
  ];
}

ForestZone zone(String id, List<LatLng> outer, {Color color = const Color(0xFF66BB6A), List<List<LatLng>> holes = const [], double? area}) =>
    ForestZone(
      id: id,
      forestType: 'coniferous',
      standAgeYears: null,
      typeLabel: 'Хвойний ліс',
      typeColor: color,
      polygons: [GeoPolygon(outer: outer, holes: holes)],
      areaM2: area,
    );

void main() {
  test('рівень деталізації за масштабом', () {
    expect(<double>[7.5, 8.99, 9, 10.4, 11, 12, 16].map(forestLodLevelFor).toList(), [0, 0, 1, 2, 3, 4, 4]);
  });

  test('при віддаленні гаї не малюються, при наближенні — усі ліси', () {
    final zones = [
      zone('big', square(50.5, 28.5, 2000)), // 400 га
      zone('grove', square(50.6, 28.6, 60)), // 0,36 га
    ];
    final lod = buildForestLod(zones);
    expect(lod.areas[0], closeTo(4e6, 4e4));
    expect(lod.levels.first.map((p) => zones[p.zone].id), ['big']);
    expect(lod.levels.last.map((p) => zones[p.zone].id).toSet(), {'big', 'grove'});
  });

  test('спрощення зменшує кількість точок і лишає контур замкнутим', () {
    // «Пилка» з 400 точок уздовж кола радіусом ~1 км.
    final ring = [
      for (var i = 0; i < 400; i++)
        LatLng(50.5 + 0.009 * math.sin(i * 2 * math.pi / 400) + (i.isEven ? 0.00002 : 0),
            28.5 + 0.014 * math.cos(i * 2 * math.pi / 400)),
      const LatLng(50.5, 28.514),
    ];
    ring[0] = ring.last;
    final simplified = simplifyRing(ring, 0.0009);
    expect(simplified.length, lessThan(60));
    expect(simplified.length, greaterThanOrEqualTo(4));
    expect(simplified.first, simplified.last);
    expect(simplifyRing(ring, 0), same(ring));
  });

  test('контури одного кольору — підряд, ліси з дірками — наприкінці', () {
    const a = Color(0xFF66BB6A), b = Color(0xFFA5D6A7);
    final zones = [
      zone('a1', square(50.1, 28.1, 1000), color: a),
      zone('b1', square(50.2, 28.2, 1000), color: b),
      zone('holed', square(50.3, 28.3, 2000), color: a, holes: [square(50.3, 28.3, 500)]),
      zone('a2', square(50.4, 28.4, 1000), color: a),
    ];
    final ids = buildForestLod(zones).levels.last.map((p) => zones[p.zone].id).toList();
    expect(ids.last, 'holed');
    expect(ids.indexOf('a1') - ids.indexOf('a2'), anyOf(1, -1));
  });

  test('тап: ліс під пальцем (не в дірці), гай при віддаленні не знаходиться', () {
    final zones = [
      zone('ring', square(50.5, 28.5, 2000), holes: [square(50.5, 28.5, 600)]),
      zone('grove', square(50.5, 28.507, 60)),
    ];
    final lod = buildForestLod(zones);
    expect(lod.zonesAt(const LatLng(50.5, 28.5), zones, level: 4), isEmpty); // у дірці
    expect(lod.zonesAt(const LatLng(50.506, 28.5), zones, level: 4).map((z) => z.id), ['ring']);
    expect(lod.zonesAt(const LatLng(50.5, 28.507), zones, level: 4).map((z) => z.id).toSet(), {'ring', 'grove'});
    expect(lod.zonesAt(const LatLng(50.5, 28.507), zones, level: 0).map((z) => z.id), ['ring']);
    expect(lod.zonesAt(const LatLng(51.5, 29.5), zones, level: 4), isEmpty);
  });
}
