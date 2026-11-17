import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_detail_screen.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/profile/licenses_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'catalog_article_test.dart' show oblasts;
import 'catalog_test.dart' show catalog;
import 'package:flutter_client/features/catalog/oblast_map.dart';

/// Папки фото в репо — у кожній файли `ліцензія*.txt` (по блоку на автора: «Фото:», «Ліцензія:»,
/// «Джерело(а):»).
const photoFolders = [
  'фото Топ-20 грибів (webp)',
  'фото популярні 55 грибів (webp)',
  'Червона книга (webp)',
  'Отруйні та смертельно отруйні (webp)',
  'фото двійників (webp)', // лише CC0 / суспільне надбання (scripts/catalog_sync/fetch_free_photos.py)
];

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => null;
    CatalogPhotoCache.directory = () async => null;
  });

  test('Ліцензії: КОЖЕН автор і КОЖНЕ посилання з усіх файлів ліцензій репо — у довіднику застосунку', () {
    // Папка виду → id: за шляхом першого фото в mushroom_catalog.json.
    final source = jsonDecode(File('../mushroom_catalog.json').readAsStringSync()) as Map<String, dynamic>;
    final folderToId = <String, String>{
      for (final s in (source['species'] as List).cast<Map<String, dynamic>>())
        if ((s['photos'] as List?)?.isNotEmpty ?? false)
          File((s['photos'] as List).first as String).parent.path: s['id'] as String,
    };
    final byId = {for (final s in catalog.species) s.id: s};
    var files = 0, authors = 0, links = 0;
    for (final folder in photoFolders) {
      final root = Directory('../$folder');
      if (!root.existsSync()) continue;
      for (final dir in root.listSync().whereType<Directory>()) {
        final licenseFiles = dir.listSync().whereType<File>().where((f) {
          final n = f.uri.pathSegments.last.toLowerCase();
          return n.contains('ліцензі') || n.contains('license');
        }).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        if (licenseFiles.isEmpty) continue;
        final rel = dir.path.substring(3);
        final id = folderToId[rel];
        expect(id, isNotNull, reason: 'папка $rel — без виду в довіднику');
        final species = byId[id]!;
        final text = licenseFiles.map((f) => f.readAsStringSync()).join('\n\n');
        final fileAuthors = [
          for (final m in RegExp(r'^Фото:\s*(.+?)\.?\s*$', multiLine: true).allMatches(text)) m.group(1)!.trim(),
        ];
        // Посилання на фото — усі URL, крім посилань на текст ліцензії (рядки «Ліцензія:»).
        final fileLinks = [
          for (final line in text.split('\n'))
            if (!line.trim().startsWith('Ліцензія:'))
              for (final m in RegExp(r'https?://\S+').allMatches(line)) m.group(0)!,
        ];
        expect(species.credits.map((c) => c.author).toList(), fileAuthors, reason: rel);
        expect(species.credits.expand((c) => c.sources).toList(), fileLinks, reason: rel);
        final fileLicenses = [
          for (final m in RegExp(r'^Ліцензія:\s*(.+?)\s+—\s+(\S+)\s*$', multiLine: true).allMatches(text)) (m.group(1)!, m.group(2)!),
        ];
        expect([for (final c in species.credits) (c.license!, c.licenseUrl!)], fileLicenses, reason: rel);
        // Лише вільні ліцензії: CC BY 4.0 (з підписом), CC0, суспільне надбання.
        expect(
            species.credits.every((c) => c.license == 'CC BY 4.0' || c.license == 'CC0 1.0' || c.license!.startsWith('Суспільне надбання')),
            isTrue,
            reason: rel);
        files += licenseFiles.length;
        authors += fileAuthors.length;
        links += fileLinks.length;
      }
    }
    // Станом на 2026-11-17: 23 файли CC BY 4.0 (36 авторів, 65 фото) + фото двійників.
    expect(files, greaterThanOrEqualTo(23));
    expect(authors, greaterThanOrEqualTo(36));
    expect(links, greaterThanOrEqualTo(65));
    // У довіднику немає авторів, яких нема у файлах.
    expect(catalog.species.fold<int>(0, (n, s) => n + s.credits.length), authors);
  });

  testWidgets('Сторінка виду: усі три автори фото боровика сатанинського й джерело Червоної книги', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => catalog), oblastsProvider.overrideWith((ref) => oblasts)],
      child: const MaterialApp(home: CatalogDetailScreen(speciesId: 'rubroboletus_satanas')),
    ));
    await tester.pumpAndSettle();
    final credit = find.byKey(const ValueKey('catalog-photo-credit'));
    await tester.scrollUntilVisible(credit, 400, scrollable: find.byType(Scrollable).first);
    expect(find.text('Фото (3 автори)'), findsOneWidget);
    for (final a in ['Алена Ручка', 'Ondřej Křivan', 'Daniel Ghyselinck']) {
      expect(find.textContaining(a), findsOneWidget);
    }
    expect(find.textContaining('inaturalist.org/photos/732691022'), findsOneWidget);
    expect(find.byKey(const ValueKey('red-book-source')), findsOneWidget);
  });

  testWidgets('Профіль → «Джерела та ліцензії»: дані, фото всіх авторів, бібліотеки', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => catalog)],
      child: const MaterialApp(home: LicensesScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Карта, ліси й дороги'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsWidgets);
    final summary = find.byKey(const ValueKey('licenses-photos-summary'));
    await tester.scrollUntilVisible(summary, 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Фото інших авторів (видів — '), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('licenses-species-rubroboletus_satanas')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Ondřej Křivan'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('licenses-packages')), 600,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('licenses-packages')), findsOneWidget);
  });
}
