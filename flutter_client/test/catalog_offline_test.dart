import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_offline.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'catalog_photo_test.dart' show tar;

CatalogSpecies sp(String id, int photos) => CatalogSpecies(
      id: id, name: id, latin: '', edibility: 'edible', redListed: false, top20: false, popular: false,
      months: const [], peakMonths: const [], tree: const [], season: const [],
      photos: [for (var i = 0; i < photos; i++) '$id-$i.webp'], description: '',
    );

final small = Catalog([sp('a', 2), sp('b', 1), sp('c', 3)]);

/// Реліз: архіви видів, мініатюри й manifest.json; `fail` — ці архіви «без мережі».
Future<Uint8List?> Function(String) release({Set<String> fail = const {}, List<String>? log}) => (url) async {
      final name = url.split('/').last;
      log?.add(name);
      if (fail.contains(name)) return null;
      if (name == 'manifest.json') {
        return utf8.encode(jsonEncode({'total': 3000000, 'bundles': {'thumbs.tar': 300000, 'a.tar': 1000000, 'b.tar': 500000, 'c.tar': 1200000}}));
      }
      if (name == 'thumbs.tar') return tar({for (final s in small.species) '${s.id}-0-t.webp': [1]});
      final id = name.replaceAll('.tar', '');
      final s = small.byId(id)!;
      return tar({for (final p in s.photos) p: [2, 3]});
    };

/// Дочекатися стану у віджет-тесті зі справжнім вводом-виводом (файли): кожен крок ланцюжка
/// `await` продовжується лише на pump, тож чергуємо runAsync і pump, доки умова не справдиться
/// (на повільній машині CI кроків потрібно більше — тому за умовою, а не фіксовано).
Future<void> settleUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 2000 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

void main() {
  late Directory dir;
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('catalog_offline');
    CatalogPhotoCache.clear();
    CatalogPhotoCache.directory = () async => dir;
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [catalogProvider.overrideWith((ref) => small)]);
    addTearDown(c.dispose);
    return c;
  }

  test('Яких архівів бракує: мініатюри і види без усіх фото', () {
    expect(CatalogOfflineController.missingBundles(small, {}), ['thumbs.tar', 'a.tar', 'b.tar', 'c.tar']);
    expect(
      CatalogOfflineController.missingBundles(small, {'a-0-t.webp', 'b-0-t.webp', 'c-0-t.webp', 'a-0.webp', 'a-1.webp', 'b-0.webp', 'c-0.webp'}),
      ['c.tar'],
    );
  });

  test('«Завантажити»: усі фото на телефоні, точний розмір з manifest.json; далі — без мережі', () async {
    CatalogPhotoCache.fetcher = release();
    final c = container();
    final ctrl = c.read(catalogOfflineProvider.notifier);
    await ctrl.refresh();
    var s = c.read(catalogOfflineProvider);
    expect(s.saved, 0);
    expect(s.bytesExact, isTrue);
    expect(s.bytesPlanned, 3000000);
    await ctrl.start();
    s = c.read(catalogOfflineProvider);
    expect(s.complete, isTrue);
    expect(s.saved, 3);
    expect(s.done, 4);
    expect(s.bytesDone, 3000000);
    expect(File('${dir.path}/c-2.webp').existsSync(), isTrue);
    // у лісі: мережі немає, а фото виду, який ще не відкривали, є
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => fail('мережа не потрібна');
    expect(await CatalogPhotoCache.get('b-0.webp'), [2, 3]);
  });

  test('Обрив мережі — помилка; «Продовжити» докачує лише решту', () async {
    final log = <String>[];
    CatalogPhotoCache.fetcher = release(fail: {'c.tar'}, log: log);
    final c = container();
    final ctrl = c.read(catalogOfflineProvider.notifier);
    await ctrl.start();
    var s = c.read(catalogOfflineProvider);
    expect(s.complete, isFalse);
    expect(s.error, isNotNull);
    log.clear();
    CatalogPhotoCache.fetcher = release(log: log);
    await ctrl.start();
    s = c.read(catalogOfflineProvider);
    expect(s.complete, isTrue);
    expect(s.error, isNull);
    expect(log.where((n) => n.endsWith('.tar')), ['c.tar']);
  });

  test('«Видалити» — місце звільнено, стан скинуто', () async {
    CatalogPhotoCache.fetcher = release();
    final c = container();
    final ctrl = c.read(catalogOfflineProvider.notifier);
    await ctrl.start();
    expect(c.read(catalogOfflineProvider).savedBytes, greaterThan(0));
    await ctrl.deleteAll();
    final s = c.read(catalogOfflineProvider);
    expect(s.saved, 0);
    expect(s.savedBytes, 0);
    expect(dir.existsSync(), isFalse);
  });

  testWidgets('Картка: розмір → «Завантажити» → «Усі фото збережено» → «Видалити»', (tester) async {
    CatalogPhotoCache.fetcher = release();
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => small)],
      child: const MaterialApp(home: Scaffold(body: CatalogOfflineCard())),
    ));
    await settleUntil(tester, find.textContaining('2.9 МБ'));
    expect(find.text('Фото без інтернету'), findsOneWidget);
    expect(find.textContaining('2.9 МБ'), findsOneWidget); // 3 000 000 байт
    await tester.tap(find.byKey(const ValueKey('offline-download')));
    await settleUntil(tester, find.byKey(const ValueKey('offline-complete')));
    expect(find.byKey(const ValueKey('offline-complete')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('offline-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offline-delete-confirm')));
    await settleUntil(tester, find.text('Фото без інтернету'));
    expect(find.text('Фото без інтернету'), findsOneWidget);
  });
}
