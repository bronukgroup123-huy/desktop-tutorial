import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_client/features/catalog/mushroom_character.dart';

/// Аватар з конструктора (ADR-021 §21.7): гриб (форма), колір шапки, обличчя, руки, капелюх,
/// річ — статичний малюнок. Каталог і замки — з сервера; тут лише як малювати кожну деталь.
/// Невідома деталь (додали на сервері, а застосунок старий) — не малюється.
typedef AvatarParts = Map<String, String?>;

const kDefaultAvatarParts = <String, String?>{
  'shape': 'bolete',
  'color': 'brown',
  'face': 'kind',
  'arms': 'down',
  'hat': null,
  'item': null,
};

const _capColors = <String, Color>{
  'brown': Color(0xff8b5a2b),
  'chestnut': Color(0xff6b3a1e),
  'red': Color(0xffd1342c),
  'orange': Color(0xffe2711d),
  'yellow': Color(0xffe8b923),
  'cream': Color(0xfff1e6c8),
  'violet': Color(0xff7e57c2),
  'gold': Color(0xffd4a017),
  'night': Color(0xff263248),
};

/// Форма гриба: вигляд і де на ньому капелюх, обличчя, плечі (одиниці 100×100 персонажа).
class _Shape {
  const _Shape(this.look, {required this.hatY, required this.hatW, required this.face, required this.shoulderY, required this.halfW});
  final CharacterLook Function(Color cap) look;
  final double hatY, hatW, shoulderY, halfW;
  final Offset face;
}

final _shapes = <String, _Shape>{
  'bolete': _Shape(
    (c) => CharacterLook(cap: CapShape.bun, capColor: c, capMark: CapMark.shine, under: Underside.tubes, underColor: const Color(0xfff1e6c8), stem: StemShape.barrel, stemColor: const Color(0xfff1e3c6), capWidth: 70),
    hatY: 28, hatW: 36, face: const Offset(50, 74.5), shoulderY: 81.5, halfW: 13,
  ),
  'amanita': _Shape(
    (c) => CharacterLook(cap: CapShape.convex, capColor: c, capMark: CapMark.warts, capMarkColor: const Color(0xffffffff), under: Underside.gills, underColor: const Color(0xfffbf6ea), stem: StemShape.slender, stemColor: const Color(0xfffbf6ea), stemMark: StemMark.ring, stemMarkColor: const Color(0xfffbf6ea), capWidth: 68),
    hatY: 37, hatW: 36, face: const Offset(50, 74.5), shoulderY: 81.5, halfW: 8,
  ),
  'chanterelle': _Shape(
    (c) => CharacterLook(cap: CapShape.chanterelle, capColor: c, under: Underside.folds, underColor: c, stem: StemShape.none, stemColor: c),
    hatY: 35, hatW: 40, face: const Offset(50, 76), shoulderY: 80, halfW: 10,
  ),
  'honey': _Shape(
    (c) => CharacterLook(cap: CapShape.convex, capColor: c, capMark: CapMark.scales, capMarkColor: const Color(0xff5a3d22), under: Underside.gills, underColor: const Color(0xffefe2c4), stem: StemShape.tall, stemColor: const Color(0xffe6d3a8), stemMark: StemMark.ring, stemMarkColor: const Color(0xfff5ecd6), capWidth: 54),
    hatY: 31, hatW: 30, face: const Offset(50, 71), shoulderY: 78, halfW: 9,
  ),
  'puffball': _Shape(
    (c) => CharacterLook(cap: CapShape.puffball, capColor: c, capMark: CapMark.warts, capMarkColor: Color.lerp(c, Colors.black, 0.15)!, under: Underside.none, underColor: c, stem: StemShape.none, stemColor: c),
    hatY: 48, hatW: 30, face: const Offset(50, 70), shoulderY: 76, halfW: 25,
  ),
  'morel': _Shape(
    (c) => CharacterLook(cap: CapShape.morel, capColor: c, capMark: CapMark.pits, capMarkColor: Color.lerp(c, Colors.black, 0.35)!, under: Underside.none, underColor: c, stem: StemShape.stout, stemColor: const Color(0xfff3e9d2)),
    hatY: 8, hatW: 18, face: const Offset(50, 74.5), shoulderY: 81.5, halfW: 12,
  ),
};

const _faces = <String, Face>{
  'kind': Face(),
  'happy': Face(eyes: Eyes.happy, mouth: Mouth.grin, blush: true),
  'sly': Face(eyes: Eyes.squint, mouth: Mouth.smile, look: Offset(0.6, 0)),
  'angry': Face(eyes: Eyes.squint, mouth: Mouth.flat, brows: -1),
  'sleepy': Face(eyes: Eyes.sleepy, mouth: Mouth.yawn),
  'surprised': Face(eyes: Eyes.wide, mouth: Mouth.o, brows: 1),
  'wink': Face(eyes: Eyes.wink, mouth: Mouth.grin),
  'dizzy': Face(eyes: Eyes.dizzy, mouth: Mouth.wavy),
};

const _arms = <String, (Arm, Arm)>{
  'down': (Arm.down, Arm.down),
  'wave': (Arm.down, Arm.up),
  'up': (Arm.up, Arm.up),
  'hips': (Arm(0.9, -1.9), Arm(0.9, -1.9)),
  'out': (Arm.out, Arm.out),
};

/// Малює аватар із конструктора в квадраті [size]: зверху лишається місце для капелюха.
class CustomAvatarPainter extends CustomPainter {
  CustomAvatarPainter(this.parts);

  final AvatarParts parts;

  static const _ink = Color(0xff3a2a1e);

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _shapes[parts['shape']] ?? _shapes['bolete']!;
    final color = _capColors[parts['color']] ?? _capColors['brown']!;
    final (left, right) = _arms[parts['arms']] ?? _arms['down']!;
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    // Персонаж — 82 % висоти, знизу; зверху — місце для капелюха.
    canvas.translate(9, 16);
    canvas.scale(0.82);
    if (parts['item'] == 'backpack') _backpack(canvas, shape);
    MushroomCharacterPainter(look: shape.look(color), face: _faces[parts['face']] ?? const Face(), left: left, right: right)
        .paint(canvas, const Size(100, 100));
    if (parts['color'] == 'gold') _sparkles(canvas, shape);
    _item(canvas, shape, parts['item']);
    _hat(canvas, shape, parts['hat']);
    canvas.restore();
  }

  Paint get _line => Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  void _fill(Canvas c, Path p, Color color) {
    c.drawPath(p, Paint()..color = color);
    c.drawPath(p, _line);
  }

  void _sparkles(Canvas c, _Shape s) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final o in [Offset(50 - s.hatW * 0.6, s.hatY + 8), Offset(50 + s.hatW * 0.5, s.hatY + 4)]) {
      c.drawPath(Path()..moveTo(o.dx, o.dy - 3)..lineTo(o.dx + 1, o.dy - 1)..lineTo(o.dx + 3, o.dy)..lineTo(o.dx + 1, o.dy + 1)..lineTo(o.dx, o.dy + 3)..lineTo(o.dx - 1, o.dy + 1)..lineTo(o.dx - 3, o.dy)..lineTo(o.dx - 1, o.dy - 1)..close(), p);
    }
  }

  // ─── Капелюхи ─────────────────────────────────────────────────────────────

  void _hat(Canvas c, _Shape s, String? id) {
    final y = s.hatY, w = s.hatW;
    switch (id) {
      case 'cap':
        _fill(c, Path()..moveTo(50 - w * 0.42, y + 2)..cubicTo(50 - w * 0.42, y - 12, 50 + w * 0.42, y - 12, 50 + w * 0.42, y + 2)..close(), const Color(0xff2e7d32));
        _fill(c, Path()..moveTo(50 + w * 0.1, y + 2)..quadraticBezierTo(50 + w * 0.6, y - 1, 50 + w * 0.75, y + 3)..lineTo(50 + w * 0.1, y + 4)..close(), const Color(0xff1b5e20));
        c.drawCircle(Offset(50, y - 8.5), 1.6, Paint()..color = _ink);
      case 'straw':
        _fill(c, Path()..addOval(Rect.fromCenter(center: Offset(50, y + 1), width: w * 1.5, height: 7)), const Color(0xffe9c46a));
        _fill(c, Path()..moveTo(50 - w * 0.32, y)..quadraticBezierTo(50 - w * 0.3, y - 12, 50, y - 12)..quadraticBezierTo(50 + w * 0.3, y - 12, 50 + w * 0.32, y)..close(), const Color(0xffe9c46a));
        c.drawLine(Offset(50 - w * 0.31, y - 3), Offset(50 + w * 0.31, y - 3), Paint()..color = const Color(0xffc0392b)..strokeWidth = 2.6);
      case 'beanie':
        _fill(c, Path()..moveTo(50 - w * 0.4, y + 2)..cubicTo(50 - w * 0.4, y - 15, 50 + w * 0.4, y - 15, 50 + w * 0.4, y + 2)..close(), const Color(0xff1e88e5));
        _fill(c, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(50, y + 1), width: w * 0.86, height: 5), const Radius.circular(2.5))), const Color(0xff1565c0));
        _fill(c, Path()..addOval(Rect.fromCircle(center: Offset(50, y - 12), radius: 3.4)), Colors.white);
      case 'ranger':
        _fill(c, Path()..addOval(Rect.fromCenter(center: Offset(50, y + 1), width: w * 1.45, height: 6)), const Color(0xff556b2f));
        _fill(c, Path()..moveTo(50 - w * 0.3, y)..lineTo(50 - w * 0.26, y - 11)..quadraticBezierTo(50, y - 15, 50 + w * 0.26, y - 11)..lineTo(50 + w * 0.3, y)..close(), const Color(0xff6b8e23));
        c.drawLine(Offset(50 - w * 0.29, y - 3), Offset(50 + w * 0.29, y - 3), Paint()..color = const Color(0xff3e2723)..strokeWidth = 2.4);
      case 'wizard':
        _fill(c, Path()..addOval(Rect.fromCenter(center: Offset(50, y + 1), width: w * 1.3, height: 6)), const Color(0xff5e35b1));
        _fill(c, Path()..moveTo(50 - w * 0.3, y)..quadraticBezierTo(50, y - 10, 54, y - 22)..quadraticBezierTo(52, y - 8, 50 + w * 0.3, y)..close(), const Color(0xff7e57c2));
        for (final o in [Offset(47, y - 5), Offset(52, y - 12)]) {
          c.drawCircle(o, 1.3, Paint()..color = const Color(0xffffd54f));
        }
      case 'crown':
        _fill(
          c,
          Path()
            ..moveTo(50 - w * 0.36, y + 1)
            ..lineTo(50 - w * 0.4, y - 9)
            ..lineTo(50 - w * 0.2, y - 3)
            ..lineTo(50, y - 12)
            ..lineTo(50 + w * 0.2, y - 3)
            ..lineTo(50 + w * 0.4, y - 9)
            ..lineTo(50 + w * 0.36, y + 1)
            ..close(),
          const Color(0xffffc107),
        );
        for (final x in [-0.2, 0.0, 0.2]) {
          c.drawCircle(Offset(50 + w * x, y - 2), 1.4, Paint()..color = const Color(0xffd32f2f));
        }
      case 'santa':
        _fill(c, Path()..moveTo(50 - w * 0.36, y + 1)..quadraticBezierTo(48, y - 16, 62, y - 14)..quadraticBezierTo(56, y - 6, 50 + w * 0.36, y + 1)..close(), const Color(0xffd32f2f));
        _fill(c, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(50, y + 1), width: w * 0.86, height: 5), const Radius.circular(2.5))), Colors.white);
        _fill(c, Path()..addOval(Rect.fromCircle(center: Offset(63, y - 14), radius: 3.2)), Colors.white);
      case 'pumpkin':
        _fill(c, Path()..addOval(Rect.fromCenter(center: Offset(50, y - 5), width: w * 0.7, height: 12)), const Color(0xffef6c00));
        c.drawLine(Offset(50, y - 11), Offset(50, y + 1), _line..strokeWidth = 1.2);
        _fill(c, Path()..moveTo(49, y - 11)..lineTo(50, y - 15)..lineTo(52, y - 14)..lineTo(51, y - 11)..close(), const Color(0xff558b2f));
      default:
    }
  }

  // ─── Речі ─────────────────────────────────────────────────────────────────

  void _item(Canvas c, _Shape s, String? id) {
    final f = s.face;
    switch (id) {
      case 'glasses':
        final p = _line..strokeWidth = 1.6;
        c.drawCircle(Offset(f.dx - 6, f.dy - 3), 4.4, p);
        c.drawCircle(Offset(f.dx + 6, f.dy - 3), 4.4, p);
        c.drawLine(Offset(f.dx - 1.6, f.dy - 3.5), Offset(f.dx + 1.6, f.dy - 3.5), p);
      case 'scarf':
        final y = s.shoulderY - 1;
        _fill(c, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(f.dx - s.halfW - 3, y - 3, f.dx + s.halfW + 3, y + 3), const Radius.circular(3))), const Color(0xffc62828));
        _fill(c, Path()..moveTo(f.dx + s.halfW - 4, y + 2)..lineTo(f.dx + s.halfW + 1, y + 14)..lineTo(f.dx + s.halfW + 5, y + 12)..lineTo(f.dx + s.halfW + 2, y + 2)..close(), const Color(0xffb71c1c));
      case 'bowtie':
        final y = s.shoulderY - 1;
        _fill(c, Path()..moveTo(f.dx, y)..lineTo(f.dx - 6, y - 4)..lineTo(f.dx - 6, y + 4)..close(), const Color(0xff1565c0));
        _fill(c, Path()..moveTo(f.dx, y)..lineTo(f.dx + 6, y - 4)..lineTo(f.dx + 6, y + 4)..close(), const Color(0xff1565c0));
      case 'medal':
        final y = s.shoulderY + 5;
        c.drawLine(Offset(f.dx - 3, s.shoulderY - 2), Offset(f.dx, y - 3), Paint()..color = const Color(0xff1565c0)..strokeWidth = 2);
        c.drawLine(Offset(f.dx + 3, s.shoulderY - 2), Offset(f.dx, y - 3), Paint()..color = const Color(0xffffd54f)..strokeWidth = 2);
        _fill(c, Path()..addOval(Rect.fromCircle(center: Offset(f.dx, y), radius: 3.6)), const Color(0xffffc107));
      case 'boots':
        for (final side in [-1.0, 1.0]) {
          final x = 50 + side * 7;
          _fill(c, Path()..moveTo(x - 4, 90)..lineTo(x - 4, 98)..lineTo(x + 4 + side * 3, 98)..lineTo(x + 4 + side * 3, 95)..lineTo(x + 4, 94)..lineTo(x + 4, 90)..close(), const Color(0xff2e7d32));
        }
      case 'basket':
        const o = Offset(82, 86);
        c.drawArc(Rect.fromCenter(center: o, width: 14, height: 14), math.pi, math.pi, false, _line..strokeWidth = 1.8);
        _fill(c, Path()..moveTo(o.dx - 8, o.dy)..lineTo(o.dx + 8, o.dy)..lineTo(o.dx + 6, o.dy + 9)..lineTo(o.dx - 6, o.dy + 9)..close(), const Color(0xffbc8a5f));
        c.drawCircle(Offset(o.dx - 2, o.dy - 1.5), 3, Paint()..color = const Color(0xff8b5a2b));
      case 'flower':
        final o = Offset(50 + s.hatW * 0.55, s.hatY + 6);
        for (var i = 0; i < 5; i++) {
          final a = i * 2 * math.pi / 5;
          c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * 2.6, 2, Paint()..color = const Color(0xfff48fb1));
        }
        c.drawCircle(o, 1.6, Paint()..color = const Color(0xffffeb3b));
      case 'lantern':
        const o = Offset(17, 84);
        c.drawCircle(o, 9, Paint()..color = const Color(0xffffe082).withValues(alpha: 0.35));
        _fill(c, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 7, height: 10), const Radius.circular(2))), const Color(0xffffca28));
        c.drawLine(o - const Offset(0, 5), o - const Offset(0, 8), _line);
      default:
    }
  }

  void _backpack(Canvas c, _Shape s) {
    final x = s.face.dx + s.halfW + 2;
    _fill(c, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x - 4, s.shoulderY - 4, x + 9, s.shoulderY + 14), const Radius.circular(3))), const Color(0xff795548));
  }

  @override
  bool shouldRepaint(covariant CustomAvatarPainter old) => !_same(old.parts, parts);

  static bool _same(AvatarParts a, AvatarParts b) => a.length == b.length && a.keys.every((k) => a[k] == b[k]);
}
