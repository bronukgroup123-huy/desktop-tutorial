import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Гриб-персонаж для сценок довідника (рішення PO 2026-11-16): кожен вид Топ-20 намальований за
/// своїм виглядом (форма й колір шапки, трубочки / пластинки / шипи / складки, ніжка з сіточкою,
/// лусочками чи кільцем) — з обличчям, емоціями й руками.
///
/// Малюється в одиницях 100×100: земля — y = 100, центр — x = 50.

enum CapShape { bun, convex, funnel, chanterelle, hedgehog, oyster, puffball, morel }

enum Underside { tubes, gills, spines, folds, none }

enum StemShape { barrel, stout, tall, slender, none }

enum StemMark { none, net, scaber, ring, velvet, pits }

enum CapMark { none, shine, scales, zones, hairyRim, warts, pits }

class CharacterLook {
  const CharacterLook({
    required this.cap,
    required this.capColor,
    required this.under,
    required this.underColor,
    required this.stem,
    required this.stemColor,
    this.capMark = CapMark.none,
    this.capMarkColor = const Color(0xff000000),
    this.stemMark = StemMark.none,
    this.stemMarkColor = const Color(0xff000000),
    this.capWidth = 66,
  });

  final CapShape cap;
  final Color capColor;
  final CapMark capMark;
  final Color capMarkColor;
  final Underside under;
  final Color underColor;
  final StemShape stem;
  final Color stemColor;
  final StemMark stemMark;
  final Color stemMarkColor;
  final double capWidth;
}

/// Вигляд 20 видів Топ-20 — за книжковими описами і фото довідника.
const kCharacterLooks = <String, CharacterLook>{
  'boletus_edulis': CharacterLook(
    cap: CapShape.bun, capColor: Color(0xff8b5a2b), capMark: CapMark.shine,
    under: Underside.tubes, underColor: Color(0xfff1e6c8),
    stem: StemShape.barrel, stemColor: Color(0xfff1e3c6), stemMark: StemMark.net, stemMarkColor: Color(0xffffffff), capWidth: 72),
  'imleria_badia': CharacterLook(
    cap: CapShape.bun, capColor: Color(0xff6b3a1e), capMark: CapMark.shine,
    under: Underside.tubes, underColor: Color(0xffe6d47a),
    stem: StemShape.stout, stemColor: Color(0xffc49a6c), capWidth: 70),
  'boletus_luridus': CharacterLook(
    cap: CapShape.bun, capColor: Color(0xff8a7444),
    under: Underside.tubes, underColor: Color(0xffd9532b),
    stem: StemShape.stout, stemColor: Color(0xffe5b83b), stemMark: StemMark.net, stemMarkColor: Color(0xffb3361f), capWidth: 70),
  'xerocomus_subtomentosus': CharacterLook(
    cap: CapShape.bun, capColor: Color(0xff8c7a45),
    under: Underside.tubes, underColor: Color(0xffe3c83a),
    stem: StemShape.slender, stemColor: Color(0xffd9c38a), capWidth: 66),
  'leccinum_scabrum': CharacterLook(
    cap: CapShape.bun, capColor: Color(0xff9c6b3e), capMark: CapMark.shine,
    under: Underside.tubes, underColor: Color(0xffe9dfd0),
    stem: StemShape.tall, stemColor: Color(0xffefeae0), stemMark: StemMark.scaber, stemMarkColor: Color(0xff2e2e2e), capWidth: 62),
  'leccinum_aurantiacum': CharacterLook(
    cap: CapShape.bun, capColor: Color(0xffd9581e), capMark: CapMark.shine,
    under: Underside.tubes, underColor: Color(0xffede5d8),
    stem: StemShape.tall, stemColor: Color(0xfff2ede4), stemMark: StemMark.scaber, stemMarkColor: Color(0xff4a3a30), capWidth: 64),
  'suillus_luteus': CharacterLook(
    cap: CapShape.convex, capColor: Color(0xff7a4a1e), capMark: CapMark.shine,
    under: Underside.tubes, underColor: Color(0xffe8c64a),
    stem: StemShape.slender, stemColor: Color(0xfff0e0a0), stemMark: StemMark.ring, stemMarkColor: Color(0xff7a5a7a), capWidth: 66),
  'suillus_bovinus': CharacterLook(
    cap: CapShape.convex, capColor: Color(0xffc08a55),
    under: Underside.tubes, underColor: Color(0xffb89a4a),
    stem: StemShape.slender, stemColor: Color(0xffd4a86a), capWidth: 70),
  'russula_vesca': CharacterLook(
    cap: CapShape.funnel, capColor: Color(0xffb5707a),
    under: Underside.gills, underColor: Color(0xfffbf7ef),
    stem: StemShape.stout, stemColor: Color(0xffffffff), capWidth: 68),
  'agaricus_campestris': CharacterLook(
    cap: CapShape.convex, capColor: Color(0xfff7f3ea),
    under: Underside.gills, underColor: Color(0xffc9707a),
    stem: StemShape.slender, stemColor: Color(0xffffffff), stemMark: StemMark.ring, stemMarkColor: Color(0xffeeeeee), capWidth: 64),
  'armillaria_mellea': CharacterLook(
    cap: CapShape.convex, capColor: Color(0xffc99a3a), capMark: CapMark.scales, capMarkColor: Color(0xff6b4a1e),
    under: Underside.gills, underColor: Color(0xfff2e6c8),
    stem: StemShape.slender, stemColor: Color(0xffd8c08a), stemMark: StemMark.ring, stemMarkColor: Color(0xfff5ebd5), capWidth: 58),
  'flammulina_velutipes': CharacterLook(
    cap: CapShape.convex, capColor: Color(0xffe08a1e), capMark: CapMark.shine,
    under: Underside.gills, underColor: Color(0xfff4e3b0),
    stem: StemShape.slender, stemColor: Color(0xffd9a35a), stemMark: StemMark.velvet, stemMarkColor: Color(0xff3b2418), capWidth: 56),
  'lactarius_deliciosus': CharacterLook(
    cap: CapShape.funnel, capColor: Color(0xffe8782a), capMark: CapMark.zones, capMarkColor: Color(0xffc85a1a),
    under: Underside.gills, underColor: Color(0xffe98a3a),
    stem: StemShape.stout, stemColor: Color(0xffe8873a), stemMark: StemMark.pits, stemMarkColor: Color(0xffc8641e), capWidth: 70),
  'lactarius_torminosus': CharacterLook(
    cap: CapShape.funnel, capColor: Color(0xffefa7a0), capMark: CapMark.hairyRim, capMarkColor: Color(0xfff8d3cc),
    under: Underside.gills, underColor: Color(0xfff5e6da),
    stem: StemShape.stout, stemColor: Color(0xfff2c5be), capWidth: 70),
  'lactarius_resimus': CharacterLook(
    cap: CapShape.funnel, capColor: Color(0xfff7f2e2), capMark: CapMark.hairyRim, capMarkColor: Color(0xffe2d3a6),
    under: Underside.gills, underColor: Color(0xfffbf5e3),
    stem: StemShape.stout, stemColor: Color(0xffffffff), capWidth: 74),
  'cantharellus_cibarius': CharacterLook(
    cap: CapShape.chanterelle, capColor: Color(0xfff2b21e),
    under: Underside.folds, underColor: Color(0xffe39e14),
    stem: StemShape.none, stemColor: Color(0xfff2b21e), capWidth: 66),
  'hydnum_repandum': CharacterLook(
    cap: CapShape.hedgehog, capColor: Color(0xffe9b97a),
    under: Underside.spines, underColor: Color(0xfff6e3c3),
    stem: StemShape.stout, stemColor: Color(0xfff7ead3), capWidth: 70),
  'pleurotus_ostreatus': CharacterLook(
    cap: CapShape.oyster, capColor: Color(0xff8e959c),
    under: Underside.gills, underColor: Color(0xffefebe3),
    stem: StemShape.none, stemColor: Color(0xffe8e2d6), capWidth: 70),
  'lycoperdon_perlatum': CharacterLook(
    cap: CapShape.puffball, capColor: Color(0xfff3eedc), capMark: CapMark.warts, capMarkColor: Color(0xffd6cbae),
    under: Underside.none, underColor: Color(0xfff3eedc),
    stem: StemShape.none, stemColor: Color(0xfff3eedc), capWidth: 56),
  'morchella_esculenta': CharacterLook(
    cap: CapShape.morel, capColor: Color(0xffc9a36a), capMark: CapMark.pits, capMarkColor: Color(0xff7a5a30),
    under: Underside.none, underColor: Color(0xffc9a36a),
    stem: StemShape.stout, stemColor: Color(0xfff3e9d2), capWidth: 44),
};

bool hasCharacter(String speciesId) => kCharacterLooks.containsKey(speciesId);

// ─── Обличчя й руки ─────────────────────────────────────────────────────────

enum Eyes { open, closed, happy, wide, squint, wink, sleepy, dizzy }

enum Mouth { smile, grin, open, o, flat, yawn, wavy }

class Face {
  const Face({this.eyes = Eyes.open, this.mouth = Mouth.smile, this.look = Offset.zero, this.blush = false, this.brows = 0});

  final Eyes eyes;
  final Mouth mouth;

  /// Куди дивляться зіниці: −1…1 по x і y.
  final Offset look;
  final bool blush;

  /// Брови: 1 — підняті (здивування), −1 — насуплені (зосередження), 0 — немає.
  final double brows;

  Face copyWith({Eyes? eyes, Mouth? mouth, Offset? look, bool? blush, double? brows}) => Face(
        eyes: eyes ?? this.eyes,
        mouth: mouth ?? this.mouth,
        look: look ?? this.look,
        blush: blush ?? this.blush,
        brows: brows ?? this.brows,
      );
}

/// Рука: [a] — кут у плечі (0 — вниз, π/2 — убік, π — угору), [b] — згин у лікті.
class Arm {
  const Arm(this.a, [this.b = 0.25]);

  final double a, b;

  static const down = Arm(0.3, 0.2);
  static const up = Arm(2.8, 0.1);
  static const out = Arm(1.6, 0.1);

  static Arm lerp(Arm x, Arm y, double t) => Arm(x.a + (y.a - x.a) * t, x.b + (y.b - x.b) * t);
}

// ─── Малюнок ────────────────────────────────────────────────────────────────

class MushroomCharacter extends StatelessWidget {
  const MushroomCharacter({
    super.key,
    required this.look,
    this.face = const Face(),
    this.left = Arm.down,
    this.right = Arm.down,
    this.size = 64,
  });

  final CharacterLook look;
  final Face face;
  final Arm left, right;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: MushroomCharacterPainter(look: look, face: face, left: left, right: right)),
      );
}

class MushroomCharacterPainter extends CustomPainter {
  MushroomCharacterPainter({required this.look, required this.face, required this.left, required this.right});

  final CharacterLook look;
  final Face face;
  final Arm left, right;

  static const _ink = Color(0xff3a2a1e);

  Paint get _outline => Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  /// Ніжка: верх, ширина вгорі й унизу.
  ({double top, double wTop, double wBottom}) get _stem => switch (look.stem) {
        StemShape.barrel => (top: 56, wTop: 22, wBottom: 30),
        StemShape.stout => (top: 56, wTop: 22, wBottom: 25),
        StemShape.tall => (top: 50, wTop: 16, wBottom: 20),
        StemShape.slender => (top: 56, wTop: 15, wBottom: 18),
        StemShape.none => (top: 66, wTop: 18, wBottom: 20),
      };

  /// Де обличчя і плечі.
  ({Offset face, double shoulderY, double halfW}) get _anchor {
    switch (look.cap) {
      case CapShape.oyster:
        return (face: const Offset(60, 50), shoulderY: 64, halfW: 22);
      case CapShape.puffball:
        return (face: const Offset(50, 70), shoulderY: 76, halfW: 25);
      case CapShape.chanterelle:
        return (face: const Offset(50, 76), shoulderY: 80, halfW: 10);
      default:
        final s = _stem;
        final y = s.top + (100 - s.top) * 0.42;
        return (face: Offset(50, y), shoulderY: y + 7, halfW: (s.wTop + (s.wBottom - s.wTop) * 0.55) / 2);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    // Тінь.
    canvas.drawOval(Rect.fromCenter(center: const Offset(50, 99), width: 46, height: 6), Paint()..color = Colors.black.withValues(alpha: 0.12));
    switch (look.cap) {
      case CapShape.chanterelle:
        _chanterelle(canvas);
      case CapShape.oyster:
        _oyster(canvas);
      case CapShape.puffball:
        _puffball(canvas);
      default:
        _stemPaint(canvas);
        _capPaint(canvas);
    }
    _arms(canvas);
    _face(canvas);
    canvas.restore();
  }

  // ─── Ніжка ────────────────────────────────────────────────────────────────

  void _stemPaint(Canvas c) {
    final s = _stem;
    final bulge = look.stem == StemShape.barrel ? 7.0 : 2.0;
    final path = Path()
      ..moveTo(50 - s.wTop / 2, s.top)
      ..quadraticBezierTo(50 - s.wBottom / 2 - bulge, (s.top + 100) / 2 + 8, 50 - s.wBottom / 2, 98)
      ..quadraticBezierTo(50, 101, 50 + s.wBottom / 2, 98)
      ..quadraticBezierTo(50 + s.wBottom / 2 + bulge, (s.top + 100) / 2 + 8, 50 + s.wTop / 2, s.top)
      ..close();
    c.drawPath(path, Paint()..color = look.stemColor);
    c.save();
    c.clipPath(path);
    final mark = Paint()..color = look.stemMarkColor;
    switch (look.stemMark) {
      case StemMark.net:
        final p = Paint()
          ..color = look.stemMarkColor.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9;
        // Сіточка — лише над обличчям (вгорі ніжки, як у справжнього гриба).
        for (var y = s.top + 2; y < _anchor.face.dy - 10; y += 4) {
          for (var x = 30.0; x < 70; x += 5) {
            c.drawLine(Offset(x, y), Offset(x + 3, y + 3), p);
            c.drawLine(Offset(x + 3, y), Offset(x, y + 3), p);
          }
        }
      case StemMark.scaber:
        final r = math.Random(3);
        for (var i = 0; i < 30; i++) {
          final p = Offset(38 + r.nextDouble() * 24, s.top + 4 + r.nextDouble() * (94 - s.top));
          if ((p - _anchor.face).distance < 12) continue; // обличчя чисте
          c.drawCircle(p, 0.9 + r.nextDouble() * 0.7, mark);
        }
      case StemMark.velvet:
        c.drawRect(Rect.fromLTRB(20, s.top + (100 - s.top) * 0.55, 80, 100), mark);
      case StemMark.pits:
        for (final (x, y) in [(42.0, 92.0), (58.0, 94.0), (50.0, 97.0)]) { // ямки — внизу, під обличчям
          c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 4, height: 3), mark..color = look.stemMarkColor.withValues(alpha: 0.7));
        }
      default:
    }
    c.restore();
    c.drawPath(path, _outline);
    if (look.stemMark == StemMark.ring) {
      final ry = s.top + 9;
      final ring = Path()
        ..moveTo(50 - s.wTop / 2 - 3, ry)
        ..quadraticBezierTo(50, ry + 7, 50 + s.wTop / 2 + 3, ry)
        ..lineTo(50 + s.wTop / 2, ry - 2.5)
        ..quadraticBezierTo(50, ry + 2, 50 - s.wTop / 2, ry - 2.5)
        ..close();
      c.drawPath(ring, Paint()..color = look.stemMarkColor);
      c.drawPath(ring, _outline..strokeWidth = 1.6);
    }
  }

  // ─── Шапки ────────────────────────────────────────────────────────────────

  void _capPaint(Canvas c) {
    final w = look.capWidth, l = 50 - w / 2, r = 50 + w / 2;
    final bottom = _stem.top + 3;
    late Path cap;
    switch (look.cap) {
      case CapShape.bun:
        cap = Path()
          ..moveTo(l, bottom)
          ..cubicTo(l - 2, bottom - 44, r + 2, bottom - 44, r, bottom)
          ..quadraticBezierTo(50, bottom + 7, l, bottom)
          ..close();
      case CapShape.convex:
        cap = Path()
          ..moveTo(l, bottom)
          ..cubicTo(l + 2, bottom - 32, r - 2, bottom - 32, r, bottom)
          ..quadraticBezierTo(50, bottom + 6, l, bottom)
          ..close();
      case CapShape.funnel:
        cap = Path()
          ..moveTo(l, bottom - 14)
          ..quadraticBezierTo(50, bottom - 2, r, bottom - 14)
          ..quadraticBezierTo(r + 2, bottom - 4, r - 6, bottom)
          ..quadraticBezierTo(50, bottom + 6, l + 6, bottom)
          ..quadraticBezierTo(l - 2, bottom - 4, l, bottom - 14)
          ..close();
      case CapShape.hedgehog:
        cap = Path()
          ..moveTo(l, bottom)
          ..cubicTo(l - 4, bottom - 26, 44, bottom - 34, 58, bottom - 28)
          ..cubicTo(70, bottom - 33, r + 4, bottom - 20, r, bottom)
          ..quadraticBezierTo(50, bottom + 6, l, bottom)
          ..close();
      case CapShape.morel:
        cap = Path()
          ..moveTo(32, bottom + 2)
          ..cubicTo(26, bottom - 28, 40, bottom - 52, 50, bottom - 54)
          ..cubicTo(60, bottom - 52, 74, bottom - 28, 68, bottom + 2)
          ..quadraticBezierTo(50, bottom + 7, 32, bottom + 2)
          ..close();
      default:
        return;
    }
    // Низ шапки — смужка трубочок / пластинок / шипів.
    if (look.under != Underside.none && look.cap != CapShape.morel) {
      final under = Path()
        ..moveTo(l + 4, bottom - 1)
        ..quadraticBezierTo(50, bottom + 10, r - 4, bottom - 1)
        ..close();
      c.drawPath(under, Paint()..color = look.underColor);
      final lines = Paint()
        ..color = Color.lerp(look.underColor, Colors.black, 0.25)!
        ..strokeWidth = 0.8;
      for (var x = l + 8; x < r - 6; x += look.under == Underside.tubes ? 3.2 : 4.2) {
        final y = bottom + 1 + 4 * (1 - ((x - 50) / (w / 2)).abs());
        if (look.under == Underside.spines) {
          c.drawLine(Offset(x, bottom), Offset(x, y + 2.5), lines..strokeWidth = 1.3);
        } else if (look.under == Underside.tubes) {
          c.drawCircle(Offset(x, (bottom + y) / 2), 0.55, lines);
        } else {
          c.drawLine(Offset(x, bottom), Offset(x + (50 - x) * 0.08, y), lines);
        }
      }
    }
    c.drawPath(cap, Paint()..color = look.capColor);
    c.save();
    c.clipPath(cap);
    switch (look.capMark) {
      case CapMark.shine:
        c.drawPath(
          Path()
            ..moveTo(l + 12, bottom - 18)
            ..quadraticBezierTo(42, bottom - 30, 58, bottom - 28),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round,
        );
      case CapMark.scales:
        final r = math.Random(6);
        for (var i = 0; i < 14; i++) {
          final p = Offset(l + 8 + r.nextDouble() * (w - 16), bottom - 26 + r.nextDouble() * 20);
          c.drawPath(Path()..addPolygon([p, p + const Offset(2, -2.5), p + const Offset(4, 0)], true), Paint()..color = look.capMarkColor.withValues(alpha: 0.7));
        }
      case CapMark.zones:
        final p = Paint()
          ..color = look.capMarkColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        for (final k in [0.45, 0.75]) {
          c.drawArc(Rect.fromCenter(center: Offset(50, bottom - 10), width: w * k, height: 12 * k), 0, math.pi * 2, false, p);
        }
      case CapMark.pits:
        // Стільники сморчка: ряди ямок зі зсувом через ряд.
        final r = math.Random(2);
        final p = Paint()..color = look.capMarkColor;
        var row = 0;
        for (var y = bottom - 46; y < bottom; y += 7, row++) {
          for (var x = 30.0; x < 70; x += 7) {
            final cx = x + (row.isEven ? 0 : 3.5) + r.nextDouble() * 1.5;
            c.drawOval(Rect.fromCenter(center: Offset(cx, y + r.nextDouble() * 1.5), width: 5, height: 4), p);
          }
        }
      default:
    }
    c.restore();
    c.drawPath(cap, _outline);
    if (look.capMark == CapMark.hairyRim) {
      // Волосиста бахрома по загнутому краю лійки.
      final fringe = Paint()
        ..color = look.capMarkColor
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      for (var x = l + 6; x <= r - 6; x += 3) {
        final k = ((x - 50) / (w / 2)).abs();
        final edge = Offset(x, bottom + 1 + 3 * (1 - k));
        c.drawLine(edge, edge + const Offset(0, 3), fringe);
      }
    }
    if (look.capMark == CapMark.warts) _warts(c);
  }

  void _chanterelle(Canvas c) {
    final w = look.capWidth, l = 50 - w / 2, r = 50 + w / 2;
    // Лійка, що плавно переходить у ніжку; край хвилястий.
    final body = Path()..moveTo(l, 38);
    for (var i = 0; i < 6; i++) {
      final x0 = l + w * i / 6, x1 = l + w * (i + 1) / 6;
      body.quadraticBezierTo((x0 + x1) / 2, i.isEven ? 31 : 43, x1, 38);
    }
    body
      ..cubicTo(r - 2, 52, 60, 62, 60, 72)
      ..lineTo(59, 98)
      ..quadraticBezierTo(50, 101, 41, 98)
      ..lineTo(40, 72)
      ..cubicTo(40, 62, l + 2, 52, l, 38)
      ..close();
    c.drawPath(body, Paint()..color = look.capColor);
    // Складки, що збігають на ніжку.
    final folds = Paint()
      ..color = look.underColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 7; i++) {
      final x = l + 8 + i * (w - 16) / 6;
      c.drawPath(Path()..moveTo(x, 42)..quadraticBezierTo((x + 50) / 2, 56, 50 + (x - 50) * 0.18, 66), folds);
    }
    c.drawPath(body, _outline);
  }

  void _oyster(Canvas c) {
    // Два «вушка» на короткій боковій ніжці.
    final stem = Path()
      ..moveTo(26, 98)
      ..lineTo(30, 70)
      ..lineTo(40, 72)
      ..lineTo(38, 98)
      ..close();
    c.drawPath(stem, Paint()..color = look.stemColor);
    c.drawPath(stem, _outline);
    final back = Path()
      ..moveTo(34, 74)
      ..cubicTo(30, 50, 56, 34, 76, 42)
      ..cubicTo(82, 52, 64, 68, 40, 76)
      ..close();
    c.drawPath(back, Paint()..color = Color.lerp(look.capColor, Colors.white, 0.25)!);
    c.drawPath(back, _outline);
    final ear = Path()
      ..moveTo(32, 76)
      ..cubicTo(26, 46, 70, 26, 90, 46)
      ..cubicTo(94, 60, 70, 76, 40, 80)
      ..close();
    // Пластинки під краєм.
    final gills = Path()
      ..moveTo(34, 78)
      ..quadraticBezierTo(70, 80, 88, 52)
      ..lineTo(90, 58)
      ..quadraticBezierTo(70, 84, 36, 82)
      ..close();
    c.drawPath(gills, Paint()..color = look.underColor);
    c.drawPath(ear, Paint()..color = look.capColor);
    c.drawPath(
        Path()
          ..moveTo(40, 66)
          ..quadraticBezierTo(60, 44, 82, 46),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    c.drawPath(ear, _outline);
  }

  void _puffball(Canvas c) {
    final body = Path()
      ..moveTo(40, 98)
      ..cubicTo(36, 86, 22, 78, 24, 62)
      ..cubicTo(26, 40, 74, 40, 76, 62)
      ..cubicTo(78, 78, 64, 86, 60, 98)
      ..quadraticBezierTo(50, 101, 40, 98)
      ..close();
    c.drawPath(body, Paint()..color = look.capColor);
    c.save();
    c.clipPath(body);
    _warts(c);
    c.restore();
    c.drawPath(body, _outline);
  }

  void _warts(Canvas c) {
    final r = math.Random(4);
    final p = Paint()..color = look.capMarkColor;
    for (var i = 0; i < 22; i++) {
      final a = r.nextDouble() * math.pi * 2;
      final d = r.nextDouble() * 22;
      final pos = Offset(50 + math.cos(a) * d, 58 + math.sin(a) * d * 0.7);
      if ((pos - _anchor.face).distance < 11) continue; // обличчя чисте
      c.drawCircle(pos, 1.2 + r.nextDouble() * 1.1, p);
    }
  }

  // ─── Руки ─────────────────────────────────────────────────────────────────

  void _arms(Canvas c) {
    final a = _anchor;
    final color = look.cap == CapShape.puffball || look.cap == CapShape.chanterelle ? look.capColor : look.stemColor;
    for (final (side, arm) in [(-1.0, left), (1.0, right)]) {
      final shoulder = Offset(a.face.dx + side * (a.halfW - 1), a.shoulderY);
      const l1 = 11.0, l2 = 10.0;
      final elbow = shoulder + Offset(math.sin(arm.a) * side, math.cos(arm.a)) * l1;
      final hand = elbow + Offset(math.sin(arm.a + arm.b) * side, math.cos(arm.a + arm.b)) * l2;
      final path = Path()
        ..moveTo(shoulder.dx, shoulder.dy)
        ..lineTo(elbow.dx, elbow.dy)
        ..lineTo(hand.dx, hand.dy);
      c.drawPath(path, Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
      c.drawPath(path, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
      c.drawCircle(hand, 4.2, Paint()..color = _ink);
      c.drawCircle(hand, 3, Paint()..color = color);
    }
  }

  // ─── Обличчя ──────────────────────────────────────────────────────────────

  void _face(Canvas c) {
    final f = _anchor.face;
    // Риси обличчя крупніші за ніжку — емоції видно навіть на маленькому персонажі.
    c.save();
    c.translate(f.dx, f.dy);
    c.scale(1.45);
    c.translate(-f.dx, -f.dy);
    final ink = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = _ink;
    const dx = 5.5;
    final eyeY = f.dy - 3;
    final look = face.look;
    for (final side in [-1.0, 1.0]) {
      final e = Offset(f.dx + side * dx, eyeY);
      final eyes = face.eyes == Eyes.wink && side > 0 ? Eyes.closed : (face.eyes == Eyes.wink ? Eyes.open : face.eyes);
      switch (eyes) {
        case Eyes.open:
          c.drawOval(Rect.fromCenter(center: e, width: 4.6, height: 5.6), Paint()..color = Colors.white);
          c.drawCircle(e + Offset(look.dx * 0.9, look.dy * 1.1), 1.7, fill);
          c.drawCircle(e + Offset(look.dx * 0.9 - 0.6, look.dy * 1.1 - 0.7), 0.55, Paint()..color = Colors.white);
        case Eyes.wide:
          c.drawCircle(e, 3.4, Paint()..color = Colors.white);
          c.drawCircle(e, 3.4, ink..strokeWidth = 0.8);
          c.drawCircle(e + look, 1.5, fill);
          ink.strokeWidth = 1.6;
        case Eyes.closed:
          c.drawPath(Path()..moveTo(e.dx - 2.4, e.dy)..quadraticBezierTo(e.dx, e.dy + 2, e.dx + 2.4, e.dy), ink);
        case Eyes.happy:
          c.drawPath(Path()..moveTo(e.dx - 2.4, e.dy + 1)..quadraticBezierTo(e.dx, e.dy - 2.4, e.dx + 2.4, e.dy + 1), ink);
        case Eyes.squint:
          c.drawLine(e + Offset(-2.4, -1.2 * side), e + Offset(2.4, 0), ink);
          c.drawLine(e + Offset(-2.4, 1.2 * side), e + Offset(2.4, 0), ink);
        case Eyes.sleepy:
          c.drawLine(e + const Offset(-2.4, 0), e + const Offset(2.4, 0), ink);
          c.drawPath(Path()..moveTo(e.dx - 2.4, e.dy)..quadraticBezierTo(e.dx, e.dy + 2.4, e.dx + 2.4, e.dy), fill);
        case Eyes.dizzy:
          c.drawLine(e + const Offset(-2, -2), e + const Offset(2, 2), ink);
          c.drawLine(e + const Offset(-2, 2), e + const Offset(2, -2), ink);
        case Eyes.wink:
      }
      if (face.brows != 0) {
        final by = eyeY - 5;
        final tilt = face.brows > 0 ? -1.2 : 1.4;
        c.drawLine(Offset(e.dx - 2.4, by + (side < 0 ? 0 : tilt)), Offset(e.dx + 2.4, by + (side < 0 ? tilt : 0)), ink);
      }
    }
    if (face.blush) {
      for (final side in [-1.0, 1.0]) {
        c.drawOval(Rect.fromCenter(center: Offset(f.dx + side * 9, f.dy + 2), width: 4.5, height: 2.4), Paint()..color = const Color(0xffff8a80).withValues(alpha: 0.7));
      }
    }
    final m = Offset(f.dx, f.dy + 4);
    switch (face.mouth) {
      case Mouth.smile:
        c.drawPath(Path()..moveTo(m.dx - 3, m.dy)..quadraticBezierTo(m.dx, m.dy + 3, m.dx + 3, m.dy), ink);
      case Mouth.grin:
        final p = Path()
          ..moveTo(m.dx - 4, m.dy - 0.5)
          ..quadraticBezierTo(m.dx, m.dy + 5.5, m.dx + 4, m.dy - 0.5)
          ..close();
        c.drawPath(p, Paint()..color = const Color(0xff7a2e2e));
        c.drawPath(p, ink..strokeWidth = 1.2);
      case Mouth.open:
        c.drawOval(Rect.fromCenter(center: m + const Offset(0, 1.2), width: 5, height: 4), Paint()..color = const Color(0xff7a2e2e));
      case Mouth.o:
        c.drawOval(Rect.fromCenter(center: m + const Offset(0, 1), width: 2.8, height: 3), Paint()..color = const Color(0xff7a2e2e));
      case Mouth.flat:
        c.drawLine(m + const Offset(-2.5, 1), m + const Offset(2.5, 1), ink);
      case Mouth.yawn:
        c.drawOval(Rect.fromCenter(center: m + const Offset(0, 1.8), width: 4.6, height: 6.4), Paint()..color = const Color(0xff7a2e2e));
      case Mouth.wavy:
        c.drawPath(
            Path()
              ..moveTo(m.dx - 3.5, m.dy + 1)
              ..quadraticBezierTo(m.dx - 1.75, m.dy - 0.6, m.dx, m.dy + 1)
              ..quadraticBezierTo(m.dx + 1.75, m.dy + 2.6, m.dx + 3.5, m.dy + 1),
            ink);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant MushroomCharacterPainter old) =>
      old.look != look || old.face != face || old.left != left || old.right != right;
}
