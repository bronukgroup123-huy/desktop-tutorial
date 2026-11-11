import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/models/geo.dart';

/// Кілометрів в одному градусі широти.
const double _kmPerDegree = 111.32;

/// Кути квадрата [sizeKm]×[sizeKm] км з центром у [center] — лише для попереднього
/// показу на карті. Точні межі проаналізованої ділянки повертає сервер.
List<LatLng> squareAround(LatLng center, int sizeKm) {
  final half = sizeKm / 2;
  final dLat = half / _kmPerDegree;
  final dLng = half / (_kmPerDegree * math.cos(center.latitude * math.pi / 180));
  return [
    LatLng(center.latitude - dLat, center.longitude - dLng),
    LatLng(center.latitude - dLat, center.longitude + dLng),
    LatLng(center.latitude + dLat, center.longitude + dLng),
    LatLng(center.latitude + dLat, center.longitude - dLng),
  ];
}

/// Кути прямокутника за межами із сервера.
List<LatLng> squareFromBounds(GeoBounds b) => [
      LatLng(b.southWest.latitude, b.southWest.longitude),
      LatLng(b.southWest.latitude, b.northEast.longitude),
      LatLng(b.northEast.latitude, b.northEast.longitude),
      LatLng(b.northEast.latitude, b.southWest.longitude),
    ];
