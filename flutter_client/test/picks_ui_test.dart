import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/repositories/picks_repository.dart';
import 'package:flutter_client/features/picks/mushroom_marker.dart';
import 'package:flutter_client/features/picks/photo_validation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'data/fake_adapter.dart';

Uint8List jpeg(int size) => Uint8List(size)..setAll(0, [0xFF, 0xD8, 0xFF, 0xE0]);

void main() {
  group('Перевірка фото тук-тука', () {
    test('JPEG / PNG / WebP — за вмістом файлу', () {
      expect(detectImageContentType(jpeg(16)), 'image/jpeg');
      expect(
        detectImageContentType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])),
        'image/png',
      );
      expect(
        detectImageContentType(Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50])),
        'image/webp',
      );
      expect(detectImageContentType(Uint8List.fromList('GIF89a......'.codeUnits)), isNull);
    });

    test('розмір: порожній / завеликий / нормальний', () {
      expect(checkPickPhoto(sizeBytes: 100, head: jpeg(12)).error, contains('пошкоджене'));
      expect(checkPickPhoto(sizeBytes: 6 * 1024 * 1024, head: jpeg(12)).error, contains('до 5 МБ'));
      final ok = checkPickPhoto(sizeBytes: 300 * 1024, head: jpeg(12));
      expect([ok.isOk, ok.contentType], [true, 'image/jpeg']);
    });

    test('фото обов\'язкове; непідтримуваний формат — помилка', () async {
      expect((await validatePickPhoto(null)).error, contains('потрібне фото'));
      final gif = XFile.fromData(Uint8List.fromList([...'GIF89a'.codeUnits, ...List.filled(4000, 0)]), name: 'x.jpg');
      expect((await validatePickPhoto(gif)).error, contains('формат'));
      final good = XFile.fromData(jpeg(4000), name: 'photo.bin'); // розширення не важливе
      final r = await validatePickPhoto(good);
      expect([r.isOk, r.contentType, r.sizeBytes], [true, 'image/jpeg', 4000]);
    });

    test('репозиторій не відправляє запити без допустимого фото', () async {
      final (api, adapter) = makeClient((_) => const FakeResponse(200, {'data': {}}));
      final repo = PicksRepository(api, uploads: Dio());
      final pick = NewPick(
        clientId: 'c1',
        point: const LatLng(50.4, 30.5),
        capturedAt: DateTime(2026, 11, 12),
        visibility: PickVisibility.private,
        speciesId: null,
      );
      for (final photo in [
        PickPhoto(openRead: () => const Stream.empty(), sizeBytes: 0, contentType: 'image/jpeg'),
        PickPhoto(openRead: () => const Stream.empty(), sizeBytes: 6 * 1024 * 1024, contentType: 'image/jpeg'),
        PickPhoto(openRead: () => const Stream.empty(), sizeBytes: 5000, contentType: 'image/gif'),
      ]) {
        await expectLater(
          repo.createPick(pick, photo),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiException.invalidPhoto)),
        );
      }
      expect(adapter.requests, isEmpty);
    });
  });

  testWidgets('Маркер: публічний — гриб без замка, приватний — гриб із замком', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Row(children: [
        MushroomMarker(key: Key('pub'), color: Color(0xFF43A047), isPrivate: false),
        MushroomMarker(key: Key('priv'), color: Color(0xFF8E24AA), isPrivate: true),
      ]),
    ));
    expect(find.descendant(of: find.byKey(const Key('pub')), matching: find.byIcon(Icons.lock_rounded)), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('priv')), matching: find.byIcon(Icons.lock_rounded)), findsOneWidget);
    expect(find.bySemanticsLabel('Приватний тук-тук'), findsOneWidget);
  });
}
