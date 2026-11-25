// PERF-001 (запобіжник): анімовані наліпки й кошик на мінікарті не перемальовують саму карту щокадру.
// Виміряно 2026-11-25: 0 перемальовувань карти за 60 кадрів — кожну наліпку відокремлює `Opacity`
// (окремий шар). Тест падає, якщо цю межу приберуть: тоді знімок або MapLibre малювались би щокадру.
import 'package:flutter/material.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../area_mini_map_test.dart' show boletus, camera, chanterelle;

class _CountingPainter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xffdcedc8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  Future<_CountingPainter> pumpBoard(WidgetTester tester, Map<String, LatLng> positions) async {
    final painter = _CountingPainter();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          StickerBoard(
            camera: camera(),
            species: const [boletus, chanterelle],
            positions: positions,
            map: CustomPaint(painter: painter),
            history: const [],
            onMove: (_, __) {},
            onRemove: (_) {},
          ),
        ]),
      ),
    ));
    await tester.pump();
    return painter;
  }

  Future<int> paintsDuringOneSecond(WidgetTester tester, _CountingPainter painter) async {
    final before = painter.paints;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return painter.paints - before;
  }

  testWidgets('гриб із піковим шансом на карті: карта малюється не щокадру', (tester) async {
    final painter = await pumpBoard(tester, {boletus.type: const LatLng(50.22, 28.63)});
    expect(painter.paints, greaterThan(0), reason: 'карта намальована');
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'наліпка анімується');
    final n = await paintsDuringOneSecond(tester, painter);
    // ignore: avoid_print
    print('map paints / 60 frames (sticker on map): $n, total ${painter.paints}');
    expect(n, lessThanOrEqualTo(1));
  });

  testWidgets('гриби в кошику підстрибують: карта малюється не щокадру', (tester) async {
    final painter = await pumpBoard(tester, const {});
    final n = await paintsDuringOneSecond(tester, painter);
    // ignore: avoid_print
    print('map paints / 60 frames (basket): $n');
    expect(n, lessThanOrEqualTo(1));
  });
}
