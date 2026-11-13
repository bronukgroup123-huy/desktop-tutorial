import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/models/geo.dart';

/// Поля навколо області на екрані (верх — під заголовок з назвою області).
const EdgeInsets regionPadding = EdgeInsets.fromLTRB(16, 80, 16, 24);

/// Невеликий відступ за кордоном, який дозволено бачити при прокручуванні, px.
const double regionMarginPx = 16;

/// Камера, у яку вміщується вся область на ЦЬОМУ екрані (з полями [regionPadding]).
///
/// Масштаб `zoom` із сервера розрахований без розміру екрана і на вузькому
/// телефоні виходить замалим. Тому стартовий і мінімальний масштаб рахуємо на
/// клієнті під реальний розмір карти — і заново при повороті екрана.
({LatLng center, double zoom}) fitRegion(
  LatLngBounds bounds,
  Size size, {
  EdgeInsets padding = regionPadding,
}) {
  final w = size.width > 0 ? size.width : 400.0;
  final h = size.height > 0 ? size.height : 800.0;
  final camera = MapCamera(
    crs: const Epsg3857(),
    center: bounds.center,
    zoom: 5,
    rotation: 0,
    nonRotatedSize: Size(w, h),
  );
  final fitted = CameraFit.bounds(bounds: bounds, padding: padding).fit(camera);
  return (center: fitted.center, zoom: fitted.zoom);
}

/// Обмеження камери «острів області».
///
/// * Наближена область більша за екран → екран не виходить за кордон
///   (дозволено лише [marginPx] за ним).
/// * Область уміщується в екран → вона просто тримається по центру.
///
/// На відміну від `CameraConstraint.contain` ніколи не повертає null: той у
/// другому випадку відхиляв БУДЬ-ЯКИЙ рух камери, і карта «застрягала».
@immutable
class RegionCameraConstraint extends CameraConstraint {
  const RegionCameraConstraint({required this.bounds, this.marginPx = regionMarginPx});

  final LatLngBounds bounds;
  final double marginPx;

  @override
  MapCamera constrain(MapCamera camera) {
    final zoom = camera.zoom;
    final ne = camera.projectAtZoom(bounds.northEast, zoom);
    final sw = camera.projectAtZoom(bounds.southWest, zoom);
    final half = camera.size / 2;

    final minX = math.min(sw.dx, ne.dx) - marginPx;
    final maxX = math.max(sw.dx, ne.dx) + marginPx;
    final minY = math.min(sw.dy, ne.dy) - marginPx;
    final maxY = math.max(sw.dy, ne.dy) + marginPx;

    double axis(double value, double lo, double hi, double halfSize) {
      final okLo = lo + halfSize;
      final okHi = hi - halfSize;
      if (okLo > okHi) return (lo + hi) / 2; // область менша за екран — по центру
      return value.clamp(okLo, okHi);
    }

    final c = camera.projectAtZoom(camera.center, zoom);
    final constrained = Offset(axis(c.dx, minX, maxX, half.width), axis(c.dy, minY, maxY, half.height));
    if (constrained == c) return camera;
    return camera.withPosition(center: camera.unprojectAtZoom(constrained, zoom));
  }

  @override
  bool operator ==(Object other) =>
      other is RegionCameraConstraint && other.bounds == bounds && other.marginPx == marginPx;

  @override
  int get hashCode => Object.hash(bounds, marginPx);
}

/// Чи точка всередині області (по кордону з сервера, а не по прямокутнику bbox).
bool isInsideRegion(LatLng p, List<GeoPolygon> polygons) {
  bool inRing(List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      final crosses = (a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  return polygons.any((poly) => inRing(poly.outer) && !poly.holes.any(inRing));
}
