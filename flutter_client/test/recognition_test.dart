import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_detail_screen.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/catalog/oblast_map.dart';
import 'package:flutter_client/features/recognize/ai_model.dart';
import 'package:flutter_client/features/recognize/capture_screen.dart';
import 'package:flutter_client/features/recognize/recognition_flow.dart';
import 'package:flutter_client/features/recognize/recognition_history.dart';
import 'package:flutter_client/features/recognize/recognize_screen.dart';
import 'package:flutter_client/features/recognize/recognizer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'catalog_article_test.dart' show oblasts;
import 'catalog_test.dart' show catalog;
import 'support/test_fonts.dart';

/// Справжнє фото-заглушка (PNG), щоб працювали підготовка й мініатюра.
Uint8List photo({int w = 320, int h = 240, int r = 200, int g = 120, int b = 40}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodePng(im));
}

const dim = 4;

/// Класи: білий гриб, бліда поганка (отруйна), лисичка, два «не гриб». Відбитки — одиничні вектори.
final labels = [
  const RecognitionLabel(id: 'boletus_edulis', latin: 'Boletus edulis', name: 'Білий гриб', edibility: 'edible', hasPhoto: true),
  const RecognitionLabel(id: 'amanita_phalloides', latin: 'Amanita phalloides', name: 'Бліда поганка', edibility: 'deadly_poisonous', hasPhoto: true),
  const RecognitionLabel(id: 'cantharellus_cibarius', latin: 'Cantharellus cibarius', name: 'Лисичка справжня', edibility: 'edible', hasPhoto: true),
  const RecognitionLabel(id: 'not_mushroom', latin: '', name: 'Не гриб', edibility: ''),
];
final text = Float32List.fromList([
  1, 0, 0, 0, // білий
  0, 1, 0, 0, // поганка
  0, 0, 1, 0, // лисичка
  0, 0, 0, 1, // не гриб
]);

class FakeEmbedder implements ImageEmbedder {
  FakeEmbedder(this.vector);

  final List<double> vector;
  int calls = 0;

  @override
  Future<Float32List> embed(Float32List input, int size) async {
    calls++;
    return Float32List.fromList(vector);
  }

  @override
  void dispose() {}
}

AiRecognizer recognizer(List<double> vector) => AiRecognizer(
      manifest: const AiModelManifest(version: 't', files: [], imageSize: 16, mean: [0.5, 0.5, 0.5], std: [0.5, 0.5, 0.5], species: 3),
      labels: labels,
      text: text,
      embedder: FakeEmbedder(vector),
    );

class FakeCamera implements CaptureCamera {
  int taken = 0;
  bool disposed = false;

  @override
  Future<void> init() async {}

  @override
  Widget preview() => Container(color: Colors.brown);

  @override
  Future<Uint8List> take() async {
    taken++;
    return photo(r: 10 * taken);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late Directory dir;
  setUpAll(useBundledTestFonts);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('recognitions');
    RecognitionHistory.directory = () async => dir;
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => null;
    CatalogPhotoCache.directory = () async => null;
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('Відбитки float16 → float32', () {
    final b = Uint16List.fromList([0x3C00, 0xC000, 0x3555, 0x0000]).buffer.asUint8List();
    final f = decodeF16(b);
    expect(f[0], 1.0);
    expect(f[1], -2.0);
    expect(f[2], closeTo(0.3333, 1e-3));
    expect(f[3], 0.0);
  });

  test('Підготовка фото: квадрат size×size, NCHW, нормалізація як у моделі', () {
    final x = preprocessImage(photo(w: 300, h: 200, r: 255, g: 0, b: 0), 16, [0.5, 0.5, 0.5], [0.25, 0.25, 0.25]);
    expect(x.length, 3 * 16 * 16);
    expect(x[0], closeTo((1 - 0.5) / 0.25, 1e-3)); // червоний
    expect(x[16 * 16], closeTo((0 - 0.5) / 0.25, 1e-3)); // зелений
  });

  test('Кандидати рівнями без відсотків; отруйний серед схожих — тривога; «не гриб»', () {
    // Найближче до білого, трохи схоже на поганку.
    final r = rankSpecies([Float32List.fromList([0.9, 0.42, 0.1, 0.0])], text, labels);
    expect(r.notMushroom, isFalse);
    expect(r.candidates.first.label.id, 'boletus_edulis');
    expect(r.candidates.first.likelihood, Likelihood.likely);
    expect(r.candidates.map((c) => c.label.id), contains('amanita_phalloides'));
    expect(r.dangerous?.id, 'amanita_phalloides');
    expect(r.candidates.every((c) => !c.label.notMushroom), isTrue);
    // Кілька кадрів — середній вектор.
    final two = rankSpecies([Float32List.fromList([0, 0, 1, 0]), Float32List.fromList([0.2, 0, 0.9, 0])], text, labels);
    expect(two.candidates.first.label.id, 'cantharellus_cibarius');
    final leaf = rankSpecies([Float32List.fromList([0.05, 0, 0.05, 1])], text, labels);
    expect(leaf.notMushroom, isTrue);
    expect(leaf.dangerous, isNull);
  });

  testWidgets('Знімок у 3 кроки: шапка → ніжка → зріз, галочки, повертає 3 кадри', (tester) async {
    final cam = FakeCamera();
    List<Uint8List>? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => got = await showCapture(context, camera: () => cam),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Крок 1 з 3 · Шапка'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('capture-shutter')));
    await tester.pumpAndSettle();
    expect(find.text('Крок 2 з 3 · Ніжка'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-skip')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('capture-shutter')));
    await tester.pumpAndSettle();
    expect(find.text('Крок 3 з 3 · Зріз'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('capture-shutter')));
    await tester.pumpAndSettle();
    expect(got, hasLength(3));
    expect(cam.disposed, isTrue);
  });

  testWidgets('Зріз можна пропустити — повертає зняте', (tester) async {
    List<Uint8List>? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(onPressed: () async => got = await showCapture(context, camera: FakeCamera.new), child: const Text('go')),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capture-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capture-skip')));
    await tester.pumpAndSettle();
    expect(got, hasLength(1));
  });

  Widget flow(AiRecognizer r, List<Uint8List> photos) => ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) => catalog),
          recognizerProvider.overrideWith((ref) => r),
        ],
        child: MaterialApp(home: RecognitionFlowScreen(photos: photos)),
      );

  Future<void> settleFlow(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 400 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('«ШІ думає» → результат: червона плашка, кандидати рівнями, «Відкрити в довіднику»; записано в історію', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final r = recognizer([0.9, 0.42, 0.1, 0]);
    await tester.pumpWidget(flow(r, [photo(), photo(), photo()]));
    await tester.pump();
    expect(find.byKey(const ValueKey('flow-thinking')), findsOneWidget);
    expect(find.text('ШІ розглядає гриб…'), findsOneWidget);
    await settleFlow(tester, find.byKey(const ValueKey('result-danger')));
    expect(find.byKey(const ValueKey('result-danger')), findsOneWidget);
    expect(find.textContaining('Серед схожих є отруйний гриб'), findsOneWidget);
    expect(find.text('Найімовірніше'), findsOneWidget);
    expect(find.text('Білий гриб'), findsOneWidget);
    expect(find.byKey(const ValueKey('candidate-open-boletus_edulis')), findsOneWidget);
    expect(find.byKey(const ValueKey('candidate-twins-boletus_edulis')), findsOneWidget);
    expect(find.textContaining('%'), findsNothing); // жодних відсотків
    expect((r.embedder as FakeEmbedder).calls, 3);
    final history = await tester.runAsync(RecognitionHistory.load);
    expect(history, hasLength(1));
    expect(history!.first.recognition.candidates.first.label.id, 'boletus_edulis');
  });

  testWidgets('«Не гриб» — персонаж розводить руками і «Перезняти»', (tester) async {
    await tester.pumpWidget(flow(recognizer([0, 0, 0, 1]), [photo()]));
    await settleFlow(tester, find.byKey(const ValueKey('result-not-mushroom')));
    expect(find.text('Хм… Це не схоже на гриб'), findsOneWidget);
    expect(find.byKey(const ValueKey('result-retake')), findsOneWidget);
  });

  testWidgets('Модель не відкрилась (пам\'ять тощо) — пропозиція знайти в довіднику', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => catalog), recognizerProvider.overrideWith((ref) => null)],
      child: MaterialApp(home: RecognitionFlowScreen(photos: [photo()])),
    ));
    await settleFlow(tester, find.byKey(const ValueKey('flow-error')));
    expect(find.textContaining('знайдіть гриб у довіднику'), findsOneWidget);
  });

  testWidgets('Історія: запис із мініатюрою й найімовірнішим грибом; торкнутися — повний результат', (tester) async {
    await tester.runAsync(() async {
      await RecognitionHistory.add(rankSpecies([Float32List.fromList([0.9, 0.42, 0.1, 0])], text, labels), photo());
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => catalog)],
      child: const MaterialApp(home: Scaffold(body: RecognitionHistorySheet())),
    ));
    await settleFlow(tester, find.text('Білий гриб'));
    expect(find.text('Білий гриб'), findsOneWidget);
    expect(find.textContaining('серед схожих отруйний'), findsOneWidget);
    await tester.tap(find.text('Білий гриб'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('result-danger')), findsOneWidget);
  });

  testWidgets('«Як відрізнити» відкриває гриб одразу на розділі двійників', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => catalog), oblastsProvider.overrideWith((ref) => oblasts)],
      child: const MaterialApp(home: CatalogDetailScreen(speciesId: 'boletus_edulis', focus: 'twins')),
    ));
    await tester.pumpAndSettle();
    final twins = find.byKey(const ValueKey('article-twins-section'));
    expect(twins, findsOneWidget);
    final top = tester.getTopLeft(twins).dy;
    expect(top, lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio)); // на екрані
    expect(top, greaterThanOrEqualTo(0));
  });
}
