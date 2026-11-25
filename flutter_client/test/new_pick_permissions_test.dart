// PROD-001c: форма тук-тука показує дозволи сервера (ADR-019 §19.10, ADR-018 §18.2) — клієнт нічого не
// рахує сам: «Усі» вимкнено, коли публічні не дозволені, з підказкою; ліміт приватних — попередження.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/picks/new_pick_screen.dart';
import 'package:flutter_client/features/recognize/recognizer.dart' show recognizerProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'profile_test.dart' show FakeMe, registered;

Map<String, dynamic> withPicks(Map<String, dynamic> picks) => {...registered(), 'picks': picks};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('Me.picks: розбір дозволів; старий сервер без picks — null', () {
    final me = Me.fromJson(withPicks({
      'public_allowed': false,
      'public_hint_label': 'Публічні точки — з рівня «Лісовик».',
      'private_allowed': true,
      'private_hint_label': null,
    }));
    expect([me.picks!.publicAllowed, me.picks!.publicHint, me.picks!.privateAllowed], [false, 'Публічні точки — з рівня «Лісовик».', true]);
    expect(Me.fromJson(registered()).picks, isNull);
  });

  Future<void> pumpForm(WidgetTester tester, Map<String, dynamic> me, {PickVisibility initial = PickVisibility.private}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('pick');
    final photo = File('${dir.path}/p.jpg')..writeAsBytesSync(File('assets/images/loading/${Directory('assets/images/loading').listSync().first.uri.pathSegments.last}').readAsBytesSync());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        meProvider.overrideWith(() => FakeMe(Me.fromJson(me))),
        recognizerProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: NewPickScreen(photo: XFile(photo.path), point: const LatLng(50.4, 30.5), capturedAt: DateTime(2026, 11, 25), initialVisibility: initial),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  ButtonSegment<PickVisibility> segment(WidgetTester tester, PickVisibility v) =>
      tester.widget<SegmentedButton<PickVisibility>>(find.byType(SegmentedButton<PickVisibility>)).segments.firstWhere((s) => s.value == v);

  testWidgets('Публічні не дозволені: «Усі» вимкнено, підказка сервера, вибір — лише приватна', (tester) async {
    await pumpForm(
      tester,
      withPicks({'public_allowed': false, 'public_hint_label': 'Публічні точки — з рівня «Лісовик».', 'private_allowed': true}),
      initial: PickVisibility.public, // навіть якщо відкрили як публічну
    );
    expect(segment(tester, PickVisibility.public).enabled, isFalse);
    expect(find.byKey(const ValueKey('pick-public-hint')), findsOneWidget);
    expect(find.text('Публічні точки — з рівня «Лісовик».'), findsOneWidget);
    final selected = tester.widget<SegmentedButton<PickVisibility>>(find.byType(SegmentedButton<PickVisibility>)).selected;
    expect(selected, {PickVisibility.private});
  });

  testWidgets('Лісовик: «Усі» доступне, підказок немає; 5 з 5 приватних — попередження «видаліть одну»', (tester) async {
    await pumpForm(tester, withPicks({'public_allowed': true, 'private_allowed': true}));
    expect(segment(tester, PickVisibility.public).enabled, isTrue);
    expect(find.byKey(const ValueKey('pick-public-hint')), findsNothing);
    expect(find.byKey(const ValueKey('pick-private-hint')), findsNothing);

    await pumpForm(tester, withPicks({
      'public_allowed': true,
      'private_allowed': false,
      'private_hint_label': 'У вас 5 з 5 приватних точок — видаліть одну, щоб додати нову.',
    }));
    expect(find.byKey(const ValueKey('pick-private-hint')), findsOneWidget);
    expect(find.textContaining('видаліть одну'), findsOneWidget);
  });

  testWidgets('Старий сервер без picks: нічого не вимикаємо — вирішить відповідь на створення', (tester) async {
    await pumpForm(tester, registered());
    expect(segment(tester, PickVisibility.public).enabled, isTrue);
    expect(find.byKey(const ValueKey('pick-public-hint')), findsNothing);
  });
}
