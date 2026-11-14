import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/features/analysis/analysis_result_view.dart';

import 'data/analysis_test.dart' show resultJson;

Map<String, dynamic> _species(String name, String level, String label) => {
      'mushroom_type': name,
      'name_ua': name,
      'level': level,
      'level_label': label,
      'level_color': '#22c55e',
      'when_label': 'Зараз',
      'where_label': 'У лісі',
      'why_labels': <String>[],
    };

Map<String, dynamic> _day(String date, String label, String level, String short, {String? top, bool approx = false}) => {
      'date': date,
      'day_label': label,
      'approximate': approx,
      'approximate_label': approx ? 'Орієнтовно: погоду так далеко прогнозують менш точно' : null,
      'level': level,
      'level_label': '$short ймовірність',
      'level_short_label': short,
      'level_color': '#22c55e',
      'top1': top == null ? null : _species(top, level, '$short ймовірність'),
      'alternative': null,
      'weather': {
        'icon': 'sun',
        'day_label': 'Погода $label',
        'temp_label': 't',
        'humidity_label': 'h',
        'rain_label': 'r',
      },
      'warnings': <String>[],
      'no_data_reason': top == null ? 'Цього дня умов немає.' : null,
    };

Map<String, dynamic> daysJson() => {
      ...resultJson(),
      'days': [
        _day('2026-11-11', 'Сьогодні', 'low', 'Низька', top: 'Опеньок'),
        _day('2026-11-12', 'Завтра', 'medium', 'Середня', top: 'Лисичка'),
        _day('2026-11-13', 'Пт 13', 'no_data', '—'),
      ],
      'horizon_days': 3,
      'best_day': {'date': '2026-11-12', 'label': 'Найкращий день: завтра'},
      'locked_days': [
        {'date': '2026-11-14', 'day_label': 'Сб 14'},
        {'date': '2026-11-15', 'day_label': 'Нд 15'},
      ],
      'locked_label': 'Ще 4 дні прогнозу — у Pro',
    };

Future<void> _pump(WidgetTester tester, AnalysisResult r) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AnalysisResultView(result: r))),
    );

void main() {
  test('AnalysisResult: дні, найкращий день, дні під замком', () {
    final r = AnalysisResult.fromJson(daysJson());
    expect(r.days.map((d) => d.dayLabel), ['Сьогодні', 'Завтра', 'Пт 13']);
    expect(r.days[1].levelShortLabel, 'Середня');
    expect(r.days[1].top1!.species.nameUa, 'Лисичка');
    expect(r.bestDay?.label, 'Найкращий день: завтра');
    expect(r.lockedDays.map((d) => d.dayLabel), ['Сб 14', 'Нд 15']);
    final tomorrow = r.forDay(r.days[1]);
    expect(tomorrow.top1!.species.nameUa, 'Лисичка');
    expect(tomorrow.forestSummaryLabel, r.forestSummaryLabel); // ліс той самий
    expect(tomorrow.weather!.dayLabel, 'Погода Завтра');
  });

  test('AnalysisResult: старий збережений результат без днів читається', () {
    final r = AnalysisResult.fromJson(resultJson());
    expect(r.days, isEmpty);
    expect(r.bestDay, isNull);
    expect(r.lockedDays, isEmpty);
  });

  testWidgets('Смужка днів: перемикання дня без запитів, найкращий день, 🔒 Pro', (tester) async {
    await _pump(tester, AnalysisResult.fromJson(daysJson()));
    expect(find.text('Прогноз ділянки'), findsOneWidget);
    expect(find.text('Опеньок'), findsWidgets); // сьогодні
    expect(find.text('Погода Сьогодні'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('day-2026-11-12')));
    await tester.pump();
    expect(find.text('Лисичка'), findsWidgets);
    expect(find.text('Опеньок'), findsNothing);
    expect(find.text('Погода Завтра'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('day-2026-11-13')));
    await tester.pump();
    expect(find.text('Цього дня умов немає.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('best-day')));
    await tester.pump();
    expect(find.text('Лисичка'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('locked-2026-11-14')));
    await tester.pump();
    expect(find.text('Ще 4 дні прогнозу — у Pro'), findsOneWidget);
  });

  testWidgets('Без днів (старий результат) — смужки немає', (tester) async {
    await _pump(tester, AnalysisResult.fromJson(resultJson()));
    expect(find.byType(AnalysisDayStrip), findsNothing);
    expect(find.text('Прогноз на 2026-11-11'), findsOneWidget);
  });
}
