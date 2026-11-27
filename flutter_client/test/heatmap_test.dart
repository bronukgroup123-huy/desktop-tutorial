// B3.5b: теплова карта на карті — модель, клітинки-прямокутники, запит лише коли шар увімкнено, період.
import 'package:flutter_client/data/models/heatmap.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/heatmap_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data/fake_adapter.dart';

Map<String, dynamic> heatJson({bool canChange = false, int period = 3, List<Map<String, dynamic>>? cells}) => {
      'cells': cells ?? [
        {'lat': 50.4545, 'lng': 30.527, 'level': 2},
        {'lat': 50.4635, 'lng': 30.541, 'level': 9},
      ],
      'cell_lat': 0.009,
      'cell_lng': 0.014,
      'period_days': period,
      'scope': 'home',
      'scope_label': 'Ваша область',
      'can_change_period': canChange,
      'legend_label': 'Де частіше знаходили — без точних місць; лише підтверджені точки',
    };

void main() {
  test('Heatmap: клітинки з рівнем 1–3, підсумок «Ваша область · за 3 дні»', () {
    final h = Heatmap.fromJson(heatJson());
    expect(h.cells.map((c) => c.level), [2, 3], reason: 'рівень обмежено 1–3');
    expect(h.summaryLabel, 'Ваша область · за 3 дні');
    expect(Heatmap.fromJson(heatJson(period: 30)).summaryLabel, 'Ваша область · за 30 днів');
    expect(h.canChangePeriod, isFalse);
  });

  test('Heatmap.toGeoJson: кожна клітинка — замкнений прямокутник довкола центру', () {
    final g = Heatmap.fromJson(heatJson()).toGeoJson();
    final f = (g['features'] as List).first as Map<String, dynamic>;
    expect(f['properties'], {'level': 2});
    final ring = ((f['geometry'] as Map)['coordinates'] as List).first as List;
    expect(ring.length, 5);
    expect(ring.first, ring.last);
    expect((ring[0] as List)[0], closeTo(30.527 - 0.007, 1e-9));
    expect((ring[2] as List)[1], closeTo(50.4545 + 0.0045, 1e-9));
  });

  test('heatmapProvider: вимкнено — без запиту; увімкнено — GET v1-heatmap з періодом', () async {
    final (api, adapter) = makeClient((r) => FakeResponse(200, {'data': heatJson(canChange: true, period: 7)}));
    final c = ProviderContainer(overrides: [
      heatmapRepositoryProvider.overrideWithValue(HeatmapRepository(api)),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(heatmapProvider, (_, __) {});
    addTearDown(sub.close);
    expect(await c.read(heatmapProvider.future), isNull);
    expect(adapter.requests, isEmpty);
    c.read(showHeatmapProvider.notifier).state = true;
    c.read(heatmapPeriodProvider.notifier).state = '7d';
    final h = await c.read(heatmapProvider.future);
    expect(h!.periodDays, 7);
    expect(adapter.requests.single.path, endsWith('/v1-heatmap'));
    expect(adapter.requests.single.queryParameters['period'], '7d');
  });
}
