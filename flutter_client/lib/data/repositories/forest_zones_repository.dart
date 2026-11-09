import '../api/api_client.dart';
import '../models/forest_zone.dart';
import '../models/geo.dart';

/// Полігони лісів — сервер віддає ТІЛЬКИ Home Region користувача (ADR-015 §15.2).
class ForestZonesRepository {
  ForestZonesRepository(this._api);

  final ApiClient _api;

  /// [bounds] — видима частина карти (без неї — уся область);
  /// [zoom] — масштаб, сервер спрощує геометрію для дрібних масштабів.
  Future<List<ForestZone>> fetchForestZones({
    GeoBounds? bounds,
    int? zoom,
    int? limit,
  }) async {
    final data = await _api.get('/v1-forest-zones', query: {
      if (bounds != null) 'bbox': bounds.toQuery(),
      if (zoom != null) 'z': zoom,
      if (limit != null) 'limit': limit,
    });
    return ForestZone.listFromFeatureCollection(data as Map<String, dynamic>);
  }
}
