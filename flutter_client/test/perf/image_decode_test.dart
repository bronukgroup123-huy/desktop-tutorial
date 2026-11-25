// PERF-001: фото з камери в мініатюрах і прев'ю не розкодовуються в повному розмірі.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_client/core/image_decode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List jpeg(int w, int h) => Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h), quality: 60));

Future<Size> decodedSize(WidgetTester tester, ImageProvider provider) async {
  final size = await tester.runAsync(() {
    final done = Completer<Size>();
    provider.resolve(ImageConfiguration.empty).addListener(ImageStreamListener(
          (info, _) => done.complete(Size(info.image.width.toDouble(), info.image.height.toDouble())),
          onError: (e, _) => done.completeError(e),
        ));
    return done.future;
  });
  return size!;
}

void main() {
  test('ширина декодування покриває рамку для 16:9 і 4:3 в обох орієнтаціях', () {
    for (final dpr in [1.0, 2.0, 2.75, 3.0]) {
      for (final box in const [Size(58, 58), Size(360, 220), Size(280, 220)]) {
        final w = coverDecodeWidth(box, dpr);
        for (final aspect in [16 / 9, 4 / 3, 1.0, 3 / 4, 9 / 16]) {
          final h = w / aspect; // висота розкодованого кадру з такою шириною
          expect(w, greaterThanOrEqualTo(box.width * dpr), reason: 'ширина: $box @$dpr, $aspect');
          expect(h, greaterThanOrEqualTo(box.height * dpr - 1), reason: 'висота: $box @$dpr, $aspect');
        }
      }
    }
  });

  testWidgets('кадр 1280×720 у мініатюрі 58×58 (dpr 3): у ~16 разів менше пам\'яті', (tester) async {
    final bytes = jpeg(1280, 720);
    final full = await decodedSize(tester, MemoryImage(bytes));
    final small = await decodedSize(tester, ResizeImage(MemoryImage(bytes), width: coverDecodeWidth(const Size(58, 58), 3)));
    final fullMb = full.width * full.height * 4 / 1e6, smallMb = small.width * small.height * 4 / 1e6;
    // ignore: avoid_print
    print('decoded: full $full = ${fullMb.toStringAsFixed(2)} MB; thumb $small = ${smallMb.toStringAsFixed(2)} MB');
    expect(full, const Size(1280, 720));
    expect(small.height, greaterThanOrEqualTo(58 * 3 - 1)); // не розмито
    expect(smallMb, lessThan(fullMb / 10));
  });

  testWidgets('маленьке фото не збільшується при декодуванні', (tester) async {
    final bytes = jpeg(200, 150);
    final s = await decodedSize(tester, ResizeImage(MemoryImage(bytes), width: coverDecodeWidth(const Size(360, 220), 3)));
    expect(s, const Size(200, 150));
  });
}
