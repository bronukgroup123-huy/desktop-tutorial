import '../api/api_client.dart';
import '../models/region.dart';

enum GeometryDetail { low, medium, high }

/// Довідник областей і їхні кордони.
class RegionsRepository {
  RegionsRepository(this._api);

  final ApiClient _api;
  final Map<String, RegionGeometry> _geometryCache = {};

  /// Список областей для онбордингу (`GET /regions`, публічний).
  Future<List<RegionSummary>> fetchRegions() async {
    final data = await _api.get('/regions') as List<dynamic>;
    return data
        .map((e) => RegionSummary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Кордон області для маски (`GET /v1-regions/{slug}/geometry`). Кешується в пам'яті —
  /// кордони не змінюються, сервер також віддає Cache-Control на 24 год.
  Future<RegionGeometry> fetchGeometry(
    String slug, {
    GeometryDetail detail = GeometryDetail.medium,
  }) async {
    final key = '$slug:${detail.name}';
    final cached = _geometryCache[key];
    if (cached != null) return cached;
    final data = await _api.get(
      '/v1-regions/${Uri.encodeComponent(slug)}/geometry',
      query: {'detail': detail.name},
    );
    return _geometryCache[key] = RegionGeometry.fromJson(data as Map<String, dynamic>);
  }
}
