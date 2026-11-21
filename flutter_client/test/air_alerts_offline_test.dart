import 'package:dio/dio.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/safety/safety_content.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data/fake_adapter.dart';
import 'support/memory_store.dart';

void main() {
  late bool online;
  late MemoryStore store;

  ProviderContainer container() {
    final (api, _) = makeClient((RequestOptions r) => online
        ? const FakeResponse(200, {
            'data': {
              'available': true,
              'updated_at': '2026-11-21T10:41:00Z',
              'regions': [
                {'slug': 'zhytomyrska', 'scope': 'oblast', 'title': 'Повітряна тривога в області'},
              ],
            },
          })
        : const FakeResponse.offline());
    return ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      localStoreProvider.overrideWithValue(store),
      homeRegionSlugProvider.overrideWithValue('zhytomyrska'),
    ]);
  }

  Future<AirAlertState> next(ProviderContainer c, bool Function(AirAlertState) ok) async {
    for (var i = 0; i < 100; i++) {
      final v = c.read(airAlertsProvider).valueOrNull;
      if (v != null && ok(v)) return v;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('no state: ${c.read(airAlertsProvider)}');
  }

  setUp(() {
    store = MemoryStore();
    airAlertsRefresh = const Duration(milliseconds: 40);
  });
  tearDown(() => airAlertsRefresh = const Duration(minutes: 1));

  test('Зник інтернет — тривога лишається на місці з позначкою «немає зв\'язку»', () async {
    online = true;
    final c = container();
    addTearDown(c.dispose);
    final sub = c.listen(airAlertsProvider, (_, __) {});
    addTearDown(sub.close);
    final first = await next(c, (s) => s.available && !s.offline);
    expect(first.alerts.single.slug, 'zhytomyrska');
    online = false;
    final off = await next(c, (s) => s.offline);
    expect(off.available, isTrue);
    expect(off.alerts.single.title, 'Повітряна тривога в області');
  });

  test('Запуск без інтернету — одразу останні збережені дані', () async {
    online = true;
    final c1 = container();
    final s1 = c1.listen(airAlertsProvider, (_, __) {});
    await next(c1, (s) => s.available && !s.offline);
    s1.close();
    c1.dispose();

    online = false;
    final c2 = container();
    addTearDown(c2.dispose);
    final s2 = c2.listen(airAlertsProvider, (_, __) {});
    addTearDown(s2.close);
    final saved = await next(c2, (s) => s.available);
    expect(saved.offline, isTrue);
    expect(saved.alerts.single.slug, 'zhytomyrska');
    expect(saved.updatedAt, DateTime.utc(2026, 11, 21, 10, 41).toLocal());
  });
}
