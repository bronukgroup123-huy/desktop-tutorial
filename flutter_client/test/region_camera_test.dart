import 'dart:math' show Point;

import 'package:flutter/widgets.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/features/map/region_camera.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // Житомирська область (≈ 27.2–30.6 × 49.6–51.6).
  final zhytomyr = LatLngBounds(const LatLng(49.6, 27.2), const LatLng(51.6, 30.6));
  const portrait = Size(411, 780);
  const landscape = Size(780, 411);

  MapCamera cameraAt(LatLng center, double zoom, [Size size = portrait]) => MapCamera(
        crs: const Epsg3857(),
        center: center,
        zoom: zoom,
        rotation: 0,
        nonRotatedSize: Point(size.width, size.height),
      );

  group('Стартовий масштаб — вся область, не більше', () {
    test('портрет: область уміщується з полями, сусідніх країн не видно', () {
      final fit = fitRegion(zhytomyr, portrait);
      expect(fit.zoom, inInclusiveRange(6.5, 8.0));
      final visible = cameraAt(fit.center, fit.zoom).visibleBounds;
      expect(visible.west, lessThanOrEqualTo(zhytomyr.west));
      expect(visible.east, greaterThanOrEqualTo(zhytomyr.east));
      // полів по горизонталі не більше ~10% ширини області
      expect(zhytomyr.west - visible.west, lessThan(0.2));
    });

    test('альбомна орієнтація: масштаб перераховується (область ширша — ближче)', () {
      final p = fitRegion(zhytomyr, portrait);
      final l = fitRegion(zhytomyr, landscape);
      expect(l.zoom, isNot(closeTo(p.zoom, 0.01)));
      final visible = cameraAt(l.center, l.zoom, landscape).visibleBounds;
      expect(visible.south, lessThanOrEqualTo(zhytomyr.south));
      expect(visible.north, greaterThanOrEqualTo(zhytomyr.north));
    });
  });

  group('Обмеження камери «острів»', () {
    final constraint = RegionCameraConstraint(bounds: zhytomyr);

    test('ніколи не блокує карту (не повертає null) і не змінює масштаб', () {
      for (final size in [portrait, landscape]) {
        for (final zoom in [4.0, 6.0, 7.0, 9.0, 13.0, 17.0]) {
          final c = constraint.constrain(cameraAt(const LatLng(50.5, 28.7), zoom, size));
          expect(c.zoom, zoom, reason: '$size z$zoom');
        }
      }
      // старе обмеження contain тут блокувало все
      expect(CameraConstraint.contain(bounds: zhytomyr).constrain(cameraAt(const LatLng(50.5, 28.7), 6)), isNull);
    });

    test('наближена карта біля кордону: за кордон видно лише невеликий відступ', () {
      final c = constraint.constrain(cameraAt(const LatLng(49.0, 26.0), 11));
      final cam = cameraAt(c.center, 11);
      final margin = regionMarginPx + 1;
      final swPx = cam.project(zhytomyr.southWest);
      final viewSw = cam.project(cam.visibleBounds.southWest);
      expect(swPx.x - viewSw.x, lessThanOrEqualTo(margin));
      expect(viewSw.y - swPx.y, lessThanOrEqualTo(margin));
    });

    test('область менша за екран — тримається по центру', () {
      final c = constraint.constrain(cameraAt(const LatLng(45.0, 20.0), 5));
      final cam = cameraAt(c.center, 5);
      final mid = cam.project(zhytomyr.center);
      final centerPx = cam.project(c.center);
      expect((mid.x - centerPx.x).abs(), lessThan(1));
      expect((mid.y - centerPx.y).abs(), lessThan(1));
    });
  });

  test('точка в області — за кордоном, а не за прямокутником', () {
    // трикутник-«область»: кут прямокутника bbox до неї не належить
    const region = [
      GeoPolygon(outer: [LatLng(50, 28), LatLng(51, 28), LatLng(50, 29), LatLng(50, 28)]),
    ];
    expect(isInsideRegion(const LatLng(50.2, 28.2), region), isTrue);
    expect(isInsideRegion(const LatLng(50.9, 28.9), region), isFalse);
    expect(isInsideRegion(const LatLng(48.0, 28.2), region), isFalse);
  });
}
