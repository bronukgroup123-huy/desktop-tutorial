import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/pick.dart';

/// Тук-туки (`/v1-picks`): карта, картка точки, список видів і створення точки.
///
/// Створення — три кроки (ADR-002), фото ніколи не передається як base64:
///   1. `POST /v1-picks/upload-url` → посилання для завантаження;
///   2. `PUT` файлу за посиланням (потоком з диска);
///   3. `POST /v1-picks` → точка.
/// Усі кроки безпечно повторювати з тим самим `client_id`.
class PicksRepository {
  PicksRepository(this._api, {required Dio uploads}) : _uploads = uploads;

  final ApiClient _api;

  /// Окремий Dio без `apikey` / `Authorization`: посилання вже містить дозвіл.
  final Dio _uploads;

  /// Точки своєї області: публічні інших людей + власні. [mine] додає власні приватні.
  Future<PicksMap> fetchMap({bool mine = false}) async => PicksMap.fromJson(
        await _api.get('/v1-picks/map', query: {'mine': mine ? 'true' : 'false'}) as Map<String, dynamic>,
      );

  Future<PickCard> fetchCard(String id) async =>
      PickCard.fromJson(await _api.get('/v1-picks/$id') as Map<String, dynamic>);

  /// Довідник видів для вибору назви.
  Future<SpeciesList> fetchSpecies() async =>
      SpeciesList.fromJson(await _api.get('/v1-picks/species') as Map<String, dynamic>);

  /// Межа розміру фото — як у bucket `mushroom-photos` на сервері.
  static const int maxPhotoBytes = 5 * 1024 * 1024;
  static const Set<String> photoTypes = {'image/jpeg', 'image/png', 'image/webp'};

  Future<CreatedPick> createPick(NewPick pick, PickPhoto photo) async {
    // Захист від некоректного виклику: без фото або з неприйнятним фото точку не створюємо.
    if (photo.sizeBytes <= 0 || photo.sizeBytes > maxPhotoBytes || !photoTypes.contains(photo.contentType)) {
      throw const ApiException(code: ApiException.invalidPhoto);
    }
    final target = await _api.post('/v1-picks/upload-url', body: {
      'client_id': pick.clientId,
      'content_type': photo.contentType,
      'size_bytes': photo.sizeBytes,
    }) as Map<String, dynamic>;
    final uploadUrl = target['upload_url'];
    final path = target['path'];
    if (uploadUrl is! String || path is! String) {
      throw const ApiException(code: ApiException.invalidResponse);
    }

    await _upload(uploadUrl, photo);

    final description = pick.description?.trim();
    final created = await _api.post('/v1-picks', body: {
      'client_id': pick.clientId,
      'path': path,
      'lat': pick.point.latitude,
      'lng': pick.point.longitude,
      'captured_at': pick.capturedAt.toUtc().toIso8601String(),
      'visibility': pick.visibility.wire,
      'species_id': pick.speciesId,
      if (description != null && description.isNotEmpty) 'description': description,
    });
    return CreatedPick.fromJson(created as Map<String, dynamic>);
  }

  Future<void> _upload(String uploadUrl, PickPhoto photo) async {
    final Response<dynamic> res;
    try {
      res = await _uploads.put<dynamic>(
        uploadUrl,
        data: photo.openRead(),
        options: Options(
          headers: {
            Headers.contentTypeHeader: photo.contentType,
            Headers.contentLengthHeader: photo.sizeBytes,
          },
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw ApiException(code: ApiException.networkError, statusCode: e.response?.statusCode);
    }
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiException(code: ApiException.uploadFailed, statusCode: status);
    }
  }
}
