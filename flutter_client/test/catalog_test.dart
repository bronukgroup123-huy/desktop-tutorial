import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/models/forecast.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_browser.dart';
import 'package:flutter_client/features/catalog/catalog_description.dart';
import 'package:flutter_client/features/catalog/catalog_detail_screen.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/forecast/identify_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

final catalog = Catalog.parse(File('assets/catalog/catalog.json.gz').readAsBytesSync());

Widget app(String initial, {Widget? home}) => ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => catalog)],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: initial, routes: [
          GoRoute(path: '/home', builder: (c, s) => Scaffold(body: home ?? const CatalogBrowser())),
          GoRoute(path: '/catalog/:id', builder: (c, s) => CatalogDetailScreen(speciesId: s.pathParameters['id']!)),
        ]),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => null; // без мережі — стікер замість фото
    CatalogPhotoCache.directory = () async => null;
  });

  test('Вбудований довідник: види з фото, описи з книги', () {
    expect(catalog.species.length, greaterThanOrEqualTo(100));
    expect(catalog.species.every((s) => s.photos.isNotEmpty), isTrue);
    final f = catalog.byId('flammulina_velutipes')!;
    expect(f.name, 'Зимовий опеньок');
    expect(f.latin, 'Flammulina velutipes');
    expect(f.thumb, 'flammulina_velutipes-0-t.webp');
    expect(f.description, contains('🔍 Швидка картка'));
    expect(edibilityBadge(f).label, 'Їстівний');
    expect(edibilityBadge(catalog.byId('amanita_phalloides')!).label, 'Смертельно отруйний');
    // кожен вид, для якого прогноз показує «Як відрізнити», є в довіднику
    for (final id in ['boletus_edulis', 'armillaria_mellea', 'cantharellus_cibarius', 'pleurotus_ostreatus', 'imleria_badia']) {
      expect(catalog.byId(id), isNotNull, reason: id);
    }
  });

  test('Відбір: пошук за назвою й латиною, категорії, дерева', () {
    final all = catalog.species;
    expect(filterCatalog(all, query: 'зимовий').map((s) => s.id), contains('flammulina_velutipes'));
    expect(filterCatalog(all, query: 'FLAMMULINA').single.id, 'flammulina_velutipes');
    expect(filterCatalog(all, category: CatalogCategory.poisonous).every((s) => s.poisonous), isTrue);
    expect(filterCatalog(all, category: CatalogCategory.red).every((s) => s.redListed), isTrue);
    expect(filterCatalog(all, category: CatalogCategory.top20).length, 20);
    expect(filterCatalog(all, trees: {'birch'}).every((s) => s.tree.contains('birch')), isTrue);
    expect(filterCatalog(all, query: 'немає такого гриба'), isEmpty);
  });

  test('Опис: розділи за емодзі-заголовками і підзаголовками Червоної книги; рядки з табуляцією — не заголовки', () {
    final s = descSections('Вступ\n🔍 Швидка картка\nШапка: руда\n⚠️ Двійники\nОзнака\tА\tБ\n🍳 Приготування\nВаріть\nТаксономія\nРодина: X');
    expect(s.map((x) => x.emoji), [null, '🔍', '⚠️', '🍳', null]);
    expect(s[1].title, 'Швидка картка');
    expect(s[2].lines, ['Ознака\tА\tБ']);
    expect(s[4].title, 'Таксономія');
    expect(descHeading('🔍\tтаблиця'), isNull);
  });

  testWidgets('Довідник: пошук → картка виду з фото-заглушкою, значками, сезоном і описом', (tester) async {
    await tester.pumpWidget(app('/home'));
    await tester.pump();
    expect(find.text('Довідник грибів'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('catalog-count'))).data, startsWith('${catalog.species.length} вид'));
    await tester.enterText(find.byKey(const ValueKey('catalog-search')), 'зимовий оп');
    await tester.pump();
    expect(find.text('1 вид'), findsOneWidget);
    // над сіткою — картка «Фото без інтернету»: гриб може бути нижче краю тестового екрана
    await tester.ensureVisible(find.byKey(const ValueKey('catalog-card-flammulina_velutipes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-card-flammulina_velutipes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-detail-flammulina_velutipes')), findsOneWidget);
    expect(find.text('Flammulina velutipes'), findsOneWidget);
    expect(find.text('⭐ Топ-20'), findsOneWidget);
    expect(find.byKey(const ValueKey('species-photo')), findsOneWidget); // фото дорослого гриба праворуч
    expect(find.byKey(const ValueKey('catalog-season')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('catalog-description')), 200,
        scrollable: find.descendant(of: find.byKey(const ValueKey('catalog-detail-flammulina_velutipes')), matching: find.byType(Scrollable)).first);
    expect(find.byKey(const ValueKey('catalog-description')), findsOneWidget);
    expect(find.text('Швидка картка (як визначити)'), findsOneWidget);
    // двійники — поруч картками (замість таблиці)
    await tester.scrollUntilVisible(find.byKey(const ValueKey('article-twins')), 300,
        scrollable: find.descendant(of: find.byKey(const ValueKey('catalog-detail-flammulina_velutipes')), matching: find.byType(Scrollable)).first);
    expect(find.text('Галерина облямована'), findsWidgets);
  });

  testWidgets('Фільтр «Дерево»: вибір береза зменшує список', (tester) async {
    await tester.pumpWidget(app('/home'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('catalog-facet-tree')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-opt-birch')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('catalog-opt-apply')));
    await tester.pumpAndSettle();
    final n = filterCatalog(catalog.species, trees: {'birch'}).length;
    expect(find.text('Дерево · 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-count')), findsOneWidget);
    expect((tester.widget<Text>(find.byKey(const ValueKey('catalog-count')))).data, startsWith('$n '));
  });

  testWidgets('Отруйний гриб — без сезону плодоношення', (tester) async {
    final p = catalog.species.firstWhere((s) => s.poisonous && s.months.isNotEmpty);
    await tester.pumpWidget(app('/catalog/${p.id}'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('catalog-detail-${p.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-season')), findsNothing);
    expect(find.byKey(const ValueKey('catalog-in-season')), findsNothing);
  });

  testWidgets('Невідомий вид — повідомлення, без падіння', (tester) async {
    await tester.pumpWidget(app('/catalog/no_such'));
    await tester.pumpAndSettle();
    expect(find.text('Цього гриба ще немає в довіднику'), findsOneWidget);
  });

  testWidgets('«Як відрізнити» → «Переглянути в довіднику» відкриває цей самий гриб', (tester) async {
    final species = ForecastSpecies.fromJson({
      'mushroom_type': 'flammulina_velutipes',
      'name_ua': 'Зимовий опеньок',
      'level': 'high',
      'level_label': 'Висока ймовірність',
      'level_color': '#16a34a',
      'when_label': 'Зараз',
      'where_label': 'На пнях',
    });
    const card = IdentifyCard(features: [], capColors: []);
    await tester.pumpWidget(app('/home', home: IdentifyView(card: card, species: species)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('identify-catalog')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-detail-flammulina_velutipes')), findsOneWidget);
  });
}
