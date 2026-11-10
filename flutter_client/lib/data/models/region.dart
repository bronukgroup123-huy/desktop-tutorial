import 'geo.dart';
import 'json.dart';
import 'package:latlong2/latlong.dart';

/// Елемент довідника областей (`GET /regions`). Показуємо [name], на сервер шлемо [slug].
class RegionSummary {
  const RegionSummary({required this.id, required this.name, required this.slug});

  factory RegionSummary.fromJson(Map<String, dynamic> json) => RegionSummary(
        id: req<int>(json, 'id'),
        name: req<String>(json, 'name'),
        slug: req<String>(json, 'slug'),
      );

  final int id;
  final String name;
  final String slug;
}

/// Кордон області для маски «острова» (`GET /v1-regions/{slug}/geometry`).
class RegionGeometry {
  const RegionGeometry({
    required this.id,
    required this.slug,
    required this.name,
    required this.bounds,
    required this.center,
    required this.zoom,
    required this.polygons,
    this.forests,
  });

  factory RegionGeometry.fromJson(Map<String, dynamic> json) {
    final center = req<List<dynamic>>(json, 'center');
    return RegionGeometry(
      id: req<int>(json, 'id'),
      slug: req<String>(json, 'slug'),
      name: req<String>(json, 'name'),
      bounds: GeoBounds.fromBbox(req<List<dynamic>>(json, 'bbox')),
      center: LatLng(toDouble(center[1], 'center.lat'), toDouble(center[0], 'center.lng')),
      zoom: req<num>(json, 'zoom').toDouble(),
      polygons: parseGeoPolygons(opt<Map<String, dynamic>>(json, 'geometry')),
      forests: RegionForestFiles.fromJson(opt<Map<String, dynamic>>(json, 'forests')),
    );
  }

  final int id;
  final String slug;
  final String name;
  final GeoBounds bounds;
  final LatLng center;

  /// Рекомендований початковий масштаб (сервер розраховує, щоб область вмістилась).
  final double zoom;
  final List<GeoPolygon> polygons;

  /// Файл лісів області (GitHub Releases). `null` — старий кеш/сервер без поля.
  final RegionForestFiles? forests;
}

/// Де лежить файл лісів області: опис (`version`, `sha256`) і сам GeoJSON.gz.
class RegionForestFiles {
  const RegionForestFiles({required this.metaUrl, required this.dataUrl});

  static RegionForestFiles? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final meta = opt<String>(json, 'meta_url');
    final data = opt<String>(json, 'data_url');
    if (meta == null || data == null) return null;
    return RegionForestFiles(metaUrl: meta, dataUrl: data);
  }

  final String metaUrl;
  final String dataUrl;
}
