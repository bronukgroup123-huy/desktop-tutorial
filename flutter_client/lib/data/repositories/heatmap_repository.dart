import '../api/api_client.dart';
import '../models/heatmap.dart';

/// Теплова карта знахідок (`/v1-heatmap`). Доступ (рівень, область, період) перевіряє сервер;
/// відмову («з рівня Лісовик», «у Pro») повертає як ApiException з текстом для людини.
class HeatmapRepository {
  HeatmapRepository(this._api);

  final ApiClient _api;

  /// [period] — `3d`, `7d` або `30d`.
  Future<Heatmap> fetch({String period = '3d'}) async =>
      Heatmap.fromJson(await _api.get('/v1-heatmap', query: {'period': period}) as Map<String, dynamic>);
}
