import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_client/data/api/api_client.dart';

/// Фейковий HTTP-адаптер Dio: записує запити, повертає заготовлені відповіді.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);

  final FakeResponse Function(RequestOptions req) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final r = respond(options);
    if (r.throwConnectionError) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final body = r.body;
    if (body is List<int>) {
      return ResponseBody.fromBytes(body, r.status, headers: {
        Headers.contentTypeHeader: ['application/octet-stream'],
      });
    }
    return ResponseBody.fromString(
      jsonEncode(r.body),
      r.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        ...r.headers.map((k, v) => MapEntry(k, [v])),
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class FakeResponse {
  const FakeResponse(this.status, this.body, {this.headers = const {}, this.throwConnectionError = false});
  const FakeResponse.offline() : this(0, null, throwConnectionError: true);

  final int status;
  final Object? body;
  final Map<String, String> headers;
  final bool throwConnectionError;
}

/// Простий Dio (без бази й токенів) — для завантаження файлів за повною адресою.
(Dio, FakeAdapter) makeFilesDio(FakeResponse Function(RequestOptions req) respond) {
  final adapter = FakeAdapter(respond);
  return (Dio()..httpClientAdapter = adapter, adapter);
}

(ApiClient, FakeAdapter) makeClient(FakeResponse Function(RequestOptions req) respond, {String? token = 'jwt-123'}) {
  final adapter = FakeAdapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'https://proj.supabase.co/functions/v1'))..httpClientAdapter = adapter;
  final client = ApiClient(dio: dio, publishableKey: 'pk-test', accessToken: () => token);
  return (client, adapter);
}
