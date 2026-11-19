import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_article.dart';
import 'package:flutter_client/features/catalog/catalog_detail_screen.dart';
import 'package:flutter_client/features/catalog/catalog_motion.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart' show SpeciesIcon;
import 'package:flutter_client/features/catalog/mushroom_character.dart';
import 'package:flutter_client/features/catalog/oblast_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'catalog_article_test.dart' show oblasts;
import 'catalog_test.dart' show catalog;

Widget host(Widget child, {bool reduce = false}) => ProviderScope(
      overrides: [
        catalogProvider.overrideWith((ref) => catalog),
        oblastsProvider.overrideWith((ref) => oblasts),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduce),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => null;
    CatalogPhotoCache.directory = () async => null;
  });

  test('Фото дорослого гриба є для кожного виду Топ-20 (assets/species/large)', () {
    final top = {for (final s in catalog.species.where((s) => s.top20)) s.id};
    expect(kSpeciesLargePhotos, top);
    for (final id in top) {
      expect(File('assets/species/large/$id.webp').existsSync(), isTrue, reason: id);
    }
  });

  testWidgets('Картка Топ-20 — без анімації: ні віконця з грибом-персонажем, ні кола сценок; праворуч фото', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        catalogProvider.overrideWith((ref) => catalog),
        oblastsProvider.overrideWith((ref) => oblasts),
      ],
      child: const MaterialApp(home: CatalogDetailScreen(speciesId: 'flammulina_velutipes')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-slot')), findsNothing);
    expect(find.byKey(const ValueKey('icon-play')), findsNothing);
    expect(find.byType(SpeciesIcon), findsWidgets);
    expect(find.byKey(const ValueKey('species-photo')), findsOneWidget);
  });

  testWidgets('Вид поза Топ-20 — без фото праворуч', (tester) async {
    final other = catalog.species.firstWhere((s) => !s.top20);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        catalogProvider.overrideWith((ref) => catalog),
        oblastsProvider.overrideWith((ref) => oblasts),
      ],
      child: MaterialApp(home: CatalogDetailScreen(speciesId: other.id)),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('species-photo')), findsNothing);
  });

  test('Персонажі: рівно 20 видів Топ-20', () {
    expect(kCharacterLooks.keys.toSet(), {for (final s in catalog.species.where((s) => s.top20)) s.id});
  });

  testWidgets('Кожен персонаж малюється з будь-якими емоціями й руками', (tester) async {
    for (final look in kCharacterLooks.values) {
      for (final eyes in Eyes.values) {
        await tester.pumpWidget(MaterialApp(
          home: Row(children: [
            for (final mouth in Mouth.values)
              MushroomCharacter(look: look, face: Face(eyes: eyes, mouth: mouth, blush: true, brows: 1), left: Arm.up, right: const Arm(1.2, 1.5), size: 40),
          ]),
        ));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Перевертень: дотик — двійник, ще дотик — наш гриб', (tester) async {
    await tester.pumpWidget(host(SingleChildScrollView(child: CatalogArticle(species: catalog.byId('flammulina_velutipes')!))));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('flip-card'));
    await tester.ensureVisible(card);
    expect(find.byKey(const ValueKey('flip-front')), findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flip-back')), findsOneWidget);
    expect(find.text('Галерина облямована'), findsWidgets);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flip-front')), findsOneWidget);
  });

  testWidgets('Грибниця між розділами проростає; без анімацій у системі — одразу', (tester) async {
    await tester.pumpWidget(host(SingleChildScrollView(child: CatalogArticle(species: catalog.byId('boletus_edulis')!)), reduce: true));
    await tester.pump();
    expect(find.byType(MyceliumDivider), findsWidgets);
    final painter = tester.widgetList<CustomPaint>(find.descendant(of: find.byType(MyceliumDivider).first, matching: find.byType(CustomPaint)))
        .map((w) => w.painter)
        .whereType<MyceliumPainter>()
        .first;
    expect(painter.progress, 1);
  });

  test('seg: частка проміжку', () {
    expect(seg(0.5, 0, 1), 0.5);
    expect(seg(-1, 0, 1), 0);
    expect(seg(2, 0, 1), 1);
  });
}
