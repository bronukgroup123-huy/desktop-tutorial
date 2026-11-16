import 'package:flutter/material.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_article.dart';
import 'package:flutter_client/features/catalog/catalog_detail_screen.dart';
import 'package:flutter_client/features/catalog/catalog_motion.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/catalog/mushroom_scenes.dart';
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

  test('Сценки: кожна поза — скінченні числа на всьому проміжку; 6 різних історій', () {
    expect(kMushroomScenes.map((s) => s.id).toSet().length, 6);
    for (final s in kMushroomScenes) {
      expect(s.duration.inMilliseconds, greaterThanOrEqualTo(5000), reason: '${s.id}: історія, а не один рух');
      for (var i = 0; i <= 200; i++) {
        final p = s.pose(i / 200);
        for (final v in [p.dx, p.dy, p.rot, p.sx, p.sy, p.opacity]) {
          expect(v.isFinite, isTrue, reason: '${s.id} t=${i / 200}');
        }
      }
      // Наприкінці гриб повертається на місце (сцена можна повторити).
      final end = s.pose(1);
      expect(end.opacity, closeTo(1, 0.01), reason: s.id);
      expect(end.rot.abs(), lessThan(0.05), reason: s.id);
    }
  });

  testWidgets('Сценки програються до кінця без помилок', (tester) async {
    for (final s in kMushroomScenes) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: MushroomStage(key: ValueKey(s.id), speciesId: 'boletus_edulis', scene: s)))));
      for (var i = 0; i < 25; i++) {
        await tester.pump(s.duration ~/ 24);
      }
      expect(tester.takeException(), isNull, reason: s.id);
    }
  });

  testWidgets('Довге натискання на значок → коло сценок → «Сон» грає на сцені, «Ще раз», «Закрити»', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        catalogProvider.overrideWith((ref) => catalog),
        oblastsProvider.overrideWith((ref) => oblasts),
      ],
      child: const MaterialApp(home: CatalogDetailScreen(speciesId: 'flammulina_velutipes')),
    ));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('icon-play')));
    await tester.pumpAndSettle();
    for (final s in kMushroomScenes) {
      expect(find.byKey(ValueKey('radial-${s.id}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('radial-sleep')));
    await tester.pumpAndSettle();
    expect(find.byType(MushroomStage), findsOneWidget);
    expect(find.text('😴 Сон'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scene-replay')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-close')));
    await tester.pumpAndSettle();
    expect(find.byType(MushroomStage), findsNothing);
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
