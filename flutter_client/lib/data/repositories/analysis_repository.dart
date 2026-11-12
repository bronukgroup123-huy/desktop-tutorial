import 'package:latlong2/latlong.dart';

import '../api/api_client.dart';
import '../models/analysis.dart';

/// Машинний прогноз — аналіз ділянки (`/v1-analysis`, ADR-015).
///
/// Які розміри доступні, скільки аналізів лишилось і що показати, якщо доступу
/// немає, — вирішує сервер; клієнт лише показує.
class AnalysisRepository {
  AnalysisRepository(this._api);

  final ApiClient _api;

  Future<AnalysisOverview> fetchOverview() async =>
      AnalysisOverview.fromJson(await _api.get('/v1-analysis') as Map<String, dynamic>);

  /// Аналіз квадрата [sizeKm]×[sizeKm] км з центром у [center] на сьогодні.
  /// [forest] — ліс у квадраті з полігонів на карті (сервер має не всі області).
  Future<AnalysisResult> analyze({
    required LatLng center,
    required int sizeKm,
    Map<String, dynamic>? forest,
  }) async =>
      AnalysisResult.fromJson(await _api.post('/v1-analysis', body: {
        'lat': center.latitude,
        'lng': center.longitude,
        'size_km': sizeKm,
        if (forest != null) 'forest': forest,
      }) as Map<String, dynamic>);
}
