import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/safety/safety_content.dart';
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_client/features/safety/safety_guides.dart';
import 'package:flutter_client/features/safety/sos_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'catalog_test.dart' show catalog;
import 'safety_test.dart' show FakeDevice, frames;
import 'support/memory_store.dart';

/// Вбудовані тексти (ті самі, що типові на сервері).
final bundled = SafetyContent.fromJson(
  jsonDecode(File('assets/safety/safety_content.json').readAsStringSync()) as Map<String, dynamic>,
);

class FixedContent extends SafetyContentNotifier {
  FixedContent(this.c);
  final SafetyContent c;
  @override
  Future<SafetyContent> build() async => c;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => null;
    CatalogPhotoCache.directory = () async => null;
  });

  Widget app(Widget home, {List<Override> extra = const [], MemoryStore? store}) => ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store ?? MemoryStore()),
          safetyContentProvider.overrideWith(() => FixedContent(bundled)),
          safetyDeviceProvider.overrideWithValue(FakeDevice()),
          ...extra,
        ],
        child: MaterialApp(home: home),
      );

  test('Вбудовані тексти: банер ДСНС, три довідки, чек-лист, поради на час тривоги', () {
    expect(bundled.notices.single.id, 'mines');
    expect(bundled.notices.single.linkUrl, startsWith('https://dsns.gov.ua'));
    expect(bundled.guides.map((g) => g.id), ['lost', 'poisoning', 'dangers']);
    expect(bundled.guide('poisoning')!.sections.first.items.first, contains('103'));
    expect(bundled.guide('dangers')!.sections.map((s) => s.title), ['Кліщі', 'Укус гадюки', 'Кабани й інші звірі', 'Сезон полювання']);
    expect(bundled.checklist.length, greaterThanOrEqualTo(6));
    expect(bundled.airAlertTips.length, 3);
  });

  testWidgets('Довідка «Заблукали?»: кроки нумеровані', (tester) async {
    await tester.pumpWidget(app(SafetyGuideScreen(guide: bundled.guide('lost')!)));
    expect(find.byKey(const ValueKey('guide-lost')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('Зупиніться'), findsWidgets);
  });

  testWidgets('Банер ДСНС: заголовок, текст і посилання на офіційний ресурс', (tester) async {
    await tester.pumpWidget(app(Scaffold(body: SafetyNoticeBanner(notice: bundled.notices.single))));
    expect(find.text('Мінна небезпека'), findsOneWidget);
    expect(find.text('Офіційна інформація — ДСНС'), findsOneWidget);
  });

  testWidgets('Повітряна тривога: банер лише для своєї області, з порадами для лісу', (tester) async {
    Widget withAlerts(String? home) => app(
          const Scaffold(body: AirAlertBanner()),
          extra: [
            homeRegionSlugProvider.overrideWithValue(home),
            airAlertsProvider.overrideWith((ref) => Stream.value([(slug: 'zhytomyrska', scope: 'oblast', title: 'Повітряна тривога в області')])),
          ],
        );
    await tester.pumpWidget(withAlerts('lvivska'));
    await tester.pump();
    expect(find.byKey(const ValueKey('air-alert')), findsNothing);
    await tester.pumpWidget(withAlerts('zhytomyrska'));
    await tester.pump();
    expect(find.byKey(const ValueKey('air-alert')), findsOneWidget);
    expect(find.textContaining('Відійдіть від доріг'), findsOneWidget);
  });

  testWidgets('Чек-лист: позначки на сьогодні зберігаються; готовність без інтернету — з кнопкою завантажити', (tester) async {
    final store = MemoryStore();
    await tester.pumpWidget(app(
      const ChecklistScreen(),
      store: store,
      extra: [
        offlineReadinessProvider.overrideWithValue(const [
          (id: 'map', label: 'Офлайн карта області', ready: true, action: 'Завантажити', route: '/map'),
          (id: 'ai', label: 'ШІ-розпізнавання', ready: false, action: 'Завантажити', route: '/recognize'),
        ]),
      ],
    ));
    await tester.pump();
    expect(find.text('0 з ${bundled.checklist.length}'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('check-phone')));
    await tester.pump();
    expect(find.text('1 з ${bundled.checklist.length}'), findsOneWidget);
    expect((store.data[ChecklistNotifier.key] as Map)['done'], ['phone']);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('ready-ai')), 200);
    expect(find.text('Є на телефоні'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Завантажити'), findsOneWidget);
  });

  testWidgets('Картка для рятувальників: лише на телефоні, видно на екрані SOS', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    await tester.pumpWidget(app(
      Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RescueCardScreen())), child: const Text('card')),
            TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SosScreen(sirenOnStart: false))), child: const Text('sos')),
          ]),
        ),
      ),
      store: store,
    ));
    await tester.tap(find.text('card'));
    await frames(tester);
    await tester.enterText(find.byKey(const ValueKey('rc-allergies')), 'пеніцилін');
    await tester.enterText(find.byKey(const ValueKey('rc-contact')), 'Мама, 067 123 45 67');
    await tester.tap(find.byKey(const ValueKey('rc-save')));
    await frames(tester);
    expect((store.data[RescueCardNotifier.key] as Map)['allergies'], 'пеніцилін');
    await tester.tap(find.text('sos'));
    await frames(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('rescue-card-view')));
    expect(find.textContaining('пеніцилін', findRichText: true), findsOneWidget);
    expect(find.textContaining('Мама, 067 123 45 67', findRichText: true), findsOneWidget);
  });

  testWidgets('Небезпечні гриби — смертельно отруйні першими, з довідника', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: DangerousMushrooms()), extra: [catalogProvider.overrideWith((ref) => catalog)]));
    await tester.pump();
    final deadly = catalog.species.where((s) => s.edibility == 'deadly_poisonous').toList();
    expect(deadly, isNotEmpty);
    expect(find.byKey(ValueKey('danger-${deadly.first.id}')), findsOneWidget);
    expect(find.text('Смертельно отруйний'), findsWidgets);
  });

  testWidgets('Небезпечна погода сьогодні на ділянці — з прогнозу; немає — картки немає', (tester) async {
    final n = DateTime.now();
    final today = '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    AnalysisOverview overview(List<String> hazards) => AnalysisOverview.fromJson({
          'sizes': const [],
          'can_create': false,
          'usage': {'used': 1, 'limit': 5, 'label': ''},
          'hint_label': '',
          'areas': [
            {
              'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'slot': 1,
              'lat': 50.4,
              'lng': 30.5,
              'size_km': 5,
              'size_label': '5×5 км',
              'title': 'Броники',
              'usage': {'used': 1, 'limit': 5, 'label': ''},
              'last_result': {
                'area': {'id': 'a', 'slot': 1, 'lat': 50.4, 'lng': 30.5, 'size_km': 5, 'size_label': '5×5 км'},
                'date': today,
                'forest': {'summary_label': '', 'types': []},
                'top1': null,
                'alternative': null,
                'weather': null,
                'warnings': [],
                'usage': {'used': 1, 'limit': 5, 'label': ''},
                'no_data_reason': null,
                'days': [
                  {
                    'date': today,
                    'day_label': 'Сьогодні',
                    'level': 'low',
                    'level_label': '',
                    'level_short_label': '',
                    'level_color': '#000000',
                    'top1': null,
                    'alternative': null,
                    'warnings': [],
                    'weather': {'icon': 'rain', 'temp_label': '', 'humidity_label': '', 'rain_label': '', 'hazards': hazards},
                  },
                ],
              },
            },
          ],
        });
    await tester.pumpWidget(app(const Scaffold(body: WeatherHazardsCard()),
        extra: [analysisOverviewProvider.overrideWith((ref) => overview(['Гроза 15:00–18:00: не стійте під поодинокими високими деревами']))]));
    await tester.pump();
    expect(find.byKey(const ValueKey('weather-hazards')), findsOneWidget);
    expect(find.textContaining('Броники'), findsOneWidget);
    expect(find.textContaining('Гроза 15:00–18:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // нові перевизначення — новий ProviderScope
    await tester.pumpWidget(app(const Scaffold(body: WeatherHazardsCard()), extra: [analysisOverviewProvider.overrideWith((ref) => overview([]))]));
    await tester.pump();
    expect(find.byKey(const ValueKey('weather-hazards')), findsNothing);
  });
}
