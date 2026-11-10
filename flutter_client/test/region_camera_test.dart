import 'dart:math' show Point;

import 'package:flutter/widgets.dart';
import 'package:flutter_client/features/map/region_camera.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // Житомирська область (≈ 27.2–30.6 × 49.6–51.6), екран телефона.
  final zhytomyr = LatLngBounds(const LatLng(49.6, 27.2), const LatLng(51.6, 30.6));
  const phone = Size(411, 780);

  MapCamera cameraAt(LatLng center, double zoom) => MapCamera(
        crs: const Epsg3857(),
        center: center,
        zoom: zoom,
        rotation: 0,
        nonRotatedSize: Point(phone.width, phone.height),
      );

  test('масштаб під екран телефона: область вміщується, але не «видно сусідні країни»', () {
    final fit = fitRegion(zhytomyr, phone);
    expect(fit.zoom, greaterThan(6.5), reason: 'сервер давав 6 — на телефоні це занадто далеко');
    expect(fit.zoom, lessThan(8));
    final visible = cameraAt(fit.center, fit.zoom).visibleBounds;
    expect(visible.west, lessThanOrEqualTo(zhytomyr.west));
    expect(visible.east, greaterThanOrEqualTo(zhytomyr.east));
  });

  test('обмеження камери ніколи не «блокує» карту (не повертає null)', () {
    final constraint = regionConstraint(zhytomyr);
    for (final zoom in [5.0, 6.0, 7.0, 10.0, 16.0]) {
      final c = constraint.constrain(cameraAt(const LatLng(50.5, 28.7), zoom));
      expect(c, isNotNull, reason: 'zoom $zoom');
      expect(c!.zoom, zoom, reason: 'наближення/віддалення дозволене');
    }
    // старе обмеження contain на цьому екрані відхиляло все при віддаленому масштабі
    expect(CameraConstraint.contain(bounds: zhytomyr).constrain(cameraAt(const LatLng(50.5, 28.7), 6)), isNull);
  });

  test('центр карти не виходить за межі області', () {
    final c = regionConstraint(zhytomyr).constrain(cameraAt(const LatLng(45.0, 20.0), 9))!;
    expect(c.center.latitude, closeTo(49.6, 1e-9));
    expect(c.center.longitude, closeTo(27.2, 1e-9));
  });
}
