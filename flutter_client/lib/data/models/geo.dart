import 'package:latlong2/latlong.dart';

import 'json.dart';

/// Полігон GeoJSON: зовнішній контур + «дірки». Координати в GeoJSON — `[lng, lat]`.
class GeoPolygon {
  const GeoPolygon({required this.outer, this.holes = const []});

  final List<LatLng> outer;
  final List<List<LatLng>> holes;
}

List<LatLng> _ring(Object? raw) {
  if (raw is! List) throw const FormatException('GeoJSON ring: expected list');
  return raw.map((p) {
    if (p is! List || p.length < 2) throw const FormatException('GeoJSON position: expected [lng, lat]');
    return LatLng(toDouble(p[1], 'lat'), toDouble(p[0], 'lng'));
  }).toList(growable: false);
}

GeoPolygon _polygon(Object? raw) {
  if (raw is! List || raw.isEmpty) throw const FormatException('GeoJSON polygon: expected rings');
  return GeoPolygon(
    outer: _ring(raw.first),
    holes: raw.skip(1).map(_ring).toList(growable: false),
  );
}

/// Polygon або MultiPolygon → список полігонів. Інші типи — порожній список.
List<GeoPolygon> parseGeoPolygons(Map<String, dynamic>? geometry) {
  if (geometry == null) return const [];
  final type = geometry['type'];
  final coords = geometry['coordinates'];
  if (type == 'Polygon') return [_polygon(coords)];
  if (type == 'MultiPolygon' && coords is List) {
    return coords.map(_polygon).toList(growable: false);
  }
  return const [];
}

/// `[minLng, minLat, maxLng, maxLat]`.
class GeoBounds {
  const GeoBounds({required this.southWest, required this.northEast});

  factory GeoBounds.fromBbox(List<dynamic> bbox) {
    if (bbox.length != 4) throw const FormatException('bbox: expected 4 numbers');
    return GeoBounds(
      southWest: LatLng(toDouble(bbox[1], 'bbox.minLat'), toDouble(bbox[0], 'bbox.minLng')),
      northEast: LatLng(toDouble(bbox[3], 'bbox.maxLat'), toDouble(bbox[2], 'bbox.maxLng')),
    );
  }

  final LatLng southWest;
  final LatLng northEast;

  /// Формат query-параметра `bbox` для API: `minLng,minLat,maxLng,maxLat` (5 знаків — ~1 м).
  String toQuery() => [
        southWest.longitude,
        southWest.latitude,
        northEast.longitude,
        northEast.latitude,
      ].map((v) => v.toStringAsFixed(5)).join(',');
}
