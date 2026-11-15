import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/features/forecast/home_widget_sync.dart';

import 'analysis_days_test.dart' show daysJson;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Віджет на головному екрані: ділянка, рівень сьогодні, найкращий гриб і день; без повторів', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async {
        calls.add(call);
        return true;
      },
    );
    HomeWidgetSync.reset();
    final result = AnalysisResult.fromJson(daysJson());
    final area = AnalysisArea.fromJson({
      'id': 'a', 'slot': 1, 'lat': 50.4, 'lng': 30.5, 'size_km': 5, 'size_label': '5×5 км', 'title': 'Броники',
    });
    await HomeWidgetSync.update(area, result, now: DateTime(2026, 11, 15, 9, 5));
    final saved = {
      for (final c in calls.where((c) => c.method == 'saveWidgetData'))
        (c.arguments as Map)['id']: (c.arguments as Map)['data'],
    };
    expect(saved['title'], 'Броники');
    expect(saved['level'], 'Сьогодні: низька ймовірність');
    expect(saved['species'], 'Найкращий: Опеньок');
    expect(saved['best'], 'Найкращий день: завтра');
    expect(saved['updated'], 'Оновлено 09:05');
    expect(calls.where((c) => c.method == 'updateWidget').length, 1);

    // ті самі дані — не перезаписуємо
    calls.clear();
    await HomeWidgetSync.update(area, result, now: DateTime(2026, 11, 15, 10, 0));
    expect(calls, isEmpty);
  });
}
