import 'package:flutter/material.dart';
import 'package:flutter_client/data/local/offline_result.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/forecast.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/forecast/forecast_screen.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

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
    expect(find.text('Дощ 16 мм за останні 3 дні'), findsOneWidget);
    expect(find.text('Сильний дощ 3 дні тому'), findsOneWidget);
    expect(find.text('Уточніть тип лісу на місці'), findsOneWidget);
    expect(find.textContaining('%'), findsOneWidget, reason: 'лише вологість, жодних відсотків ймовірності');
  });

  testWidgets('Вкладка «Прогноз» без обраної точки — підказка відкрити карту', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: ForecastScreen())));
    expect(find.text('Оберіть ліс на карті'), findsOneWidget);
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

  testWidgets('Картка виду: обмежувальні фактори видно поруч із «Низька ймовірність»', (tester) async {
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
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('Вологість 55% — замало (краще від 70%)'), findsOneWidget);
  });

  testWidgets('Вкладка «Прогноз» показує аналіз ділянки повноцінним екраном', (tester) async {
    final result = AnalysisResult.fromJson({
      'area': {'id': 'a', 'slot': 1, 'lat': 50.4, 'lng': 30.5, 'size_km': 5, 'size_label': '5×5 км'},
      'date': '2026-11-12',
      'forest': {'summary_label': 'На карті в цій ділянці лісів немає', 'types': []},
      'top1': null,
      'alternative': null,
      'weather': null,
      'warnings': [],
      'usage': {'used': 1, 'limit': 5, 'label': 'Сьогодні: 1 з 5 аналізів'},
      'no_data_reason': 'У цій ділянці на карті немає лісу, тож лісові гриби тут не прогнозуємо.',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [analysisResultProvider.overrideWith((ref) => result)],
      child: const MaterialApp(home: ForecastScreen()),
    ));
    expect(find.text('Аналіз ділянки'), findsOneWidget);
    expect(find.text('Ділянка 5×5 км'), findsOneWidget);
    expect(find.textContaining('немає лісу'), findsOneWidget);
    expect(find.text('Оберіть ліс на карті'), findsNothing);

    await tester.tap(find.byTooltip('Закрити аналіз'));
    await tester.pump();
    expect(find.text('Оберіть ліс на карті'), findsOneWidget);
  });
}
