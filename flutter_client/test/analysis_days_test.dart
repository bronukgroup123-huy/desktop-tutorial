import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/features/analysis/analysis_result_view.dart';
import 'package:flutter_client/features/analysis/weather_scene.dart';

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

Future<void> _pump(WidgetTester tester, AnalysisResult r, {WeekPlayController? play}) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AnalysisResultView(result: r, playController: play))),
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
    // Заголовка «Прогноз ділянки» більше немає (рішення PO 2026-11-14): смужка днів — біля погоди.
    expect(find.text('Прогноз ділянки'), findsNothing);
    final stripY = tester.getTopLeft(find.byType(AnalysisDayStrip)).dy;
    expect(tester.getTopLeft(find.text('Погода Сьогодні')).dy, greaterThan(stripY));
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

  testWidgets('▶ у верхньому рядку керує анімацією; старий аналіз — підказка оновити', (tester) async {
    final play = WeekPlayController();
    addTearDown(play.dispose);
    await _pump(tester, AnalysisResult.fromJson({...daysJson(), 'week_animation': {'allowed': true}}), play: play);
    expect(find.byKey(const ValueKey('play-days')), findsNothing); // значок — у рядку екрана
    play.press();
    await tester.pump();
    expect(play.playing, isTrue);
    expect(find.text('Погода Сьогодні'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text('Погода Завтра'), findsOneWidget);
    play.press(); // пауза
    await tester.pump();
    expect(play.playing, isFalse);

    // аналіз до появи анімації (без week_animation) — натискання підказує оновити
    final stale = WeekPlayController();
    addTearDown(stale.dispose);
    await _pump(tester, AnalysisResult.fromJson(daysJson()), play: stale);
    await tester.pump();
    stale.press();
    await tester.pump();
    expect(find.text(kWeekAnimationStaleLabel), findsOneWidget);
    expect(stale.playing, isFalse);
  });

  testWidgets('Погода: висновок для грибів і графік; торкнутися дня на графіку — обрати день', (tester) async {
    final json = daysJson();
    final days = [for (final d in json['days'] as List) Map<String, dynamic>.from(d as Map)];
    for (final d in days) {
      d['weather'] = <String, dynamic>{
        ...(d['weather'] as Map),
        'verdict_label': 'Ґрунт вологий після дощів — добре для грибів',
        'verdict_tone': 'good',
      };
    }
    json['days'] = days;
    json['weather_chart'] = {
      'title_label': 'Погода: тиждень до сьогодні й прогноз',
      'rain_legend_label': 'опади, мм',
      'days': [
        for (final (i, date) in ['2026-11-08', '2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13'].indexed)
          {
            'date': date, 'label': 'Пн', 'date_label': '${date.substring(8)}.11',
            'tmin': i, 'tmax': i + 6, 'rain': i == 1 ? 12 : 0, 'forecast': i > 3, 'today': i == 3,
          },
      ],
    };
    await _pump(tester, AnalysisResult.fromJson(json));
    expect(find.byKey(const ValueKey('weather-verdict')), findsOneWidget);
    expect(find.text('Ґрунт вологий після дощів — добре для грибів'), findsOneWidget);
    // простий вигляд: графік — у «Розширені дані погоди»
    expect(find.byKey(const ValueKey('weather-chart')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('weather-advanced')));
    await tester.tap(find.byKey(const ValueKey('weather-advanced')));
    await tester.pump();
    expect(find.byKey(const ValueKey('weather-chart')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('weather-chart')));
    await tester.pump();
    expect(find.text('Погода Сьогодні'), findsOneWidget);
    // остання колонка графіка — 13.11 (день смужки) → обирається
    final chart = tester.getRect(find.byKey(const ValueKey('weather-chart')));
    await tester.tapAt(Offset(chart.right - 4, chart.center.dy));
    await tester.pump();
    expect(find.text('Погода Пт 13'), findsOneWidget);
    // перша колонка — минуле, не день смужки → нічого не змінюється
    await tester.tapAt(Offset(chart.left + 4, chart.center.dy));
    await tester.pump();
    expect(find.text('Погода Пт 13'), findsOneWidget);
  });

  testWidgets('Погода: анімована сцена з грибом-маскотом за погодою дня, молоді гриби за хвилею', (tester) async {
    final json = daysJson();
    final days = [for (final d in json['days'] as List) Map<String, dynamic>.from(d as Map)];
    final scenes = ['sunny', 'heavy_rain', 'snow'];
    for (final (i, d) in days.indexed) {
      d['weather'] = <String, dynamic>{
        ...(d['weather'] as Map),
        'scene': scenes[i],
        'scene_label': ['Сонячно', 'Злива', 'Сніг'][i],
        'sprouts': 'many',
      };
    }
    json['days'] = days;
    await _pump(tester, AnalysisResult.fromJson(json));
    expect(find.byKey(const ValueKey('weather-scene-sunny')), findsOneWidget);
    expect(find.text('Сонячно'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // анімація йде без помилок
    await tester.tap(find.byKey(const ValueKey('day-2026-11-12')));
    await tester.pump();
    expect(find.byKey(const ValueKey('weather-scene-heavyRain')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('day-2026-11-13')));
    await tester.pump();
    expect(find.byKey(const ValueKey('weather-scene-snow')), findsOneWidget);
    expect(parseWeatherScene('partly_cloudy'), WeatherSceneKind.partlyCloudy);
    expect(parseWeatherScene(null), isNull);
    expect([sproutCount('none'), sproutCount('few'), sproutCount('many')], [0, 2, 5]);
  });

  testWidgets('Картка гриба: «Чому середня» і смужка хвилі; подробиці — «Сприяє» / «Не вистачає»', (tester) async {
    final json = daysJson();
    final days = [for (final d in json['days'] as List) Map<String, dynamic>.from(d as Map)];
    days[0]['top1'] = <String, dynamic>{
      ...(days[0]['top1'] as Map),
      'level': 'medium',
      'reason_label': 'Чому середня: хвиля тільки починається — гриби ще дрібні й поодинокі',
      'why_labels': ['Підходящий ліс: сосновий ліс'],
      'limit_labels': ['Хвиля тільки починається — гриби ще дрібні й поодинокі'],
      'wave': {
        'phase': 'flush', 'day': 1, 'days': 20, 'stage': 'rise', 'label': 'Хвиля зараз — 1-й день з 20',
        'segments': [{'days': 4, 'label': 'підйом'}, {'days': 9, 'label': 'розпал'}, {'days': 7, 'label': 'спад'}],
      },
    };
    json['days'] = days;
    await _pump(tester, AnalysisResult.fromJson(json));
    expect(find.byKey(const ValueKey('species-reason')), findsOneWidget);
    expect(find.textContaining('хвиля тільки починається', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('wave-strip')), findsOneWidget);
    expect(find.text('Хвиля зараз — 1-й день з 20'), findsOneWidget);
    expect(find.text('Зараз'), findsNothing); // рядок «коли» замінено смужкою
    expect(find.text('підйом'), findsOneWidget);
    expect(find.text('Сприяє'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('species-advanced')).first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('species-advanced')).first);
    await tester.pump();
    expect(find.text('Сприяє'), findsOneWidget);
    expect(find.text('Не вистачає'), findsOneWidget);
  });

  testWidgets('Ліс: пояснення про уточнення не на головному екрані; без можливості — кнопка пояснює', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisResultView(
          result: AnalysisResult.fromJson({
            ...daysJson(),
            'forest': <String, dynamic>{
              ...(daysJson()['forest'] as Map),
              'refine_note_label': 'Уточнення діє лише для вашої ділянки. Знайдете тут гриб — зробіть тук-тук.',
            },
          }),
          refineHintLabel: 'Уточнити ліс сьогодні вже не можна — ліміт 2 рази на добу',
        ),
      ),
    ));
    expect(find.textContaining('тук-тук'), findsNothing);
    expect(find.textContaining('ліміт 2 рази'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('refine-forest')));
    await tester.pump();
    expect(find.textContaining('ліміт 2 рази'), findsOneWidget);
  });
}
