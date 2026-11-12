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
    this.areaM2,
    this.areaLabel,
    this.typeSource,
    this.typeSourceLabel,
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
      areaM2: opt<num>(props, 'area_m2')?.toDouble(),
      areaLabel: opt<String>(props, 'area_label'),
      typeSource: opt<String>(props, 'type_source'),
      typeSourceLabel: opt<String>(props, 'type_source_label'),
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

  /// Площа лісу (файл лісів області; у старих даних немає).
  final double? areaM2;

  /// «≈ 0,4 га» — готовий підпис.
  final String? areaLabel;

  /// Звідки тип: `osm_species` | `osm_leaf_type` | `osm_name` | null.
  final String? typeSource;

  /// «Порода вказана в OpenStreetMap» — наскільки надійний тип.
  final String? typeSourceLabel;
}

/// Наскільки конкретний тип: порода > хвойний/листяний/мішаний > невідомо.
int _typeRank(ForestZone z) {
  const general = {'coniferous', 'deciduous', 'mixed'};
  final t = z.forestType;
  if (t == null) return 0;
  return general.contains(t) ? 1 : 2;
}

/// Наскільки надійне джерело типу: порода з OSM > хвойний/листяний з OSM > назва.
int _sourceRank(ForestZone z) => switch (z.typeSource) {
      'osm_species' => 3,
      'osm_leaf_type' => 2,
      'osm_name' => 1,
      _ => z.forestType == null ? 0 : 2, // старі дані без джерела
    };

/// Який ліс показати визначнику, коли під пальцем кілька контурів OSM
/// (загальний «ліс» і вкладені ділянки з породою часто перекриваються):
/// надійніше джерело → конкретніший тип → менший (локальніший) контур.
ForestZone pickForestAt(List<ForestZone> hits) {
  assert(hits.isNotEmpty);
  ForestZone best = hits.first;
  for (final z in hits.skip(1)) {
    final bySource = _sourceRank(z).compareTo(_sourceRank(best));
    final byType = _typeRank(z).compareTo(_typeRank(best));
    final smaller = (z.areaM2 ?? double.infinity) < (best.areaM2 ?? double.infinity);
    if (bySource > 0 || (bySource == 0 && (byType > 0 || (byType == 0 && smaller)))) best = z;
  }
  return best;
}

/// `#rrggbb` → [Color] (непрозорий). Некоректне значення → сірий.
Color parseHexColor(String hex) {
  final v = hex.startsWith('#') ? hex.substring(1) : hex;
  final rgb = int.tryParse(v, radix: 16);
  if (v.length != 6 || rgb == null) return const Color(0xFF9E9E9E);
  return Color(0xFF000000 | rgb);
}
