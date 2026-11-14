import 'package:flutter/material.dart';
import 'package:flutter_client/data/local/offline_result.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/forecast.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/analysis_repository.dart';
import 'package:flutter_client/features/forecast/forecast_screen.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';

Map<String, dynamic> forecastJson({bool withWeather = true}) => {
      'regionName': 'Житомирська',
      'date': '2026-11-09',
      'forest': 'pine (підтверджено), ? років',
      'forest_label': 'Сосновий ліс',
      'weather': withWeather
          ? {
              'icon': 'rain',
              'temp_label': '9°…17°, у середньому 13° за тиждень',
              'humidity_label': 'Вологість 78%',
              'rain_label': 'Опади: 16 мм за 3 дні, 21 мм за тиждень',
              'rain_recent_label': 'Сильний дощ 3 дні тому',
              'pressure_label': 'Тиск 1013 гПа, стабільний',
            }
          : null,
      'top1': {
        'mushroom_type': 'boletus_edulis',
        'name_ua': 'Білий гриб',
        'level': 'high',
        'level_label': 'Висока ймовірність',
        'level_color': '#22c55e',
        'when_label': 'Зараз — 3 дні після дощу · Осіння хвиля',
        'where_label': 'Південні схили',
        'why_labels': ['Дощ 16 мм за останні 3 дні'],
      },
      'alternative': null,
      'warnings': ['Уточніть тип лісу на місці'],
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('Forecast: блок погоди і forest_label', () {
    final f = Forecast.fromJson(forecastJson());
    expect(f.forestLabel, 'Сосновий ліс');
    expect(f.weather!.icon, 'rain');
    expect(f.weather!.rainRecentLabel, 'Сильний дощ 3 дні тому');
    expect(Forecast.fromJson(forecastJson(withWeather: false)).weather, isNull);
  });

  const point = ForecastPoint(lat: 50.25, lng: 28.66, forestType: 'pine', title: 'Сосновий ліс');

  testWidgets('ForecastView показує тексти з сервера', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        forecastProvider(point).overrideWith(
          (ref) async => OfflineResult(value: Forecast.fromJson(forecastJson()), savedAt: DateTime(2026, 11, 9), offline: false),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: ForecastView(point: point))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Сосновий ліс'), findsOneWidget);
    expect(find.text('Білий гриб'), findsOneWidget);
    expect(find.text('Висока ймовірність'), findsOneWidget);
    expect(find.text('Зараз — 3 дні після дощу · Осіння хвиля'), findsOneWidget);
    // Причини рівня — під «Розширені дані»
    expect(find.text('Дощ 16 мм за останні 3 дні'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('species-advanced')).first);
    await tester.pumpAndSettle();
    expect(find.text('Дощ 16 мм за останні 3 дні'), findsOneWidget);
    expect(find.text('Сильний дощ 3 дні тому'), findsOneWidget);
    expect(find.text('Уточніть тип лісу на місці'), findsOneWidget);
    expect(find.textContaining('%'), findsOneWidget, reason: 'лише вологість, жодних відсотків ймовірності');
  });

  testWidgets('Вкладка «Прогноз» без ділянок — підказка обрати ділянку на карті', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [analysisOverviewProvider.overrideWith((ref) => overview(areas: []))],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump();
    expect(find.text('Оберіть ділянку на карті'), findsOneWidget);
    expect(find.text('Відкрити карту'), findsOneWidget);
  });

  testWidgets('Без інтернету — збережений прогноз з датою', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        forecastProvider(point).overrideWith(
          (ref) async => OfflineResult(value: Forecast.fromJson(forecastJson()), savedAt: DateTime(2026, 11, 9, 14, 20), offline: true),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: ForecastView(point: point))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Немає інтернету. Показано прогноз від 09.11, 14:20.'), findsOneWidget);
    expect(find.text('Білий гриб'), findsOneWidget);
  });

  testWidgets('Картка виду: просто за замовчуванням, причини й обмеження — у «Розширені дані»', (tester) async {
    final species = ForecastSpecies.fromJson({
      ...(forecastJson()['top1'] as Map<String, dynamic>),
      'level': 'low',
      'level_label': 'Низька ймовірність',
      'level_color': '#f97316',
      'why_labels': ['Сезон цього виду'],
      'limit_labels': ['Вологість 55% — замало (краще від 70%)'],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ForecastSpeciesCard(species: species))));
    expect(find.text('Низька ймовірність'), findsOneWidget);
    // Просто за замовчуванням: рівень, «коли», «де»; причини — під «Розширені дані»
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.text('Розширені дані'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('species-advanced')));
    await tester.pump();
    expect(find.text('Сховати подробиці'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('Вологість 55% — замало (краще від 70%)'), findsOneWidget);
  });

  testWidgets('Вкладка «Прогноз»: ділянка з останнім результатом; її не змінити — лише оновити, показати, видалити',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [analysisOverviewProvider.overrideWith((ref) => overview(areas: [areaJson(withResult: true)]))],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump();
    // три клітинки: «Ділянка 1 · 5×5 км», дві інші під замком Pro
    expect(find.descendant(of: find.byKey(const ValueKey('slot-1')), matching: find.text('Ділянка 1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('slot-1')), matching: find.text('5×5 км')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('slot-2')), matching: find.byIcon(Icons.lock_outline_rounded)),
        findsOneWidget);
    expect(find.text('Сьогодні: 1 з 5 аналізів'), findsOneWidget);
    // ▶ «Хвиля по днях» — завжди у рядку значків
    expect(find.byKey(const ValueKey('play-days')), findsOneWidget);
    expect(find.text('Прогноз на 2026-11-12'), findsOneWidget);
    expect(find.textContaining('немає лісу'), findsOneWidget);
    // «Оновити аналіз» — компактний значок у рядку ділянки, без великої кнопки
    expect(find.byTooltip('Оновити аналіз'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Оновити аналіз'), findsNothing);
    expect(find.byTooltip('Показати на карті'), findsOneWidget);
    expect(find.byTooltip('Видалити ділянку'), findsOneWidget);
    // безкоштовно вже є ділянка → «Нова ділянка» не пропонується
    expect(find.text('Нова ділянка'), findsNothing);
  });

  testWidgets('Вкладка «Прогноз»: ділянка без результату і без інтернету — дії вимкнено', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analysisOverviewProvider.overrideWith(
          (ref) => overview(areas: [areaJson()], canCreate: true, offlineSince: DateTime(2026, 11, 12, 9)),
        ),
      ],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump();
    expect(find.text('Аналізу ще немає'), findsOneWidget);
    expect(find.textContaining('Немає інтернету'), findsOneWidget);
    expect(find.text('Нова ділянка'), findsWidgets);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Аналізувати ділянку'));
    expect(button.onPressed, isNull);
  });

  testWidgets('Клітинки ділянок: замок Pro, назва через олівець, ▶ на старому аналізі підказує оновити', (tester) async {
    final (api, adapter) = makeClient((req) => FakeResponse(200, {
          'data': {'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'label': 'Біля Броників', 'title': 'Біля Броників'},
        }));
    var loads = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analysisOverviewProvider.overrideWith((ref) {
          loads++;
          return overview(areas: [areaJson(withResult: true)], slots: [
            {'slot': 1, 'state': 'area', 'area_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'title': 'Ділянка 1', 'subtitle': '5×5 км'},
            {'slot': 2, 'state': 'locked', 'title': 'Ділянка 2', 'locked_label': 'Ще 2 ділянки — у Pro'},
            {'slot': 3, 'state': 'locked', 'title': 'Ділянка 3', 'locked_label': 'Ще 2 ділянки — у Pro'},
          ]);
        }),
        analysisRepositoryProvider.overrideWithValue(AnalysisRepository(api)),
      ],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('slot-2')));
    await tester.pump();
    expect(find.text('Ще 2 ділянки — у Pro'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('play-days')));
    await tester.pump();
    expect(find.textContaining('після оновлення аналізу'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rename-slot-1')));
    await tester.pumpAndSettle();
    expect(find.text('Назва ділянки'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('area-label-field')), '  Біля Броників ');
    await tester.tap(find.byKey(const ValueKey('area-label-save')));
    await tester.pumpAndSettle();
    expect([adapter.requests.single.method, adapter.requests.single.path],
        ['PUT', '/v1-analysis/areas/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']);
    expect(adapter.requests.single.data, {'label': 'Біля Броників'});
    expect(loads, 2); // список ділянок оновлено з сервера

    // довге натискання на клітинку — той самий діалог
    await tester.longPress(find.byKey(const ValueKey('slot-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('area-label-field')), findsOneWidget);
  });
}

Map<String, dynamic> areaJson({bool withResult = false}) => {
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'slot': 1,
      'lat': 50.4,
      'lng': 30.5,
      'size_km': 5,
      'size_label': '5×5 км',
      'usage': {'used': 1, 'limit': 5, 'label': 'Сьогодні: 1 з 5 аналізів'},
      'last_analyzed_at': withResult ? '2026-11-12T08:00:00Z' : null,
      'last_result': withResult
          ? {
              'area': {'id': 'a', 'slot': 1, 'lat': 50.4, 'lng': 30.5, 'size_km': 5, 'size_label': '5×5 км'},
              'date': '2026-11-12',
              'forest': {'summary_label': 'На карті в цій ділянці лісів немає', 'types': []},
              'top1': null,
              'alternative': null,
              'weather': null,
              'warnings': [],
              'usage': {'used': 1, 'limit': 5, 'label': 'Сьогодні: 1 з 5 аналізів'},
              'no_data_reason': 'У цій ділянці на карті немає лісу, тож лісові гриби тут не прогнозуємо.',
            }
          : null,
    };

AnalysisOverview overview({
  required List<Map<String, dynamic>> areas,
  bool canCreate = false,
  DateTime? offlineSince,
  List<Map<String, dynamic>>? slots,
}) =>
    AnalysisOverview.fromJson({
      if (slots != null) 'slots': slots,
      'sizes': [
        {'size_km': 5, 'label': '5×5 км', 'available': true, 'lock_label': null},
      ],
      'areas': areas,
      'can_create': areas.isEmpty || canCreate,
      'create_hint_label': 'У вас уже є ділянка. Щоб створити нову, видаліть стару у вкладці «Прогноз».',
      'usage': {'used': 1, 'limit': 5, 'label': 'Сьогодні: 1 з 5 аналізів'},
      'hint_label': 'Торкніться карти, щоб обрати центр ділянки',
    }, offlineSince: offlineSince);
