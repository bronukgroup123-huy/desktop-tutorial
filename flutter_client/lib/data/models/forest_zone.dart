import 'dart:ui' show Color;

import 'geo.dart';
import 'json.dart';

/// Полігон лісу з `GET /v1-forest-zones`. Підпис і колір типу — із сервера.
class ForestZone {
  const ForestZone({
    required this.id,
    required this.forestType,
    required this.standAgeYears,
    required this.typeLabel,
    required this.typeColor,
    required this.polygons,
  });

  factory ForestZone.fromFeature(Map<String, dynamic> feature) {
    final props = req<Map<String, dynamic>>(feature, 'properties');
    return ForestZone(
      id: req<Object>(props, 'id').toString(),
      forestType: opt<String>(props, 'forest_type'),
      standAgeYears: opt<num>(props, 'stand_age_years')?.toInt(),
      typeLabel: req<String>(props, 'type_label'),
      typeColor: parseHexColor(req<String>(props, 'type_color')),
      polygons: parseGeoPolygons(opt<Map<String, dynamic>>(feature, 'geometry')),
    );
  }

  /// `{ type: FeatureCollection, features: [...] }` → список лісів.
  static List<ForestZone> listFromFeatureCollection(Map<String, dynamic> fc) =>
      (opt<List<dynamic>>(fc, 'features') ?? const [])
          .map((f) => ForestZone.fromFeature(f as Map<String, dynamic>))
          .toList(growable: false);

  final String id;
  final String? forestType;
  final int? standAgeYears;
  final String typeLabel;
  final Color typeColor;
  final List<GeoPolygon> polygons;
}

/// `#rrggbb` → [Color] (непрозорий). Некоректне значення → сірий.
Color parseHexColor(String hex) {
  final v = hex.startsWith('#') ? hex.substring(1) : hex;
  final rgb = int.tryParse(v, radix: 16);
  if (v.length != 6 || rgb == null) return const Color(0xFF9E9E9E);
  return Color(0xFF000000 | rgb);
}
