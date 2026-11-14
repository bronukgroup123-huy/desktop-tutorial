import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/models/geo.dart';

/// Поля навколо області на екрані (верх — під заголовок з назвою області).
const EdgeInsets regionPadding = EdgeInsets.fromLTRB(16, 80, 16, 24);

/// Розмір світу на масштабі 0 у логічних пікселях — як у MapLibre (плитки 512 px).
/// У растрових картах (flutter_map) — 256, тож той самий масштаб там на 1 «ближче».
const double mapLibreWorldSize = 512;

/// Web Mercator: широта/довгота → частка світу 0…1 (x — на схід, y — на південь).
({double x, double y}) _mercator(LatLng p) {
  final lat = p.latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  return (
    x: (p.longitude + 180) / 360,
    y: (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2,
  );
}

LatLng _unmercator(double x, double y) {
  final n = math.pi - 2 * math.pi * y;
  return LatLng(180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n))), x * 360 - 180);
}

/// Камера, у яку вміщується вся область на ЦЬОМУ екрані (з полями [padding]).
///
/// Масштаб `zoom` із сервера розрахований без розміру екрана і на вузькому
/// телефоні виходить замалим. Тому стартовий і мінімальний масштаб рахуємо на
/// клієнті під реальний розмір карти — і заново при повороті екрана.
({LatLng center, double zoom}) fitRegion(
  GeoBounds bounds,
  Size size, {
  EdgeInsets padding = regionPadding,
  double worldSize = mapLibreWorldSize,
}) {
  final w = (size.width > 0 ? size.width : 400.0) - padding.horizontal;
  final h = (size.height > 0 ? size.height : 800.0) - padding.vertical;
  final sw = _mercator(bounds.southWest);
  final ne = _mercator(bounds.northEast);
  final dx = (ne.x - sw.x).abs().clamp(1e-9, 1.0);
  final dy = (sw.y - ne.y).abs().clamp(1e-9, 1.0);
  final zoom = math.log(math.min(math.max(w, 1) / (dx * worldSize), math.max(h, 1) / (dy * worldSize))) / math.ln2;
  // Центр — з урахуванням несиметричних полів (зверху заголовок).
  final scale = worldSize * math.pow(2, zoom);
  final cx = (sw.x + ne.x) / 2 + (padding.right - padding.left) / 2 / scale;
  final cy = (sw.y + ne.y) / 2 + (padding.bottom - padding.top) / 2 / scale;
  return (center: _unmercator(cx, cy), zoom: zoom);
}

/// Що видно на екрані [size] з камерою [center]/[zoom] (для перевірок): пд-зх і пн-сх кути.
({LatLng southWest, LatLng northEast}) visibleExtent(
  LatLng center,
  double zoom,
  Size size, {
  double worldSize = mapLibreWorldSize,
}) {
  final c = _mercator(center);
  final scale = worldSize * math.pow(2, zoom);
  final hw = size.width / 2 / scale, hh = size.height / 2 / scale;
  return (southWest: _unmercator(c.x - hw, c.y + hh), northEast: _unmercator(c.x + hw, c.y - hh));
}

/// Квадрат-обрис точок (для «Показати ділянку на карті»).
GeoBounds boundsOf(Iterable<LatLng> points) {
  var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
  for (final p in points) {
    s = math.min(s, p.latitude);
    n = math.max(n, p.latitude);
    w = math.min(w, p.longitude);
    e = math.max(e, p.longitude);
  }
  return GeoBounds(southWest: LatLng(s, w), northEast: LatLng(n, e));
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
