import 'dart:math' show Point;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Камера, у яку вміщується вся область на ЦЬОМУ екрані.
///
/// Масштаб `zoom` із сервера розрахований «наосліп» (без розміру екрана) і на
/// вузькому телефоні виходить замалим. Тому стартовий масштаб і мінімальний
/// масштаб рахуємо на клієнті під реальний розмір карти.
({LatLng center, double zoom}) fitRegion(
  LatLngBounds bounds,
  Size size, {
  EdgeInsets padding = const EdgeInsets.fromLTRB(16, 80, 16, 24),
}) {
  final w = size.width > 0 ? size.width : 400.0;
  final h = size.height > 0 ? size.height : 800.0;
  final camera = MapCamera(
    crs: const Epsg3857(),
    center: bounds.center,
    zoom: 5,
    rotation: 0,
    nonRotatedSize: Point(w, h),
  );
  final fitted = CameraFit.bounds(bounds: bounds, padding: padding).fit(camera);
  return (center: fitted.center, zoom: fitted.zoom);
}

/// Обмеження камери: ЦЕНТР карти не виходить за межі області.
///
/// Раніше було `CameraConstraint.contain` — воно вимагає, щоб увесь екран
/// вміщувався в межі області. Якщо область на екрані менша за сам екран,
/// `contain` повертає null і flutter_map відхиляє БУДЬ-ЯКИЙ рух камери —
/// карта «застрягає» (не наближається і не зсувається).
CameraConstraint regionConstraint(LatLngBounds bounds) =>
    CameraConstraint.containCenter(bounds: bounds);
