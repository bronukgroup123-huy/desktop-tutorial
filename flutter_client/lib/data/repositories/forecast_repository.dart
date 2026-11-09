import '../api/api_client.dart';
import '../models/forecast.dart';

/// Прогноз для точки в межах Home Region (`POST /v1-forecast`).
class ForecastRepository {
  ForecastRepository(this._api);

  final ApiClient _api;

  Future<Forecast> fetchForecast({
    required double lat,
    required double lng,
    required DateTime date,
    String? forestType,
  }) async {
    final data = await _api.post('/v1-forecast', body: {
      'lat': lat,
      'lng': lng,
      'date': _ymd(date),
      if (forestType != null) 'forestType': forestType,
    });
    return Forecast.fromJson(data as Map<String, dynamic>);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
