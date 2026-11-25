// UI-001 (частина 2): основні вкладки й форма тук-тука не ламаються на малому екрані, зі шрифтом ×2 і
// в альбомній орієнтації — ті самі умови, що layout_stress_test.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_browser.dart';
import 'package:flutter_client/features/catalog/catalog_detail_screen.dart';
import 'package:flutter_client/features/forecast/forecast_screen.dart';
import 'package:flutter_client/features/picks/new_pick_screen.dart';
import 'package:flutter_client/features/recognize/ai_model.dart';
import 'package:flutter_client/features/recognize/recognizer.dart' show recognizerProvider;
import 'package:flutter_client/features/safety/safety_device.dart' show safetyDeviceProvider;
import 'package:flutter_client/features/safety/safety_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../catalog_test.dart' show catalog;
import '../forecast_test.dart' show areaJson, overview;
import '../profile_test.dart' show FakeMe, registered;
import '../safety_test.dart' show FakeDevice;
import 'layout_stress_test.dart' show stressCases;

Future<void> pumpStress(WidgetTester tester, Widget screen, ({String name, Size size, double text}) c,
    {List<Override> overrides = const []}) async {
  tester.view.physicalSize = c.size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(c.text)),
        child: child!,
      ),
      home: screen,
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Прокрутити всі вертикальні списки донизу — нижні елементи теж мають бути цілими.
Future<void> scrollAll(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  for (var i = 0; i < scrollables.evaluate().length && i < 3; i++) {
    final s = tester.widget<Scrollable>(scrollables.at(i));
    if (s.axisDirection != AxisDirection.down) continue;
    await tester.drag(scrollables.at(i), const Offset(0, -4000), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// ШІ ще не завантажено, мережа є — банер із найдовшим текстом і кнопкою «Завантажити ШІ».
class _NotDownloadedAi extends AiModelController {
  @override
  AiModelState build() => const AiModelState(
        checked: true,
        remote: AiModelManifest(
          version: 'v1',
          files: [AiModelFile(name: 'model.onnx', size: 180 * 1024 * 1024, sha256: 'x')],
          imageSize: 224,
          mean: [0.5, 0.5, 0.5],
          std: [0.5, 0.5, 0.5],
          species: 120,
        ),
      );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final species = catalog.species.firstWhere((s) => s.id == 'boletus_edulis', orElse: () => catalog.species.first);
  final photoDir = Directory.systemTemp.createTempSync('pick');
  final photo = File('${photoDir.path}/p.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

  final screens = <(String, Widget Function(), List<Override> Function())>[
    ('Безпека', () => const SafetyScreen(), () => [safetyDeviceProvider.overrideWithValue(FakeDevice())]),
    ('Прогноз (ділянка)', () => const ForecastScreen(),
        () => [analysisOverviewProvider.overrideWith((ref) => overview(areas: [areaJson(withResult: true)]))]),
    (
      'Довідник',
      () => const Scaffold(body: CatalogBrowser()),
      () => [catalogProvider.overrideWith((ref) => catalog), aiModelProvider.overrideWith(_NotDownloadedAi.new)],
    ),
    ('Картка виду', () => CatalogDetailScreen(speciesId: species.id), () => [catalogProvider.overrideWith((ref) => catalog)]),
    (
      'Форма тук-тука',
      () => NewPickScreen(photo: XFile(photo.path), point: const LatLng(50.4, 30.5), capturedAt: DateTime(2026, 11, 25)),
      () => [
            meProvider.overrideWith(() => FakeMe(Me.fromJson({
                  ...registered(),
                  'picks': {'public_allowed': false, 'public_hint_label': 'Публічні точки — з рівня «Лісовик». Поки що зробіть приватний тук-тук.', 'private_allowed': true},
                }))),
            recognizerProvider.overrideWith((ref) async => null),
          ],
    ),
  ];

  for (final c in stressCases) {
    for (final (name, screen, overrides) in screens) {
      testWidgets('$name: ${c.name} — без переповнення', (tester) async {
        final overflows = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          final text = details.toString();
          if (!text.contains('overflowed')) return; // шрифти Google у тестах недоступні — не наша справа
          final where = text.split('\n').firstWhere((l) => l.contains('/lib/'), orElse: () => '');
          overflows.add('${details.exceptionAsString().split('\n').first} ${where.trim()}');
        };
        addTearDown(() => FlutterError.onError = original);
        await pumpStress(tester, screen(), c, overrides: overrides());
        await scrollAll(tester);
        FlutterError.onError = original;
        expect(overflows, isEmpty);
      });
    }
  }
}
