import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adapter.dart';

void main() {
  test('додає apikey і Bearer, розгортає { data }', () async {
    final (api, adapter) = makeClient((_) => const FakeResponse(200, {'data': {'ok': true}}));
    final data = await api.get('/v1-me');
    expect(data, {'ok': true});
    final h = adapter.requests.single.headers;
    expect(h['apikey'], 'pk-test');
    expect(h['Authorization'], 'Bearer jwt-123');
  });

  test('без сесії — без Authorization', () async {
    final (api, adapter) = makeClient((_) => const FakeResponse(200, {'data': []}), token: null);
    await api.get('/regions');
    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('помилка сервера → ApiException з кодом і текстом із сервера', () async {
    final (api, _) = makeClient((_) => const FakeResponse(
          403,
          {'error': 'outside_home_region', 'message': 'Точка поза вашою областю.'},
        ));
    await expectLater(
      api.post('/v1-forecast', body: {}),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'outside_home_region')
          .having((e) => e.statusCode, 'status', 403)
          .having((e) => e.userMessage, 'userMessage', 'Точка поза вашою областю.')),
    );
  });

  test('429 → retryAfter із заголовка', () async {
    final (api, _) = makeClient((_) => const FakeResponse(
          429,
          {'error': 'rate_limited', 'message': 'Забагато запитів'},
          headers: {'retry-after': '60'},
        ));
    await expectLater(
      api.get('/v1-forest-zones'),
      throwsA(isA<ApiException>().having((e) => e.retryAfter, 'retryAfter', 60).having((e) => e.isRateLimited, 'rl', true)),
    );
  });

  test('немає мережі → network_error з людським текстом', () async {
    final (api, _) = makeClient((_) => const FakeResponse.offline());
    await expectLater(
      api.get('/v1-me'),
      throwsA(isA<ApiException>()
          .having((e) => e.isNetworkError, 'network', true)
          .having((e) => e.userMessage, 'msg', contains('інтернет'))),
    );
  });

  test('2xx без конверта { data } → invalid_response', () async {
    final (api, _) = makeClient((_) => const FakeResponse(200, {'foo': 1}));
    await expectLater(api.get('/v1-me'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_response')));
  });

  test('помилка без JSON-коду → http_<status>', () async {
    final (api, _) = makeClient((_) => const FakeResponse(502, 'Bad gateway'));
    await expectLater(api.get('/v1-me'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'http_502')));
  });
}
