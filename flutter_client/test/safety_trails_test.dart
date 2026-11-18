import 'dart:io';

import 'package:flutter_client/features/safety/hike/hike_geo.dart';
import 'package:flutter_client/features/safety/hike/hike_nav.dart';
import 'package:flutter_client/features/safety/hike/trails.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тестова мережа (scripts/trails/fixture.geojsonseq): машина на півдні дороги, що йде на
/// північ до перехрестя; звідти лісова дорога на схід і стежка на південь; напряму від машини на
/// схід — лісова дорога через болото; між ними — озеро; на захід — стежка через річку мостом.
final graph = TrailGraph.parse(File('test/fixtures/trails-test.bin').readAsBytesSync());
const car = (lat: 50.45, lng: 30.52);

void main() {
  test('Файл мережі: вузли, ребра, довжини, перешкоди', () {
    expect(graph.nodeCount, 7);
    expect(graph.edgeCount, 7);
    expect(graph.barrierOn(const (lat: 50.453, lng: 30.529), car), 'water'); // навпростець через озеро
    expect(graph.barrierOn(const (lat: 50.4512, lng: 30.525), const (lat: 50.4490, lng: 30.525)), 'wetland');
    expect(graph.barrierOn(const (lat: 50.457, lng: 30.512), const (lat: 50.457, lng: 30.518)), 'river');
    expect(graph.barrierOn(const (lat: 50.457, lng: 30.521), const (lat: 50.458, lng: 30.529)), isNull);
    expect(() => TrailGraph.parse(File('test/fixtures/trails-test.bin').readAsBytesSync().sublist(4)), throwsFormatException);
  });

  test('Додому стежками: в обхід болота й озера — стежкою, лісовою дорогою, дорогою', () {
    final r = planRoute(graph, const (lat: 50.453, lng: 30.529), car)!;
    expect(r.warning, isNull);
    // Без відрізка через болото (лісова дорога на широті 50,45).
    expect(r.points.any((p) => (p.lat - 50.45).abs() < 0.0002 && p.lng > 30.522 && p.lng < 30.528), isFalse);
    expect(r.lengthM, closeTo(70 + 333 + 710 + 667, 25));
    final plan = NavPlan(r.points, kinds: r.kinds, destination: 'Машина');
    expect([for (final l in plan.legs) l.kind], ['direct', 'path', 'track', 'road']);
    expect([for (final l in plan.legs) cardinal(l.bearing)], ['Сх', 'Пн', 'Зх', 'Пд']);
    expect(legInstruction(plan.legs[1]), 'Йдіть на північ стежкою');
    expect(legInstruction(plan.legs[2]), 'Йдіть на захід лісовою дорогою');
    expect(legInstruction(plan.legs[3]), 'Йдіть на південь дорогою');
  });

  test('Річку — лише мостом', () {
    final r = planRoute(graph, const (lat: 50.4565, lng: 30.5115), car)!;
    // Шлях іде стежкою на схід через міст (30,514 → 30,516), далі дорогою на південь.
    expect(r.points.any((p) => (p.lng - 30.515).abs() < 0.0011 && (p.lat - 50.456).abs() < 0.0002), isTrue);
    expect(r.kinds.toSet(), containsAll(['path', 'road']));
    expect(r.warning, isNull);
  });

  test('До стежки навпростець — не через болото: обираємо іншу стежку', () {
    final from = const (lat: 50.4512, lng: 30.525);
    final r = planRoute(graph, from, car)!;
    expect(r.kinds.first, 'direct');
    expect(r.points[1].lng, closeTo(30.52, 0.0003)); // на дорогу на заході, а не на південь через болото
    expect(r.warning, isNull);
  });

  test('Поруч немає доріг — автоматичного маршруту немає', () {
    expect(planRoute(graph, const (lat: 50.30, lng: 30.80), car), isNull);
  });
}
