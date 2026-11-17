import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_article.dart';
import 'package:flutter_client/features/catalog/catalog_browser.dart';
import 'package:flutter_client/features/catalog/catalog_description.dart';
import 'package:flutter_client/features/catalog/catalog_forecast_link.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/catalog/oblast_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'catalog_test.dart' show catalog;
import 'data/analysis_test.dart' show resultJson;
import 'forecast_test.dart' show areaJson, overview;

/// Ділянка з результатом, де найкращий гриб — білий (data/analysis_test.dart).
Map<String, dynamic> areaWithEdulis() => {...areaJson(withResult: true), 'last_result': resultJson()};

final oblasts = parseOblasts(File('assets/catalog/ukraine_oblasts.json').readAsStringSync());

String norm(String s) => s
    .replaceAll('**', '')
    .replaceAll(RegExp(r'^\s*[✅❌]\s*'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Фрагменти книжкового тексту, які мають бути на екрані дослівно (згорнуті кулінарні розділи
/// перевіряються окремо — їхній вміст будується лише після розгортання).
List<String> expectedFragments(CatalogSpecies sp) {
  final out = <String>[];
  for (final s in descSections(sp.description)) {
    final kind = articleKind(s);
    if (kind == ArticleKind.culinary || kind == ArticleKind.recipes) continue;
    if (s.emoji != '🍄' && s.title != null) out.add(s.title!);
    var firstTableRow = true;
    for (final raw in s.lines) {
      final t = raw.trim();
      if (t.isEmpty || t == sp.name.trim()) continue;
      if (raw.contains('\t')) {
        final cells = raw.split(RegExp(r'\t+')).map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
        // Шапка таблиці «Параметр | Опис…» / «Питання | Відповідь» — плитки й картки її замінюють.
        final skipHeader = firstTableRow && (kind == ArticleKind.where || kind == ArticleKind.memo) && DescTable.hasHeader([cells, cells]);
        firstTableRow = false;
        if (skipHeader) continue;
        for (final c in cells) {
          // «🌲 Де росте?» у плитці — емодзі окремо від ключа.
          out.add(kind == ArticleKind.where ? c.replaceFirst(RegExp(r'^[^\p{L}\p{N}\s]+\s*', unicode: true), '') : c);
        }
        continue;
      }
      final line = t.replaceFirst(descBullet, '');
      final kv = descKv.firstMatch(line);
      if (kv != null) {
        out
          ..add(kv.group(1)!)
          ..add(kv.group(2)!);
      } else {
        out.add(line);
      }
    }
  }
  return [for (final f in out) norm(f)]..removeWhere((f) => f.isEmpty);
}

Widget host(Widget child) => ProviderScope(
      overrides: [
        catalogProvider.overrideWith((ref) => catalog),
        oblastsProvider.overrideWith((ref) => oblasts),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

String screenText(WidgetTester tester) => norm([
      for (final w in tester.allWidgets)
        if (w is RichText) w.text.toPlainText(includePlaceholders: false),
    ].join(' \n '));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => null;
    CatalogPhotoCache.directory = () async => null;
  });

  test('Ролі розділів: статус, небезпека, двійники, паспорт, Червона книга', () {
    DescSection s(String? e, String t) => DescSection(emoji: e, title: t);
    expect(articleKind(s('✅', 'Статус: Їстівний')), ArticleKind.status);
    expect(articleKind(s('⚠️', 'Обережно, двійники!')), ArticleKind.twins);
    expect(articleKind(s('⚠️', 'Смертельно небезпечний двійник — галерина!')), ArticleKind.danger);
    expect(articleKind(s('⚠️', 'З ким можна сплутати')), ArticleKind.confusions);
    expect(articleKind(s('🔍', 'Швидка картка (як визначити)')), ArticleKind.passport);
    expect(articleKind(s(null, 'Чи може ви зламати закон?')), ArticleKind.law);
    expect(articleKind(s(null, 'Чим цікавий?')), ArticleKind.fact);
    expect(articleKind(s('💡', 'Цікавий факт')), ArticleKind.fact);
  });

  test('«Головне»: статус, небезпека, закон, ключова ознака — з тексту книги', () {
    final f = buildArticle(catalog.byId('flammulina_velutipes')!).summary;
    expect(f.status, startsWith('Статус: Їстівний'));
    expect(f.dangers.single.title, startsWith('Смертельно небезпечний двійник'));
    final red = buildArticle(catalog.byId('boletus_aereus')!).summary;
    expect(red.status, 'Природоохоронний статус: Вразливий');
    expect(red.law, isNotNull);
    final poison = buildArticle(catalog.byId('inocybe_geophylla')!).summary;
    expect(poison.status, startsWith('Бейдж:'));
    expect(poison.facts.any((x) => x.startsWith('Симптоми:')), isTrue);
    expect(poison.keyFeature, startsWith('Ключова ознака:'));
  });

  test('Паспорт: схема потрібної частини гриба', () {
    expect(passportGlyph('Шапка').part, 'cap');
    expect(passportGlyph('Капелюх').part, 'cap');
    expect(passportGlyph('Низ шапки (Трубочки)'), (part: 'underside', kind: 'tubes', icon: null));
    expect(passportGlyph('Пластинки').kind, 'gills');
    expect(passportGlyph('Ніжка').part, 'stem');
    expect(passportGlyph("М'якоть").part, 'flesh');
    expect(passportGlyph('Споровий порошок').icon, Icons.grain_rounded);
  });

  test('Рецепти кроками: нічого з тексту не губиться', () {
    for (final sp in catalog.species) {
      for (final s in descSections(sp.description).where((s) => articleKind(s) == ArticleKind.recipes)) {
        final parsed = parseRecipeSection(s.lines);
        final recipes = parsed.recipes;
        if (recipes.isEmpty) continue;
        final shown = {
          ...parsed.preface,
          for (final r in recipes) ...[r.title, r.ingredientsLabel, r.stepsLabel, ...r.intro, ...r.ingredients, ...r.steps, ...r.notes],
        };
        for (final l in s.lines.map((l) => l.trim()).where((l) => l.isNotEmpty)) {
          final bare = l.replaceFirst(descBullet, '');
          final title = RegExp(r'^\d+\.\s+(.+)$').firstMatch(l)?.group(1);
          expect(shown.contains(bare) || shown.contains(title), isTrue, reason: '${sp.id}: «$l»');
        }
      }
    }
    final edulis = parseRecipes(descSections(catalog.byId('boletus_edulis')!.description)
        .firstWhere((s) => articleKind(s) == ArticleKind.recipes)
        .lines);
    expect(edulis.length, 3);
    expect(edulis.first.ingredients.length, 4);
    expect(edulis.first.steps.length, 6);
  });

  testWidgets('Текст книги — дослівно на екрані для кожного виду (змінюється лише подача)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    for (final sp in catalog.species) {
      await tester.pumpWidget(host(CatalogArticle(key: ValueKey(sp.id), species: sp)));
      await tester.pump();
      final text = screenText(tester);
      for (final f in expectedFragments(sp)) {
        expect(text.contains(f), isTrue, reason: '${sp.id}: немає «$f»');
      }
    }
  });

  testWidgets('Зимовий опеньок: «Головне», паспорт зі схемами, двійники поруч, плитки, карта, порада маскота', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(CatalogArticle(species: catalog.byId('flammulina_velutipes')!)));
    await tester.pump();
    expect(find.byKey(const ValueKey('article-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('article-danger-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('passport-Шапка')), findsOneWidget);
    expect(find.byKey(const ValueKey('glyph-cap')), findsOneWidget);
    expect(find.byKey(const ValueKey('article-twins')), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsWidgets); // ❌ — значком
    expect(find.byKey(const ValueKey('oblast-map')), findsOneWidget);
    expect(find.textContaining('Поширений: '), findsOneWidget);
    // Кулінарія згорнута; рецепти — кроками з підсвіченим часом
    final acc = find.byKey(const ValueKey('desc-acc-Рецепти'));
    if (acc.evaluate().isNotEmpty) {
      await tester.tap(acc);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('article-recipes')), findsOneWidget);
    }
  });

  testWidgets('Двійник із довідника — дотик веде на його сторінку', (tester) async {
    // У білого гриба двійник «Гірчак» — шукаємо будь-який вид, чий двійник є в довіднику.
    CatalogSpecies? withLink;
    String? twinId;
    for (final sp in catalog.species) {
      final s = descSections(sp.description).where((s) => articleKind(s) == ArticleKind.twins).firstOrNull;
      final head = s?.lines.firstWhere((l) => l.contains('\t'), orElse: () => '');
      final cells = head == null || head.isEmpty ? <String>[] : head.split(RegExp(r'\t+'));
      final twin = cells.length == 3 ? findByName(catalog, cells[2].trim()) : null;
      if (twin != null) {
        withLink = sp;
        twinId = twin.id;
        break;
      }
    }
    expect(withLink, isNotNull);
    await tester.pumpWidget(host(CatalogArticle(species: withLink!)));
    await tester.pump();
    expect(find.byKey(ValueKey('twin-link-$twinId')), findsOneWidget);
  });

  test('Рецепти кроками — у всіх видів з нумерованими рецептами (і зі вступом перед ними)', () {
    var sections = 0;
    for (final sp in catalog.species) {
      for (final s in descSections(sp.description).where((s) => articleKind(s) == ArticleKind.recipes)) {
        final numbered = s.lines.any((l) => RegExp(r'^\d+\.\s').hasMatch(l.trim()));
        if (!numbered) continue;
        sections++;
        final r = parseRecipeSection(s.lines);
        expect(r.recipes, isNotEmpty, reason: sp.id);
        expect(r.recipes.every((x) => x.steps.isNotEmpty), isTrue, reason: sp.id);
      }
    }
    expect(sections, greaterThanOrEqualTo(60));
    final rufescens = parseRecipeSection(descSections(catalog.byId('hydnum_rufescens')!.description)
        .firstWhere((s) => articleKind(s) == ArticleKind.recipes)
        .lines);
    expect(rufescens.preface, ['Знайдено перевірені рецепти для цього виду.']);
    expect(rufescens.recipes, isNotEmpty);
  });

  test('Сезон — за місяцями: «Весна» без зимового опенька; отруйні — без сезону', () {
    expect(catalog.byId('flammulina_velutipes')!.seasons, ['autumn', 'winter']);
    final spring = filterCatalog(catalog.species, seasons: {'spring'});
    expect(spring.map((s) => s.id), isNot(contains('flammulina_velutipes')));
    expect(spring.every((s) => s.months.isEmpty || s.months.any([3, 4, 5].contains)), isTrue);
    for (final p in catalog.species.where((s) => s.poisonous)) {
      expect(p.seasons, isEmpty, reason: p.id);
      expect(p.inSeason(DateTime.now().month), isFalse, reason: p.id);
    }
    expect(filterCatalog(catalog.species, seasons: {'summer', 'autumn'}).any((s) => s.poisonous), isFalse);
  });

  test('Двійник у довіднику: народні назви, скорочена латина, синоніми', () {
    expect(findByName(catalog, 'Сатанинський гриб (Боровик чортів)')?.id, 'rubroboletus_satanas');
    expect(findByName(catalog, 'Сироїжка їстівна (R. vesca)')?.id, 'russula_vesca');
    expect(findByName(catalog, 'Скрипиця (L. vellereus)')?.id, 'lactarius_vellereus');
    expect(findByName(catalog, 'Небезпечний двійник (Inocybe patouillardii / Entoloma lividum)')?.id, 'inocybe_erubescens');
    expect(findByName(catalog, 'Галерина облямована')?.id, 'galerina_marginata');
    // Фото двійників CC0 / суспільне надбання (рішення PO 2026-11-17): тепер у довіднику.
    expect(findByName(catalog, 'Гірчак (жовчний гриб)')?.id, 'tylopilus_felleus');
    expect(findByName(catalog, 'Хрящ-молочник пухнастий')?.id, 'lactarius_pubescens');
    expect(findByName(catalog, 'Гіродон сизуватий')?.id, 'gyrodon_lividus');
  });

  test('Кожна картка-перевертень: двійник знайдений з фото — або його справді немає в довіднику', () {
    const notInCatalog = {'Неїстівний / перестиглий'}; // не вид — «перестиглий дощовик»
    for (final sp in catalog.species) {
      final s = descSections(sp.description).where((s) => articleKind(s) == ArticleKind.twins).firstOrNull;
      final head = s?.lines.firstWhere((l) => l.contains('\t'), orElse: () => '');
      if (head == null || head.isEmpty) continue;
      final cells = head.split(RegExp(r'\t+')).map((c) => c.trim()).toList();
      if (cells.length != 3) continue;
      final twin = findByName(catalog, cells[2]);
      expect(twin != null || notInCatalog.contains(cells[2]), isTrue, reason: '${sp.id}: «${cells[2]}»');
      if (twin != null) expect(twin.photos, isNotEmpty, reason: twin.id);
    }
  });

  testWidgets('Двійника немає в довіднику — зворот із назвою і відмінностями, без порожньої заглушки', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // У дощовика двійник — «Неїстівний / перестиглий» (не вид довідника).
    await tester.pumpWidget(host(CatalogArticle(species: catalog.byId('lycoperdon_perlatum')!)));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('flip-card'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flip-no-photo')), findsOneWidget);
    expect(find.text('Фото поки немає'), findsOneWidget);
  });

  test('«Зараз сезон»: відбір за місяцем', () {
    final nov = filterCatalog(catalog.species, inSeasonMonth: 11);
    expect(nov.map((s) => s.id), contains('flammulina_velutipes'));
    expect(nov.every((s) => s.months.contains(11)), isTrue);
    expect(nov.length, lessThan(catalog.species.length));
  });

  test('Карта областей: 25 областей, Крим у складі України; зони видів — відомі коди', () {
    expect(oblasts.length, 25);
    expect(oblasts.keys, contains('krym'));
    for (final sp in catalog.species) {
      for (final z in sp.zones) {
        expect(oblasts.containsKey(z), isTrue, reason: '${sp.id}: $z');
      }
    }
  });

  test('«У ваших ділянках»: рівень виду сьогодні з результату ділянки', () {
    final hits = speciesInAreas(overview(areas: [areaWithEdulis()]), 'boletus_edulis');
    expect(hits, isNotEmpty);
    expect(hits.first.levelLabel, isNotEmpty);
    expect(speciesInAreas(overview(areas: [areaWithEdulis()]), 'amanita_phalloides'), isEmpty);
  });

  testWidgets('«У ваших ділянках» — картка на сторінці виду', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [analysisOverviewProvider.overrideWith((ref) => overview(areas: [areaWithEdulis()]))],
      child: const MaterialApp(home: Scaffold(body: CatalogForecastLink(speciesId: 'boletus_edulis'))),
    ));
    await tester.pump();
    expect(find.text('У ваших ділянках сьогодні'), findsOneWidget);
  });
}
