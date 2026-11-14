import 'package:flutter/widgets.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/features/map/region_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // Житомирська область (≈ 27.2–30.6 × 49.6–51.6).
  const zhytomyr = GeoBounds(southWest: LatLng(49.6, 27.2), northEast: LatLng(51.6, 30.6));
  const portrait = Size(411, 780);
  const landscape = Size(780, 411);

  group('Стартовий масштаб — вся область, не більше (MapLibre: світ 512 px)', () {
    test('портрет: область уміщується з полями, зайвих полів по ширині немає', () {
      final fit = fitRegion(zhytomyr, portrait);
      expect(fit.zoom, inInclusiveRange(5.5, 7.0));
      final v = visibleExtent(fit.center, fit.zoom, portrait);
      expect(v.southWest.longitude, lessThanOrEqualTo(zhytomyr.southWest.longitude));
      expect(v.northEast.longitude, greaterThanOrEqualTo(zhytomyr.northEast.longitude));
      expect(v.southWest.latitude, lessThanOrEqualTo(zhytomyr.southWest.latitude));
      expect(v.northEast.latitude, greaterThanOrEqualTo(zhytomyr.northEast.latitude));
      // полів по горизонталі — лише regionPadding (~16 px), не більше ~10% ширини області
      expect(zhytomyr.southWest.longitude - v.southWest.longitude, lessThan(0.35));
    });

    test('альбомна орієнтація: масштаб перераховується, область уміщується по висоті', () {
      final p = fitRegion(zhytomyr, portrait);
      final l = fitRegion(zhytomyr, landscape);
      expect(l.zoom, isNot(closeTo(p.zoom, 0.01)));
      final v = visibleExtent(l.center, l.zoom, landscape);
      expect(v.southWest.latitude, lessThanOrEqualTo(zhytomyr.southWest.latitude));
      expect(v.northEast.latitude, greaterThanOrEqualTo(zhytomyr.northEast.latitude));
    });

    test('масштаб MapLibre на 1 менший за растровий (світ 512 проти 256 px)', () {
      final ml = fitRegion(zhytomyr, portrait);
      final raster = fitRegion(zhytomyr, portrait, worldSize: 256);
      expect(raster.zoom - ml.zoom, closeTo(1, 1e-9));
    });
  });

  test('boundsOf — обрис точок', () {
    final b = boundsOf(const [LatLng(50, 28), LatLng(51, 27), LatLng(50.5, 29)]);
    expect([b.southWest, b.northEast], const [LatLng(50, 27), LatLng(51, 29)]);
  });

  test('isInsideRegion — по кордону, з дірками', () {
    const ring = [LatLng(50, 28), LatLng(50, 29), LatLng(51, 29), LatLng(51, 28), LatLng(50, 28)];
    const hole = [LatLng(50.4, 28.4), LatLng(50.4, 28.6), LatLng(50.6, 28.6), LatLng(50.6, 28.4), LatLng(50.4, 28.4)];
    const region = [GeoPolygon(outer: ring, holes: [hole])];
    expect(isInsideRegion(const LatLng(50.2, 28.2), region), isTrue);
    expect(isInsideRegion(const LatLng(50.5, 28.5), region), isFalse);
    expect(isInsideRegion(const LatLng(52, 28.5), region), isFalse);
  });
}
