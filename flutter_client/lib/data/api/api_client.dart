import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Повертає актуальний access token (JWT) поточної сесії або `null`.
/// Береться з `supabase_flutter` при кожному запиті — токен не зберігаємо вручну.
typedef AccessTokenGetter = String? Function();

/// HTTP-клієнт до Edge Functions (`<SUPABASE_URL>/functions/v1`).
///
/// * додає `apikey` і `Authorization: Bearer <JWT>` до кожного запиту;
/// * розгортає успішну відповідь `{ "data": ... }`;
/// * перетворює будь-яку помилку на [ApiException].
class ApiClient {
  ApiClient({
    required Dio dio,
    required String publishableKey,
    required AccessTokenGetter accessToken,
  }) : _dio = dio {
    _dio.options.validateStatus = (_) => true; // статуси обробляємо самі
    _dio.options.responseType = ResponseType.json;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['apikey'] = publishableKey;
          final token = accessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  /// GET, повертає вміст поля `data`.
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: query));

  /// POST з JSON-тілом, повертає вміст поля `data`.
  Future<dynamic> post(String path, {Object? body}) =>
      _send(() => _dio.post<dynamic>(path, data: body));

  /// PATCH з JSON-тілом, повертає вміст поля `data`.
  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => _dio.patch<dynamic>(path, data: body));

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    final Response<dynamic> res;
    try {
      res = await request();
    } on DioException catch (e) {
      throw ApiException(code: ApiException.networkError, serverMessage: null, statusCode: e.response?.statusCode);
    }

    final status = res.statusCode ?? 0;
    final body = res.data;

    if (status >= 200 && status < 300) {
      if (body is Map<String, dynamic> && body.containsKey('data')) {
        return body['data'];
      }
      throw ApiException(code: ApiException.invalidResponse, statusCode: status);
    }

    if (body is Map<String, dynamic> && body['error'] is String) {
      throw ApiException(
        code: body['error'] as String,
        statusCode: status,
        serverMessage: body['message'] is String ? body['message'] as String : null,
        retryAfter: int.tryParse(res.headers.value('retry-after') ?? ''),
      );
    }
    throw ApiException(code: 'http_$status', statusCode: status);
  }
}
