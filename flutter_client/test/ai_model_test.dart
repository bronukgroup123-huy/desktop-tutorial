import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter_client/features/recognize/ai_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Реліз «ai-model» у пам'яті: файли й маніфест; [cutAt] — обрив передачі після стількох байтів.
class FakeRelease {
  FakeRelease({this.version = '2026.11.17'});

  final String version;
  final files = {
    'bioclip2_vision_int8.onnx': List<int>.generate(5000, (i) => i % 251),
    'species_text.f16': List<int>.generate(1200, (i) => (i * 7) % 256),
    'labels.json': utf8.encode('[{"id":"boletus_edulis"}]'),
  };
  int? cutAt;
  final starts = <String, int>{};
  bool corrupt = false;

  Map<String, dynamic> manifest() => {
        'version': version,
        'image_size': 224,
        'mean': [0.48, 0.45, 0.4],
        'std': [0.26, 0.26, 0.27],
        'species': 326,
        'files': {for (final e in files.entries) e.key: {'size': e.value.length, 'sha256': sha256.convert(e.value).toString()}},
      };

  void install() {
    AiModelIo.fetch = (url) async => url.endsWith('manifest.json') ? utf8.encode(jsonEncode(manifest())) : null;
    AiModelIo.stream = (url, from, onChunk, cancelled) async {
      final name = url.split('/').last;
      starts[name] = from;
      var data = files[name]!;
      if (corrupt) data = [...data]..[data.length - 1] ^= 0xff;
      var sent = from;
      while (sent < data.length) {
        if (cutAt != null && sent >= cutAt!) return false;
        final end = (sent + 700).clamp(0, data.length);
        await onChunk(data.sublist(sent, end));
        sent = end;
      }
      return true;
    };
  }
}

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ai_model');
    AiModelIo.directory = () async => dir;
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('Модель із релізу: розмір з маніфесту → завантаження → перевірено sha256 → готова', () async {
    final r = FakeRelease()..install();
    final c = container();
    final ctrl = c.read(aiModelProvider.notifier);
    await ctrl.refresh();
    var s = c.read(aiModelProvider);
    expect(s.ready, isFalse);
    expect(s.remote!.totalBytes, 5000 + 1200 + r.files['labels.json']!.length);
    await ctrl.start();
    s = c.read(aiModelProvider);
    expect(s.ready, isTrue);
    expect(s.installed!.version, '2026.11.17');
    expect(File('${dir.path}/bioclip2_vision_int8.onnx').lengthSync(), 5000);
    // Нове відкриття застосунку — модель на місці, без мережі.
    AiModelIo.fetch = (_) async => null;
    final c2 = container();
    await c2.read(aiModelProvider.notifier).refresh();
    expect(c2.read(aiModelProvider).ready, isTrue);
  });

  test('Обрив — «Продовжити» докачує з того ж місця (Range), не з нуля', () async {
    final r = FakeRelease()
      ..cutAt = 2100
      ..install();
    final c = container();
    final ctrl = c.read(aiModelProvider.notifier);
    await ctrl.start();
    expect(c.read(aiModelProvider).ready, isFalse);
    expect(c.read(aiModelProvider).error, isNotNull);
    r.cutAt = null;
    await ctrl.start();
    expect(c.read(aiModelProvider).ready, isTrue);
    expect(r.starts['bioclip2_vision_int8.onnx'], 2100);
  });

  test('Пошкоджений файл (sha256) — не встановлюється', () async {
    FakeRelease()
      ..corrupt = true
      ..install();
    final c = container();
    await c.read(aiModelProvider.notifier).start();
    expect(c.read(aiModelProvider).ready, isFalse);
    expect(c.read(aiModelProvider).error, contains('пошкоджено'));
  });

  test('Нова версія в релізі — «Оновити»; «Видалити» звільняє місце', () async {
    FakeRelease().install();
    final c = container();
    final ctrl = c.read(aiModelProvider.notifier);
    await ctrl.start();
    FakeRelease(version: '2026.12.01').install();
    await ctrl.refresh();
    expect(c.read(aiModelProvider).updateAvailable, isTrue);
    await ctrl.deleteModel();
    expect(c.read(aiModelProvider).ready, isFalse);
    expect(dir.existsSync(), isFalse);
  });

  testWidgets('Картка: розмір → «Завантажити» → «на телефоні» → «Видалити»', (tester) async {
    FakeRelease().install();
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: Scaffold(body: AiModelCard()))));
    Future<void> until(Finder f) async {
      for (var i = 0; i < 2000 && f.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
    }

    await until(find.byKey(const ValueKey('ai-download')));
    expect(find.text('ШІ-розпізнавач'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-download')));
    await until(find.byKey(const ValueKey('ai-ready')));
    expect(find.byKey(const ValueKey('ai-ready')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-delete-confirm')));
    await until(find.byKey(const ValueKey('ai-download')));
    expect(find.byKey(const ValueKey('ai-download')), findsOneWidget);
  });
}
