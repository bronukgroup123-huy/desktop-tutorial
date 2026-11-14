import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Маркер тук-тука у вигляді гриба (ADR-018 §18.2).
///
/// * Колір шапки — із сервера: публічні — за статусом перевірки (сірий
///   «Перевіряється», зелений «Підтверджено»), приватні — власний колір.
/// * Приватна точка додатково має значок замка, щоб її не сплутати з публічною
///   навіть за схожого кольору.
class MushroomMarker extends StatelessWidget {
  const MushroomMarker({super.key, required this.color, required this.isPrivate, this.tooltip, this.size = 36});

  final Color color;
  final bool isPrivate;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final marker = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: _MushroomPainter(capColor: color))),
          if (isPrivate)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                key: const ValueKey('private-lock'),
                width: size * 0.42,
                height: size * 0.42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Icon(Icons.lock_rounded, size: size * 0.26, color: color),
              ),
            ),
        ],
      ),
    );
    final labelled = Semantics(
      label: isPrivate ? 'Приватний тук-тук' : 'Публічний тук-тук',
      child: marker,
    );
    return tooltip == null ? labelled : Tooltip(message: tooltip!, child: labelled);
  }
}

class _MushroomPainter extends CustomPainter {
  _MushroomPainter({required this.capColor});

  final Color capColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    // Ніжка.
    final stem = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.36, h * 0.42, w * 0.28, h * 0.52),
      bottomLeft: Radius.circular(w * 0.1),
      bottomRight: Radius.circular(w * 0.1),
    );
    // Шапка — півеліпс із легко підігнутим краєм.
    final cap = Path()
      ..moveTo(w * 0.04, h * 0.5)
      ..quadraticBezierTo(w * 0.04, h * 0.04, w * 0.5, h * 0.04)
      ..quadraticBezierTo(w * 0.96, h * 0.04, w * 0.96, h * 0.5)
      ..quadraticBezierTo(w * 0.5, h * 0.4, w * 0.04, h * 0.5)
      ..close();

    canvas.drawPath(cap.shift(const Offset(0, 1.5)), shadow);
    canvas.drawRRect(stem.shift(const Offset(0, 1.5)), shadow);

    canvas.drawRRect(stem, Paint()..color = const Color(0xFFFFF3E0));
    canvas.drawRRect(stem, outline);
    canvas.drawPath(cap, Paint()..color = capColor);
    canvas.drawPath(cap, outline);

    // Світлі цятки на шапці — щоб читалось як гриб навіть дрібно.
    final dots = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(Offset(w * 0.34, h * 0.24), w * 0.06, dots);
    canvas.drawCircle(Offset(w * 0.6, h * 0.18), w * 0.045, dots);
    canvas.drawCircle(Offset(w * 0.7, h * 0.34), w * 0.04, dots);
  }

  @override
  bool shouldRepaint(_MushroomPainter old) => old.capColor != capColor;
}

/// Маркер тук-тука картинкою (PNG) — для карти MapLibre, де значки малює відеокарта.
/// Той самий гриб, що й у [MushroomMarker]; приватний — із замком. Ніжка — внизу по центру
/// (точка на карті), запас по краях — під тінь і замок.
Future<Uint8List> mushroomMarkerPng({
  required Color color,
  required bool isPrivate,
  double size = 36,
  double pixelRatio = 3,
}) async {
  const pad = 4.0;
  final logical = Size(size + pad * 2, size + pad * 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(pixelRatio)
    ..translate(pad, pad);
  _MushroomPainter(capColor: color).paint(canvas, Size(size, size));
  if (isPrivate) {
    final r = size * 0.21;
    final c = Offset(size + 2 - r, size + 2 - r);
    canvas
      ..drawCircle(c, r, Paint()..color = Colors.white)
      ..drawCircle(
          c,
          r,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    const icon = Icons.lock_rounded;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size * 0.26, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }
  final image = await recorder
      .endRecording()
      .toImage((logical.width * pixelRatio).ceil(), (logical.height * pixelRatio).ceil());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
