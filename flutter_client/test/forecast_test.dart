import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/core/push.dart';
import 'dart:io';
import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_client/data/local/offline_result.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/models/forecast.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/analysis_repository.dart';
import 'package:flutter_client/features/forecast/forecast_screen.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/analysis_test.dart' show resultJson;
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

  testWidgets('«Як відрізнити»: ознаки з довідника зі стікерами частин, двійник з відмінностями, правило', (tester) async {
    final species = ForecastSpecies.fromJson({
      ...(forecastJson()['top1'] as Map<String, dynamic>),
      'mushroom_type': 'flammulina_velutipes',
      'name_ua': 'Зимовий опеньок',
      'identify': identifyJson,
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => Catalog.parse(File('assets/catalog/catalog.json.gz').readAsBytesSync()))],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ForecastSpeciesCard(species: species)))),
    ));
    expect(find.byKey(const ValueKey('identify-view')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('species-identify')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1700)); // анімація появи — один раз
    expect(find.byKey(const ValueKey('identify-view')), findsOneWidget);
    expect(find.text('Пластинки'), findsWidgets); // ознака й рядок відмінності двійника
    expect(find.text('жовтий'), findsOneWidget);
    expect(find.text('Немає кільця'), findsOneWidget);
    expect(find.byKey(const ValueKey('glyph-ring')), findsOneWidget);
    expect(find.text('Галерина облямована'), findsOneWidget);
    expect(find.text('Смертельно отруйний!'), findsOneWidget);
    expect(find.text('Відсутнє'), findsOneWidget); // ❌ — у значок, не в текст
    expect(find.text('Ніколи не беріть гриби на пеньках без уважної перевірки'), findsOneWidget);
    // в кінці — посилання на цей вид у довіднику
    expect(find.widgetWithText(OutlinedButton, 'Переглянути в довіднику'), findsOneWidget);
    await tester.pumpAndSettle(); // переливання кольорів шапки зупиняється
    await tester.ensureVisible(find.byKey(const ValueKey('species-identify')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('species-identify')));
    await tester.pump();
    expect(find.byKey(const ValueKey('identify-view')), findsNothing);
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
    final (api, adapter) = makeClient((req) => _isDaily(req) ? _alreadyFresh : FakeResponse(200, {
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
    expect([_manual(adapter).single.method, _manual(adapter).single.path],
        ['PUT', '/v1-analysis/areas/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']);
    expect(_manual(adapter).single.data, {'label': 'Біля Броників'});
    expect(loads, 2); // список ділянок оновлено з сервера

    // довге натискання на клітинку — той самий діалог
    await tester.longPress(find.byKey(const ValueKey('slot-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('area-label-field')), findsOneWidget);
  });

  testWidgets('«Оновити аналіз» спершу питає: скасувати — без запиту; «Оновити» — аналіз', (tester) async {
    final (api, adapter) = makeClient((req) => _isDaily(req) ? _alreadyFresh : FakeResponse(500, {'error': 'x', 'message': 'x'}));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analysisOverviewProvider.overrideWith((ref) => overview(areas: [areaJson(withResult: true)])),
        analysisRepositoryProvider.overrideWithValue(AnalysisRepository(api)),
      ],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reanalyze')));
    await tester.pumpAndSettle();
    expect(find.text('Оновити аналіз?'), findsOneWidget);
    expect(find.textContaining('сьогодні лишилось 4 з 5'), findsOneWidget);
    await tester.tap(find.text('Скасувати'));
    await tester.pumpAndSettle();
    expect(_manual(adapter), isEmpty);

    await tester.tap(find.byKey(const ValueKey('reanalyze')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reanalyze-confirm')));
    await tester.pumpAndSettle();
    expect([_manual(adapter).single.method, _manual(adapter).single.path], ['POST', '/v1-analysis']);
  });

  testWidgets('«Оновити аналіз», коли аналізи закінчились, — пояснення без запиту', (tester) async {
    final (api, adapter) = makeClient((req) => _isDaily(req) ? _alreadyFresh : FakeResponse(200, {'data': {}}));
    final area = areaJson(withResult: true)..['usage'] = {'used': 5, 'limit': 5, 'label': 'Сьогодні: 5 з 5 аналізів'};
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analysisOverviewProvider.overrideWith((ref) => overview(areas: [area])),
        analysisRepositoryProvider.overrideWithValue(AnalysisRepository(api)),
      ],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reanalyze')));
    await tester.pumpAndSettle();
    expect(find.text('Аналізи на сьогодні закінчились'), findsOneWidget);
    expect(find.byKey(const ValueKey('reanalyze-confirm')), findsNothing);
    expect(_manual(adapter), isEmpty);
  });

  testWidgets('Щоденне оновлення: старий аналіз оновлюється сам, без списання ліміту', (tester) async {
    final (api, adapter) = makeClient((req) => FakeResponse(200, {'data': resultJson()}));
    var loads = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analysisOverviewProvider.overrideWith((ref) {
          loads++;
          return overview(areas: [areaJson(withResult: true)]);
        }),
        analysisRepositoryProvider.overrideWithValue(AnalysisRepository(api)),
      ],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump(); // перший кадр
    await tester.pump(); // post-frame — автооновлення
    expect(find.byKey(const ValueKey('auto-refreshing')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    final daily = adapter.requests.where(_isDaily).toList();
    expect(daily.length, 1);
    expect(daily.single.data, containsPair('area_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));
    expect(loads, greaterThanOrEqualTo(2)); // ділянки перечитано зі свіжим результатом
  });

  testWidgets('Щоденне оновлення без інтернету — банер, без запиту', (tester) async {
    final (api, adapter) = makeClient((req) => FakeResponse(200, {'data': resultJson()}));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analysisOverviewProvider.overrideWith(
          (ref) => overview(areas: [areaJson(withResult: true)], offlineSince: DateTime(2026, 11, 12, 9)),
        ),
        analysisRepositoryProvider.overrideWithValue(AnalysisRepository(api)),
      ],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(adapter.requests, isEmpty);
    expect(find.byKey(const ValueKey('stale-banner')), findsOneWidget);
    expect(find.textContaining('коли з\'явиться інтернет'), findsOneWidget);
  });

  testWidgets('Поділитися прогнозом: кнопка вгорі, картинка з рівнем і найкращим днем', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final area = areaJson(withResult: true);
    final res = resultJson();
    // без меж ділянки — мінікарта (офлайн карта, сховище) у цьому тесті не потрібна
    res['area'] = {...(res['area'] as Map<String, dynamic>)}..remove('bbox');
    area['last_result'] = {...res, 'best_day': {'date': '2026-11-12', 'label': 'Найкращий день: завтра'}};
    final (api, _) = makeClient((req) => _alreadyFresh);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analysisOverviewProvider.overrideWith((ref) => overview(areas: [area])),
        analysisRepositoryProvider.overrideWithValue(AnalysisRepository(api)),
      ],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('share-forecast')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('share-card')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('share-card')), matching: find.text('Білий гриб')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('share-card')), matching: find.text('Найкращий день: завтра')), findsOneWidget);
    expect(find.byKey(const ValueKey('share-send')), findsOneWidget);
  });

  testWidgets('Сповіщення про хвилі: картка лише коли push налаштовано; «Не зараз» — сховати', (tester) async {
    PushService.availableForTest = true;
    addTearDown(() => PushService.availableForTest = false);
    final (api, _) = makeClient((req) => _alreadyFresh);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analysisOverviewProvider.overrideWith((ref) => overview(areas: [areaJson(withResult: true)])),
        analysisRepositoryProvider.overrideWithValue(AnalysisRepository(api)),
        localStoreProvider.overrideWithValue(_MemoryStore()),
      ],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('wave-alerts-card')), findsOneWidget);
    await tester.tap(find.byTooltip('Не зараз'));
    await tester.pump();
    expect(find.byKey(const ValueKey('wave-alerts-card')), findsNothing);
    await tester.pump(const Duration(seconds: 5)); // таймери анімацій / запитів
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

const identifyJson = {
  'features': [
    {'part': 'cap', 'title': 'Шапка', 'text': 'Опукло- або плоско-розпростерта, 2–6 см'},
    {'part': 'underside', 'kind': 'gills', 'title': 'Пластинки', 'text': 'Рідкі, кремові або жовтуваті, прирослі до ніжки'},
    {'part': 'stem', 'title': 'Ніжка', 'text': 'Циліндрична, довга, щільна, з порожниною'},
    {'part': 'flesh', 'title': "М'якоть", 'text': 'Жовтувата, щільна, з приємним грибним запахом'},
  ],
  'cap_colors': [
    {'hex': '#e6c03a', 'label': 'жовтий'},
    {'hex': '#8b5a2b', 'label': 'коричневий'},
    {'hex': '#e0802c', 'label': 'оранжевий'},
  ],
  'underside': 'gills',
  'ring': false,
  'twin': {
    'name': 'Галерина облямована',
    'danger': 'deadly',
    'danger_label': 'Смертельно отруйний!',
    'diffs': [
      {'feature': 'Кільце на ніжці', 'ours': '❌ Відсутнє', 'twin': '✅ Чітке кільце'},
      {'feature': 'Пластинки', 'ours': 'Прирослі до ніжки', 'twin': 'Не приростають до ніжки'},
    ],
  },
  'rule': 'Ніколи не беріть гриби на пеньках без уважної перевірки',
};


/// Щоденне автооновлення (refresh: daily) — окремо від дій користувача в тестах.
bool _isDaily(RequestOptions req) => req.data is Map && (req.data as Map)['refresh'] == 'daily';
const _alreadyFresh = FakeResponse(409, {'error': 'already_fresh', 'message': 'Прогноз ділянки вже оновлено сьогодні.'});
List<RequestOptions> _manual(FakeAdapter a) => a.requests.where((r) => !_isDaily(r)).toList();


/// Сховище в пам'яті (без файлів) — для тестів екрана.
class _MemoryStore extends LocalStore {
  _MemoryStore() : super(Directory.systemTemp);

  final Map<String, Object?> _data = {};

  @override
  Future<StoredEntry?> read(String key) async =>
      _data.containsKey(key) ? StoredEntry(data: _data[key], savedAt: DateTime(2026)) : null;

  @override
  Future<void> write(String key, Object? data, {String? etag, DateTime? savedAt}) async => _data[key] = data;
}
