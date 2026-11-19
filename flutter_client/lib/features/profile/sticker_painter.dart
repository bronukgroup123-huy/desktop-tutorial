import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Грибна наліпка (ADR-021 §21.7): білий вирізний контур, об'ємна шапка, велика емоція, пухкі
/// руки. Персонаж ([StickerSpec]) + деталі поверх (капелюх, річ, ефект). Усе — код, без картинок;
/// невідома деталь не малюється. Малюнок сам вписується в квадрат (капелюх чи хмаринка не
/// обрізаються).

enum SBody { round, potato, tall, puff, chanterelle, cluster }

enum SCap { dome, spotted, flat, cone, morel, none, funnel, parasol, bell }

enum SEyes { normal, happy, squeeze, spiral, hearts, crying, shades, angry, sleepy, wink, scared, sly, stars }

enum SMouth { smile, laugh, shout, o, wavy, smirk, frown, tongue }

enum SArms { down, wave, hips, head, up, cheeks, out }

/// Ефекти, намальовані в самому персонажі.
enum SFx { blush, sweat, vein, sparkle, hearts, zzz, tears }

/// Особливий візерунок шапки (Pro та рідкісні персонажі).
enum CapPattern { auto, stars, stripes, polka, snow, gold }

class StickerSpec {
  const StickerSpec({
    required this.body,
    required this.cap,
    required this.capColor,
    this.bodyColor = const Color(0xfff4ead6),
    this.eyes = SEyes.normal,
    this.mouth = SMouth.smile,
    this.arms = SArms.down,
    this.fx = const {},
    this.tilt = 0,
    this.pattern = CapPattern.auto,
    this.spotColor = const Color(0xfffffbf2),
    this.glow,
    this.side = const [(SEyes.happy, SMouth.laugh), (SEyes.wink, SMouth.smile)],
  });

  final SBody body;
  final SCap cap;
  final Color capColor;
  final Color bodyColor;
  final SEyes eyes;
  final SMouth mouth;
  final SArms arms;
  final Set<SFx> fx;
  final double tilt;
  final CapPattern pattern;
  final Color spotColor;

  /// Сяйво навколо наліпки (світні гриби).
  final Color? glow;

  /// Емоції двох задніх грибів у гроні ([SBody.cluster]).
  final List<(SEyes, SMouth)> side;
}

/// Деталі поверх персонажа (id із серверного каталогу).
class StickerExtras {
  const StickerExtras({this.hat, this.item, this.fx});
  final String? hat, item, fx;

  @override
  bool operator ==(Object other) => other is StickerExtras && other.hat == hat && other.item == item && other.fx == fx;

  @override
  int get hashCode => Object.hash(hat, item, fx);
}

const _ink = Color(0xff2b1d14);
const _faceScale = 1.18;

Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _darken(Color c, double t) => Color.lerp(c, const Color(0xff1a0f08), t)!;

class StickerPainter extends CustomPainter {
  StickerPainter(this.spec, [this.extras = const StickerExtras()]);

  final StickerSpec spec;
  final StickerExtras extras;

  @override
  void paint(Canvas canvas, Size size) {
    final s = spec;
    final figures = <_Figure>[];
    if (s.body == SBody.cluster) {
      final side = [
        (const Offset(-28, -11), 0.66, s.side[0]),
        (const Offset(28, -15), 0.70, s.side[1]),
      ];
      for (final (o, k, (e, m)) in side) {
        figures.add(_Figure(
          StickerSpec(body: SBody.tall, cap: s.cap, capColor: _darken(s.capColor, 0.12), bodyColor: s.bodyColor, eyes: e, mouth: m),
          offset: o,
          scale: k,
        ));
      }
      figures.add(_Figure(
        StickerSpec(body: SBody.tall, cap: s.cap, capColor: s.capColor, bodyColor: s.bodyColor, eyes: s.eyes, mouth: s.mouth, arms: s.arms, fx: s.fx),
        offset: const Offset(0, 8),
        scale: 0.88,
      ));
    } else {
      figures.add(_Figure(s));
    }
    final main = figures.last;
    final details = _Details(main, extras);

    // Вписати в квадрат 120×120 з полем.
    var bounds = figures.map((f) => f.bounds()).reduce((a, b) => a.expandToInclude(b));
    final db = details.measure();
    if (db != null) bounds = bounds.expandToInclude(main.toOuter(db));
    final span = math.max(bounds.width, bounds.height) * (1 + s.tilt.abs() * 0.5);
    final k = math.min(1.12, 112 / span);

    canvas.save();
    canvas.scale(size.width / 120, size.height / 120);
    canvas.translate(60, 60);
    canvas.scale(k);
    canvas.rotate(s.tilt);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    if (s.glow != null) {
      final g = Paint()
        ..color = s.glow!.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
      for (final f in figures) {
        f.silhouette(canvas, g, g);
      }
    }
    // Тінь, потім білий контур — для всього разом (персонаж + деталі).
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.save();
    canvas.translate(1.5, 3);
    for (final f in figures) {
      f.silhouette(canvas, shadow, shadow);
    }
    details.silhouette(canvas, shadow);
    canvas.restore();
    final white = Paint()..color = Colors.white;
    for (final f in figures) {
      f.silhouette(canvas, white, white);
    }
    details.silhouette(canvas, white);

    for (final f in figures) {
      if (f == main) details.paint(canvas, behind: true);
      f.paint(canvas);
    }
    details.paint(canvas, behind: false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StickerPainter old) => old.spec != spec || old.extras != extras;
}

class _Arm {
  _Arm(this.from, this.mid, this.to);
  final Offset from, mid, to;
  Path get path => Path()
    ..moveTo(from.dx, from.dy)
    ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);
}

class _Figure {
  _Figure(this.s, {this.offset = Offset.zero, this.scale = 1}) {
    _build();
  }

  final StickerSpec s;
  final Offset offset;
  final double scale;

  late Path body, cap;
  Path? under;
  late Rect bodyBox, capBox;
  late Offset face;
  final arms = <_Arm>[];
  final feet = <Rect>[];

  static const cx = 60.0;

  // ─── Перетворення фігури (гроно: малі гриби позаду) ─────────────────────────

  Offset toOuterPoint(Offset p) => Offset(60 + offset.dx, 62 + offset.dy) + (p - const Offset(60, 62)) * scale;
  Rect toOuter(Rect r) => Rect.fromPoints(toOuterPoint(r.topLeft), toOuterPoint(r.bottomRight));

  void _apply(Canvas c, void Function() draw) {
    c.save();
    c.translate(60 + offset.dx, 62 + offset.dy);
    c.scale(scale);
    c.translate(-60, -62);
    draw();
    c.restore();
  }

  /// Межі разом з руками, ефектами й білим контуром — для вписування.
  Rect bounds() {
    var r = body.getBounds().expandToInclude(cap.getBounds());
    for (final f in feet) {
      r = r.expandToInclude(f);
    }
    for (final a in arms) {
      r = r.expandToInclude(a.path.getBounds().inflate(8));
    }
    if (s.fx.contains(SFx.zzz) || s.fx.contains(SFx.hearts)) r = r.expandToInclude(Rect.fromLTWH(top.dx + 14, topY - 12, 26, 20));
    if (s.fx.contains(SFx.sparkle)) r = r.expandToInclude(r.inflate(3));
    return toOuter(r.inflate(5));
  }

  /// Верх гриба (центр, y) — для капелюха.
  Offset get top => s.cap == SCap.none ? Offset(bodyBox.center.dx, bodyBox.top) : Offset(capBox.center.dx, capBox.top);
  double get topY => top.dy;
  double get topWidth => s.cap == SCap.none ? bodyBox.width * 0.8 : capBox.width;
  Rect get headBox => s.cap == SCap.none ? bodyBox : capBox;

  /// Очі (з урахуванням збільшення обличчя).
  Offset eye(double side) => face + Offset(side * 8, -3) * _faceScale;
  double get chestY => math.min(face.dy + 18, bodyBox.bottom - 7);

  void _build() {
    switch (s.body) {
      case SBody.round:
        bodyBox = Rect.fromCenter(center: const Offset(cx, 80), width: 54, height: 50);
        body = Path()..addOval(bodyBox);
        face = const Offset(cx, 82);
        feet.addAll([Rect.fromCenter(center: const Offset(cx - 12, 105), width: 14, height: 8), Rect.fromCenter(center: const Offset(cx + 12, 105), width: 14, height: 8)]);
      case SBody.potato:
        bodyBox = Rect.fromCenter(center: const Offset(cx, 86), width: 66, height: 40);
        body = Path()
          ..moveTo(cx - 30, 74)
          ..cubicTo(cx - 40, 96, cx - 20, 108, cx, 106)
          ..cubicTo(cx + 24, 108, cx + 38, 96, cx + 31, 74)
          ..quadraticBezierTo(cx, 64, cx - 30, 74)
          ..close();
        face = const Offset(cx, 87);
        feet.addAll([Rect.fromCenter(center: const Offset(cx - 14, 108), width: 13, height: 7), Rect.fromCenter(center: const Offset(cx + 14, 108), width: 13, height: 7)]);
      case SBody.tall:
      case SBody.cluster:
        bodyBox = const Rect.fromLTRB(cx - 18, 52, cx + 18, 108);
        body = Path()
          ..moveTo(cx - 13, 54)
          ..cubicTo(cx - 20, 72, cx - 22, 96, cx - 17, 106)
          ..quadraticBezierTo(cx, 112, cx + 17, 106)
          ..cubicTo(cx + 22, 96, cx + 20, 72, cx + 13, 54)
          ..close();
        face = const Offset(cx, 80);
      case SBody.puff:
        bodyBox = Rect.fromCenter(center: const Offset(cx, 76), width: 64, height: 60);
        body = Path()
          ..moveTo(cx - 20, 104)
          ..cubicTo(cx - 38, 100, cx - 36, 52, cx, 46)
          ..cubicTo(cx + 36, 52, cx + 38, 100, cx + 20, 104)
          ..quadraticBezierTo(cx, 109, cx - 20, 104)
          ..close();
        face = const Offset(cx, 82);
      case SBody.chanterelle:
        bodyBox = const Rect.fromLTRB(cx - 16, 56, cx + 16, 108);
        body = Path()
          ..moveTo(cx - 24, 58)
          ..cubicTo(cx - 12, 70, cx - 14, 92, cx - 13, 106)
          ..quadraticBezierTo(cx, 111, cx + 13, 106)
          ..cubicTo(cx + 14, 92, cx + 12, 70, cx + 24, 58)
          ..close();
        face = const Offset(cx, 85);
    }
    _buildCap();
    _buildArms();
  }

  Path _underside(double halfW, double top) => Path()
    ..moveTo(cx - halfW, top)
    ..quadraticBezierTo(cx, top + 12, cx + halfW, top)
    ..quadraticBezierTo(cx, top + 6, cx - halfW, top)
    ..close();

  void _buildCap() {
    final top = switch (s.body) { SBody.potato => 72.0, _ => s.body == SBody.round || s.body == SBody.chanterelle ? 60.0 : 56.0 };
    switch (s.cap) {
      case SCap.dome:
        capBox = Rect.fromLTRB(cx - 40, top - 42, cx + 40, top + 6);
        cap = Path()
          ..moveTo(cx - 40, top + 2)
          ..cubicTo(cx - 44, top - 52, cx + 44, top - 52, cx + 40, top + 2)
          ..quadraticBezierTo(cx, top + 12, cx - 40, top + 2)
          ..close();
        under = _underside(34, top + 2);
      case SCap.spotted:
        capBox = Rect.fromLTRB(cx - 44, top - 34, cx + 44, top + 6);
        cap = Path()
          ..moveTo(cx - 44, top + 4)
          ..cubicTo(cx - 44, top - 38, cx + 44, top - 38, cx + 44, top + 4)
          ..quadraticBezierTo(cx, top + 12, cx - 44, top + 4)
          ..close();
        under = _underside(38, top + 4);
      case SCap.flat:
        capBox = Rect.fromLTRB(cx - 36, top - 22, cx + 36, top + 6);
        cap = Path()
          ..moveTo(cx - 36, top + 4)
          ..cubicTo(cx - 40, top - 14, cx - 20, top - 22, cx, top - 20)
          ..cubicTo(cx + 20, top - 22, cx + 40, top - 14, cx + 36, top + 4)
          ..quadraticBezierTo(cx, top + 10, cx - 36, top + 4)
          ..close();
        under = _underside(31, top + 4);
      case SCap.cone:
        capBox = Rect.fromLTRB(cx - 28, top - 50, cx + 28, top + 6);
        cap = Path()
          ..moveTo(cx - 28, top + 4)
          ..cubicTo(cx - 26, top - 20, cx - 8, top - 48, cx, top - 50)
          ..cubicTo(cx + 8, top - 48, cx + 26, top - 20, cx + 28, top + 4)
          ..quadraticBezierTo(cx, top + 10, cx - 28, top + 4)
          ..close();
      case SCap.morel:
        capBox = Rect.fromLTRB(cx - 24, top - 52, cx + 24, top + 6);
        cap = Path()
          ..moveTo(cx - 20, top + 4)
          ..cubicTo(cx - 32, top - 26, cx - 14, top - 54, cx, top - 52)
          ..cubicTo(cx + 14, top - 54, cx + 32, top - 26, cx + 20, top + 4)
          ..quadraticBezierTo(cx, top + 9, cx - 20, top + 4)
          ..close();
      case SCap.funnel:
        // Лисичка: хвиляста лійка, що переходить у тіло.
        capBox = Rect.fromLTRB(cx - 42, top - 26, cx + 42, top + 6);
        final p = Path()..moveTo(cx - 42, top - 14);
        const waves = 6;
        for (var i = 0; i < waves; i++) {
          final x0 = cx - 42 + i * 84 / waves, x1 = x0 + 84 / waves;
          p.quadraticBezierTo((x0 + x1) / 2, top - (i.isEven ? 26 : 18), x1, top - 14);
        }
        p
          ..cubicTo(cx + 40, top - 2, cx + 26, top + 4, cx + 18, top + 6)
          ..quadraticBezierTo(cx, top + 10, cx - 18, top + 6)
          ..cubicTo(cx - 26, top + 4, cx - 40, top - 2, cx - 42, top - 14)
          ..close();
        cap = p;
      case SCap.parasol:
        // Парасолька: широка пласка шапка з горбиком посередині.
        capBox = Rect.fromLTRB(cx - 48, top - 30, cx + 48, top + 6);
        cap = Path()
          ..moveTo(cx - 48, top + 3)
          ..cubicTo(cx - 44, top - 12, cx - 20, top - 20, cx - 9, top - 22)
          ..cubicTo(cx - 6, top - 31, cx + 6, top - 31, cx + 9, top - 22)
          ..cubicTo(cx + 20, top - 20, cx + 44, top - 12, cx + 48, top + 3)
          ..quadraticBezierTo(cx, top + 10, cx - 48, top + 3)
          ..close();
        under = _underside(42, top + 3);
      case SCap.bell:
        // Гнойовик: високий дзвін з волохатими лусочками й рваним краєм.
        capBox = Rect.fromLTRB(cx - 30, top - 46, cx + 30, top + 8);
        final p = Path()
          ..moveTo(cx - 30, top + 6)
          ..cubicTo(cx - 32, top - 30, cx - 18, top - 46, cx, top - 46)
          ..cubicTo(cx + 18, top - 46, cx + 32, top - 30, cx + 30, top + 6);
        for (var i = 0; i < 6; i++) {
          final x1 = cx + 30 - (i + 1) * 10;
          p.quadraticBezierTo(x1 + 5, top + (i.isEven ? 1 : 10), x1, top + 6);
        }
        cap = p..close();
      case SCap.none:
        capBox = Rect.zero;
        cap = Path();
    }
  }

  void _buildArms() {
    final b = bodyBox;
    final y = face.dy + 8;
    final l = Offset(b.left + 4, y), r = Offset(b.right - 4, y);
    switch (s.arms) {
      case SArms.down:
        arms.addAll([_Arm(l, l + const Offset(-8, 8), l + const Offset(-6, 18)), _Arm(r, r + const Offset(8, 8), r + const Offset(6, 18))]);
      case SArms.wave:
        arms.addAll([_Arm(l, l + const Offset(-8, 8), l + const Offset(-6, 18)), _Arm(r, r + const Offset(14, -2), r + const Offset(16, -18))]);
      case SArms.hips:
        arms.addAll([_Arm(l, l + const Offset(-12, 4), l + const Offset(-1, 12)), _Arm(r, r + const Offset(12, 4), r + const Offset(1, 12))]);
      case SArms.head:
        arms.addAll([_Arm(l, l + const Offset(-14, -8), Offset(face.dx - 16, face.dy - 24)), _Arm(r, r + const Offset(14, -8), Offset(face.dx + 16, face.dy - 24))]);
      case SArms.up:
        arms.addAll([_Arm(l, l + const Offset(-12, -6), l + const Offset(-14, -22)), _Arm(r, r + const Offset(12, -6), r + const Offset(14, -22))]);
      case SArms.cheeks:
        arms.addAll([_Arm(l, l + const Offset(-10, 0), Offset(face.dx - 14, face.dy + 4)), _Arm(r, r + const Offset(10, 0), Offset(face.dx + 14, face.dy + 4))]);
      case SArms.out:
        arms.addAll([_Arm(l, l + const Offset(-10, -2), l + const Offset(-20, -4)), _Arm(r, r + const Offset(10, -2), r + const Offset(20, -4))]);
    }
  }

  /// Силует фігури (для тіні, білого контуру, сяйва).
  void silhouette(Canvas canvas, Paint fill, Paint strokeBase) => _apply(canvas, () {
        final stroke = Paint()
          ..color = strokeBase.color
          ..maskFilter = strokeBase.maskFilter
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;
        for (final p in [body, cap]) {
          canvas.drawPath(p, fill);
          canvas.drawPath(p, stroke);
        }
        for (final f in feet) {
          canvas.drawOval(f, fill);
          canvas.drawOval(f, stroke);
        }
        final arm = Paint()
          ..color = strokeBase.color
          ..maskFilter = strokeBase.maskFilter
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round;
        for (final a in arms) {
          canvas.drawPath(a.path, arm);
        }
      });

  void paint(Canvas canvas) => _apply(canvas, () {
        _paintFeet(canvas);
        _paintArms(canvas, behind: true);
        _paintBody(canvas);
        _paintCap(canvas);
        _paintFace(canvas);
        _paintArms(canvas, behind: false);
        _paintFx(canvas);
      });

  /// Малювати деталі в координатах цієї фігури.
  void within(Canvas canvas, void Function() draw) => _apply(canvas, draw);

  Paint _outline(Color c) => Paint()
    ..color = _darken(c, 0.5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeJoin = StrokeJoin.round;

  void _paintFeet(Canvas c) {
    for (final f in feet) {
      c.drawOval(f, Paint()..color = _darken(s.bodyColor, 0.18));
      c.drawOval(f, _outline(s.bodyColor));
    }
  }

  void _paintArms(Canvas c, {required bool behind}) {
    // Руки, що лягають на тіло (щоки, голова, боки), — поверх; інші — за тілом.
    final over = s.arms == SArms.cheeks || s.arms == SArms.head || s.arms == SArms.hips;
    if (behind == over) return;
    for (final a in arms) {
      c.drawPath(a.path, Paint()
        ..color = _darken(s.bodyColor, 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.6
        ..strokeCap = StrokeCap.round);
      c.drawPath(a.path, Paint()
        ..color = _darken(s.bodyColor, 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.6
        ..strokeCap = StrokeCap.round);
    }
  }

  void _paintBody(Canvas c) {
    final b = bodyBox;
    final base = s.body == SBody.puff ? s.capColor : s.bodyColor;
    c.drawPath(body, Paint()..shader = ui.Gradient.linear(b.centerLeft, b.centerRight, [_lighten(base, 0.35), base, _darken(base, 0.14)], [0, 0.45, 1]));
    c.save();
    c.clipPath(body);
    if (s.cap != SCap.none) {
      c.drawOval(Rect.fromCenter(center: Offset(b.center.dx, b.top + 2), width: b.width * 1.2, height: 16), Paint()
        ..color = _darken(base, 0.35).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    if (s.body == SBody.puff) {
      final r = math.Random(4);
      for (var i = 0; i < 22; i++) {
        final p = Offset(b.left + 8 + r.nextDouble() * (b.width - 16), b.top + 4 + r.nextDouble() * 22);
        c.drawCircle(p, 1.2 + r.nextDouble() * 1.6, Paint()..color = _darken(base, 0.14));
        c.drawCircle(p - const Offset(0.5, 0.5), 0.6, Paint()..color = Colors.white.withValues(alpha: 0.7));
      }
      c.drawOval(Rect.fromCenter(center: Offset(b.left + b.width * 0.32, b.top + 14), width: 16, height: 9), Paint()..color = Colors.white.withValues(alpha: 0.45));
    }
    c.restore();
    c.drawPath(body, _outline(base));
  }

  void _paintCap(Canvas c) {
    if (s.cap == SCap.none) return;
    final b = capBox;
    final col = s.capColor;
    if (under != null) {
      c.drawPath(under!, Paint()..color = _lighten(s.bodyColor, 0.1));
      c.save();
      c.clipPath(under!);
      final gill = Paint()
        ..color = _darken(s.bodyColor, 0.22)
        ..strokeWidth = 0.8;
      for (var x = b.left; x < b.right; x += 3) {
        c.drawLine(Offset(x, b.bottom - 8), Offset(b.center.dx + (x - b.center.dx) * 0.7, b.bottom + 8), gill);
      }
      c.restore();
    }
    if (s.pattern == CapPattern.stripes) {
      c.drawPath(cap, Paint()..color = col);
    } else {
      c.drawPath(cap, Paint()
        ..shader = ui.Gradient.radial(Offset(b.left + b.width * 0.36, b.top + b.height * 0.32), b.width * 0.75, [_lighten(col, 0.4), col, _darken(col, 0.28)], [0, 0.5, 1]));
    }
    c.save();
    c.clipPath(cap);
    _capTexture(c, b, col);
    _capPattern(c, b, col);
    c.drawOval(Rect.fromCenter(center: Offset(b.left + b.width * 0.3, b.top + b.height * 0.28), width: b.width * 0.22, height: b.height * 0.16),
        Paint()..color = Colors.white.withValues(alpha: 0.5));
    c.drawCircle(Offset(b.left + b.width * 0.45, b.top + b.height * 0.2), 1.6, Paint()..color = Colors.white.withValues(alpha: 0.75));
    c.restore();
    c.drawPath(cap, _outline(s.pattern == CapPattern.stripes ? const Color(0xff7e57c2) : col));
  }

  void _capTexture(Canvas c, Rect b, Color col) {
    final r = math.Random(col.toARGB32() & 0xff);
    switch (s.cap) {
      case SCap.spotted:
        for (final (dx, dy, rad) in [(-0.3, 0.38, 6.5), (0.06, 0.22, 5.0), (0.32, 0.45, 7.0), (-0.08, 0.62, 4.0), (0.18, 0.72, 3.5), (-0.4, 0.7, 3.8), (0.44, 0.75, 3.2), (-0.18, 0.18, 3.0)]) {
          final p = Offset(b.center.dx + dx * b.width, b.top + dy * b.height);
          c.drawOval(Rect.fromCenter(center: p, width: rad * 2, height: rad * 1.6), Paint()..color = s.spotColor);
          c.drawOval(Rect.fromCenter(center: p + Offset(0, rad * 0.25), width: rad * 2, height: rad * 1.6), Paint()
            ..color = _darken(s.spotColor, 0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9);
        }
      case SCap.dome:
        if (s.pattern != CapPattern.auto) return;
        for (var i = 0; i < 16; i++) {
          final p = Offset(b.left + 10 + r.nextDouble() * (b.width - 20), b.top + 12 + r.nextDouble() * (b.height - 20));
          c.drawCircle(p, 0.9 + r.nextDouble(), Paint()..color = _darken(col, 0.25).withValues(alpha: 0.55));
        }
      case SCap.morel:
        final pit = Paint()..color = _darken(col, 0.4);
        var row = 0;
        for (var y = b.top + 6; y < b.bottom - 2; y += 7, row++) {
          for (var x = b.left + (row.isEven ? 4 : 7.5); x < b.right - 2; x += 7) {
            c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 5, height: 4.4), pit);
          }
        }
      case SCap.cone:
        final line = Paint()
          ..color = _darken(col, 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        for (final k in [-0.25, 0.0, 0.25]) {
          c.drawLine(Offset(b.center.dx + k * 10, b.top + 6), Offset(b.center.dx + k * b.width * 0.8, b.bottom), line);
        }
      case SCap.funnel:
        final fold = Paint()
          ..color = _darken(col, 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1;
        for (var i = -3; i <= 3; i++) {
          c.drawLine(Offset(b.center.dx + i * 9, b.top + 10), Offset(b.center.dx + i * 3, b.bottom + 4), fold);
        }
      case SCap.parasol:
        // Темний горбик і лусочки кільцями.
        c.drawOval(Rect.fromCenter(center: Offset(b.center.dx, b.top + 7), width: 20, height: 12), Paint()..color = _darken(col, 0.45));
        final scale = Paint()..color = _darken(col, 0.32);
        for (var ring = 0; ring < 3; ring++) {
          final n = 6 + ring * 3;
          for (var i = 0; i < n; i++) {
            final t = (i + 0.5) / n;
            final x = b.left + 8 + t * (b.width - 16);
            final y = b.top + 13 + ring * 6 + (x - b.center.dx).abs() * 0.18;
            c.drawPath(Path()..moveTo(x - 2.4, y)..lineTo(x + 2.4, y)..lineTo(x, y + 2.6)..close(), scale);
          }
        }
      case SCap.bell:
        final shag = Paint()
          ..color = _darken(col, 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round;
        for (var row = 0; row < 5; row++) {
          for (var i = 0; i < 5 + row; i++) {
            final x = b.left + 10 + (i + (row.isEven ? 0.5 : 0)) * (b.width - 20) / (5 + row);
            final y = b.top + 12 + row * 8;
            c.drawPath(Path()..moveTo(x - 2.5, y)..quadraticBezierTo(x, y + 3.5, x + 2.5, y), shag);
          }
        }
      default:
    }
  }

  void _capPattern(Canvas c, Rect b, Color col) {
    switch (s.pattern) {
      case CapPattern.stars:
        final r = math.Random(7);
        for (var i = 0; i < 26; i++) {
          final p = Offset(b.left + r.nextDouble() * b.width, b.top + r.nextDouble() * b.height);
          c.drawCircle(p, 0.5 + r.nextDouble() * 0.9, Paint()..color = Colors.white.withValues(alpha: 0.5 + r.nextDouble() * 0.5));
        }
        for (final (dx, dy, rr) in [(-0.22, 0.4, 3.6), (0.2, 0.3, 2.8), (0.05, 0.62, 2.4), (0.32, 0.62, 2.0)]) {
          _star4(c, Offset(b.center.dx + dx * b.width, b.top + dy * b.height), rr, const Color(0xfffff59d));
        }
        // Туманність.
        c.drawOval(Rect.fromCenter(center: Offset(b.center.dx + b.width * 0.15, b.top + b.height * 0.5), width: b.width * 0.5, height: b.height * 0.3),
            Paint()
              ..color = const Color(0xffce93d8).withValues(alpha: 0.35)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      case CapPattern.stripes:
        const colors = [Color(0xffef5350), Color(0xffffa726), Color(0xffffee58), Color(0xff66bb6a), Color(0xff42a5f5), Color(0xffab47bc)];
        final h = b.height / colors.length;
        for (var i = 0; i < colors.length; i++) {
          c.drawRect(Rect.fromLTWH(b.left - 4, b.top + i * h, b.width + 8, h + 0.5), Paint()..color = colors[i]);
        }
        c.drawRect(b, Paint()
          ..shader = ui.Gradient.linear(b.topLeft, b.bottomRight, [Colors.white.withValues(alpha: 0.25), Colors.transparent, Colors.black.withValues(alpha: 0.18)], [0, 0.5, 1]));
      case CapPattern.polka:
        var row = 0;
        for (var y = b.top + 8; y < b.bottom; y += 9, row++) {
          for (var x = b.left + (row.isEven ? 6 : 10.5); x < b.right; x += 9) {
            c.drawCircle(Offset(x, y), 2.2, Paint()..color = Colors.white.withValues(alpha: 0.85));
          }
        }
      case CapPattern.snow:
        // Сніжна шапочка зверху й сніжинки.
        c.drawPath(
          Path()
            ..moveTo(b.left, b.top + b.height * 0.45)
            ..quadraticBezierTo(b.left + b.width * 0.2, b.top + b.height * 0.58, b.left + b.width * 0.35, b.top + b.height * 0.44)
            ..quadraticBezierTo(b.center.dx, b.top + b.height * 0.62, b.left + b.width * 0.68, b.top + b.height * 0.44)
            ..quadraticBezierTo(b.left + b.width * 0.85, b.top + b.height * 0.6, b.right, b.top + b.height * 0.42)
            ..lineTo(b.right, b.top)
            ..lineTo(b.left, b.top)
            ..close(),
          Paint()..color = const Color(0xfffafdff),
        );
        for (final (dx, dy) in [(-0.25, 0.72), (0.1, 0.8), (0.32, 0.7)]) {
          _snowflake(c, Offset(b.center.dx + dx * b.width, b.top + dy * b.height), 2.6, Colors.white);
        }
      case CapPattern.gold:
        for (final (dx, dy, rr) in [(-0.2, 0.45, 3.0), (0.24, 0.35, 2.4), (0.1, 0.65, 2.0)]) {
          _star4(c, Offset(b.center.dx + dx * b.width, b.top + dy * b.height), rr, Colors.white);
        }
      case CapPattern.auto:
    }
  }

  // ─── Обличчя ──────────────────────────────────────────────────────────────

  void _paintFace(Canvas c) {
    c.save();
    c.translate(face.dx, face.dy);
    c.scale(_faceScale);
    c.translate(-face.dx, -face.dy);
    _paintFaceInner(c);
    c.restore();
  }

  void _paintFaceInner(Canvas c) {
    final f = face;
    const ex = 8.0;
    final ink = Paint()..color = _ink;
    Paint stroke([double w = 2.2]) => Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (s.fx.contains(SFx.blush)) {
      for (final sx in [-1.0, 1.0]) {
        c.drawOval(Rect.fromCenter(center: Offset(f.dx + sx * 13, f.dy + 5), width: 8, height: 4.5), Paint()..color = const Color(0xffff8a80).withValues(alpha: 0.7));
      }
    }
    final ey = f.dy - 3;
    void eyeBall(double x, {double r = 4.6, double pupil = 3.0, Offset look = Offset.zero}) {
      c.drawCircle(Offset(x, ey), r, Paint()..color = Colors.white);
      c.drawCircle(Offset(x, ey), r, stroke(1.4));
      c.drawCircle(Offset(x, ey) + look, pupil, ink);
      c.drawCircle(Offset(x, ey) + look + const Offset(-1, -1.2), pupil * 0.35, Paint()..color = Colors.white);
    }

    void happyArc(double x) => c.drawArc(Rect.fromCenter(center: Offset(x, ey + 1.5), width: 8, height: 7), math.pi, math.pi, false, stroke(2.4));

    switch (s.eyes) {
      case SEyes.normal:
        eyeBall(f.dx - ex);
        eyeBall(f.dx + ex);
      case SEyes.happy:
        happyArc(f.dx - ex);
        happyArc(f.dx + ex);
      case SEyes.squeeze:
        for (final sx in [-1.0, 1.0]) {
          final x = f.dx + sx * ex;
          c.drawPath(Path()..moveTo(x - 3.5 * sx, ey - 3.5)..lineTo(x + 3 * sx, ey)..lineTo(x - 3.5 * sx, ey + 3.5), stroke(2.4));
        }
      case SEyes.spiral:
        for (final sx in [-1.0, 1.0]) {
          final o = Offset(f.dx + sx * ex, ey);
          c.drawCircle(o, 4.8, Paint()..color = Colors.white);
          final p = Path();
          for (var t = 0.0; t < 5.5 * math.pi; t += 0.2) {
            final pt = o + Offset(math.cos(t * sx), math.sin(t * sx)) * (0.3 + t * 0.26);
            t == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
          }
          c.drawPath(p, Paint()
            ..color = const Color(0xff2e7d32)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
          c.drawCircle(o, 4.8, stroke(1.2));
        }
      case SEyes.hearts:
        for (final sx in [-1.0, 1.0]) {
          heart(c, Offset(f.dx + sx * ex, ey), 5.2, const Color(0xffe53935));
        }
      case SEyes.stars:
        for (final sx in [-1.0, 1.0]) {
          _star5(c, Offset(f.dx + sx * ex, ey), 5.6);
        }
      case SEyes.crying:
        for (final sx in [-1.0, 1.0]) {
          c.drawArc(Rect.fromCenter(center: Offset(f.dx + sx * ex, ey - 1), width: 8, height: 6), 0, math.pi, false, stroke());
        }
      case SEyes.shades:
        final g = Path()
          ..addRRect(RRect.fromRectAndCorners(Rect.fromCenter(center: Offset(f.dx - ex, ey), width: 13, height: 8), bottomLeft: const Radius.circular(5), bottomRight: const Radius.circular(5)))
          ..addRRect(RRect.fromRectAndCorners(Rect.fromCenter(center: Offset(f.dx + ex, ey), width: 13, height: 8), bottomLeft: const Radius.circular(5), bottomRight: const Radius.circular(5)));
        c.drawLine(Offset(f.dx - ex - 9, ey - 3.5), Offset(f.dx + ex + 9, ey - 3.5), stroke(2));
        c.drawPath(g, ink);
        final shine = Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        for (final sx in [-1.0, 1.0]) {
          c.drawLine(Offset(f.dx + sx * ex - 3, ey - 2), Offset(f.dx + sx * ex + 1, ey - 2), shine);
        }
      case SEyes.angry:
        eyeBall(f.dx - ex, r: 4.2, pupil: 2.4, look: const Offset(0.8, 0.6));
        eyeBall(f.dx + ex, r: 4.2, pupil: 2.4, look: const Offset(-0.8, 0.6));
        c.drawLine(Offset(f.dx - ex - 5, ey - 8), Offset(f.dx - 2, ey - 4.5), stroke(2.8));
        c.drawLine(Offset(f.dx + ex + 5, ey - 8), Offset(f.dx + 2, ey - 4.5), stroke(2.8));
      case SEyes.sleepy:
        for (final sx in [-1.0, 1.0]) {
          c.drawArc(Rect.fromCenter(center: Offset(f.dx + sx * ex, ey - 1), width: 8, height: 5), 0.1, math.pi - 0.2, false, stroke(2));
        }
      case SEyes.wink:
        eyeBall(f.dx - ex);
        happyArc(f.dx + ex);
      case SEyes.scared:
        eyeBall(f.dx - ex, r: 5.4, pupil: 1.6);
        eyeBall(f.dx + ex, r: 5.4, pupil: 1.6);
        c.drawLine(Offset(f.dx - ex - 4, ey - 9), Offset(f.dx - ex + 3, ey - 11), stroke(2));
        c.drawLine(Offset(f.dx + ex + 4, ey - 9), Offset(f.dx + ex - 3, ey - 11), stroke(2));
      case SEyes.sly:
        for (final sx in [-1.0, 1.0]) {
          final x = f.dx + sx * ex;
          eyeBall(x, look: const Offset(1.4, 0.4));
          c.drawPath(Path()..addArc(Rect.fromCenter(center: Offset(x, ey), width: 9.6, height: 9.6), math.pi, math.pi)..close(), Paint()..color = _darken(s.bodyColor, 0.12));
          c.drawLine(Offset(x - 4.8, ey), Offset(x + 4.8, ey), stroke(1.8));
        }
    }

    final my = f.dy + 7;
    switch (s.mouth) {
      case SMouth.smile:
        c.drawArc(Rect.fromCenter(center: Offset(f.dx, my - 2), width: 10, height: 7), 0.2, math.pi - 0.4, false, stroke());
      case SMouth.laugh:
        _mouthFill(c, Path()
          ..moveTo(f.dx - 7, my - 2)
          ..quadraticBezierTo(f.dx, my - 1, f.dx + 7, my - 2)
          ..quadraticBezierTo(f.dx + 6, my + 9, f.dx, my + 9)
          ..quadraticBezierTo(f.dx - 6, my + 9, f.dx - 7, my - 2)
          ..close(), tongue: Offset(f.dx, my + 6.5));
      case SMouth.shout:
        _mouthFill(c, Path()
          ..moveTo(f.dx - 6, my - 3)
          ..lineTo(f.dx + 6, my - 3)
          ..lineTo(f.dx + 8, my + 9)
          ..quadraticBezierTo(f.dx, my + 12, f.dx - 8, my + 9)
          ..close(), tongue: Offset(f.dx, my + 8.5), teeth: true);
      case SMouth.o:
        _mouthFill(c, Path()..addOval(Rect.fromCenter(center: Offset(f.dx, my + 1), width: 6, height: 7)));
      case SMouth.wavy:
        final p = Path()..moveTo(f.dx - 7, my);
        for (var i = 0; i < 4; i++) {
          p.quadraticBezierTo(f.dx - 5.25 + i * 3.5, my + (i.isEven ? -2.5 : 2.5), f.dx - 3.5 + i * 3.5, my);
        }
        c.drawPath(p, stroke(2));
      case SMouth.smirk:
        c.drawPath(Path()..moveTo(f.dx - 5, my)..quadraticBezierTo(f.dx + 2, my + 3, f.dx + 7, my - 3), stroke());
      case SMouth.frown:
        c.drawArc(Rect.fromCenter(center: Offset(f.dx, my + 3), width: 10, height: 7), math.pi + 0.3, math.pi - 0.6, false, stroke());
      case SMouth.tongue:
        c.drawArc(Rect.fromCenter(center: Offset(f.dx, my - 2), width: 12, height: 7), 0.15, math.pi - 0.3, false, stroke());
        final t = Path()
          ..moveTo(f.dx - 1, my + 1)
          ..quadraticBezierTo(f.dx + 1, my + 8, f.dx + 5, my + 6)
          ..quadraticBezierTo(f.dx + 6, my + 2, f.dx + 4, my + 0.5)
          ..close();
        c.drawPath(t, Paint()..color = const Color(0xffef5350));
        c.drawPath(t, stroke(1.4));
    }
  }

  void _mouthFill(Canvas c, Path m, {Offset? tongue, bool teeth = false}) {
    c.drawPath(m, Paint()..color = const Color(0xff5d1f1a));
    c.save();
    c.clipPath(m);
    if (tongue != null) c.drawOval(Rect.fromCenter(center: tongue, width: 9, height: 6), Paint()..color = const Color(0xffef5350));
    if (teeth) {
      final b = m.getBounds();
      c.drawRect(Rect.fromLTWH(b.left, b.top, b.width, 2.6), Paint()..color = Colors.white);
    }
    c.restore();
    c.drawPath(m, Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round);
  }

  void _paintFx(Canvas c) {
    final f = face;
    final hb = headBox;
    for (final fx in s.fx) {
      switch (fx) {
        case SFx.sweat:
          drop(c, Offset(f.dx + 19, f.dy - 13), 5, const Color(0xff81d4fa));
        case SFx.vein:
          final o = Offset(hb.right - 12, hb.top + 14);
          final v = Paint()
            ..color = const Color(0xffd32f2f)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round;
          for (var i = 0; i < 4; i++) {
            final a = i * math.pi / 2 + math.pi / 4;
            c.drawArc(Rect.fromCircle(center: o + Offset(math.cos(a), math.sin(a)) * 4, radius: 3), a + math.pi * 0.6, math.pi * 0.8, false, v);
          }
        case SFx.sparkle:
          for (final (o, r) in [(Offset(hb.left - 2, hb.top + 6), 4.0), (Offset(hb.right + 1, hb.top + 16), 3.0), (Offset(bodyBox.right + 8, bodyBox.bottom - 14), 2.6)]) {
            _star4(c, o, r, const Color(0xffffd54f));
          }
        case SFx.hearts:
          heart(c, Offset(hb.right + 2, hb.top + 4), 4, const Color(0xffff5c8a));
          heart(c, Offset(hb.right + 9, hb.top + 14), 2.8, const Color(0xffff5c8a));
        case SFx.zzz:
          final z = Paint()
            ..color = const Color(0xff5c6bc0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round;
          for (final (o, k) in [(Offset(hb.right - 2, hb.top - 2), 7.0), (Offset(hb.right + 8, hb.top - 10), 5.0)]) {
            c.drawPath(Path()..moveTo(o.dx, o.dy)..lineTo(o.dx + k, o.dy)..lineTo(o.dx, o.dy + k)..lineTo(o.dx + k, o.dy + k), z);
          }
        case SFx.tears:
          for (final sx in [-1.0, 1.0]) {
            final o = eye(sx) + const Offset(0, 4);
            c.drawPath(
              Path()
                ..moveTo(o.dx, o.dy)
                ..quadraticBezierTo(o.dx + sx * 4, o.dy + 9, o.dx + sx * 1, o.dy + 12)
                ..quadraticBezierTo(o.dx - sx * 3, o.dy + 9, o.dx, o.dy)
                ..close(),
              Paint()..color = const Color(0xff4fc3f7).withValues(alpha: 0.9),
            );
          }
        case SFx.blush:
      }
    }
  }
}

// ─── Спільні дрібниці ───────────────────────────────────────────────────────

void heart(Canvas c, Offset o, double r, Color color) {
  final p = Path()
    ..moveTo(o.dx, o.dy + r * 0.9)
    ..cubicTo(o.dx - r * 1.4, o.dy - r * 0.1, o.dx - r * 0.7, o.dy - r * 1.2, o.dx, o.dy - r * 0.45)
    ..cubicTo(o.dx + r * 0.7, o.dy - r * 1.2, o.dx + r * 1.4, o.dy - r * 0.1, o.dx, o.dy + r * 0.9)
    ..close();
  c.drawPath(p, Paint()..color = color);
  c.drawPath(p, Paint()
    ..color = _darken(color, 0.4)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1);
  c.drawCircle(o + Offset(-r * 0.35, -r * 0.35), r * 0.18, Paint()..color = Colors.white.withValues(alpha: 0.8));
}

void drop(Canvas c, Offset o, double r, Color color) {
  final p = Path()
    ..moveTo(o.dx, o.dy - r * 1.2)
    ..quadraticBezierTo(o.dx + r, o.dy + r * 0.2, o.dx, o.dy + r * 0.5)
    ..quadraticBezierTo(o.dx - r, o.dy + r * 0.2, o.dx, o.dy - r * 1.2)
    ..close();
  c.drawPath(p, Paint()..color = color);
  c.drawPath(p, Paint()
    ..color = _darken(color, 0.45)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1);
}

void _star4(Canvas c, Offset o, double r, Color color) {
  final p = Path()
    ..moveTo(o.dx, o.dy - r)
    ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
    ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
    ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
    ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
    ..close();
  c.drawPath(p, Paint()..color = color);
}

Path starPath(Offset o, double r, {double inner = 0.45}) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final rr = i.isEven ? r : r * inner;
    final pt = o + Offset(math.cos(a), math.sin(a)) * rr;
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
}

void _star5(Canvas c, Offset o, double r) {
  final p = starPath(o, r);
  c.drawPath(p, Paint()..color = const Color(0xffffca28));
  c.drawPath(p, Paint()
    ..color = const Color(0xff8d5a00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1
    ..strokeJoin = StrokeJoin.round);
  c.drawCircle(o + Offset(-r * 0.2, -r * 0.2), r * 0.16, Paint()..color = Colors.white);
}

void _snowflake(Canvas c, Offset o, double r, Color color) {
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.1
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 3; i++) {
    final a = i * math.pi / 3;
    final d = Offset(math.cos(a), math.sin(a)) * r;
    c.drawLine(o - d, o + d, p);
  }
}

// ─── Деталі: капелюх, річ, ефект ────────────────────────────────────────────

/// Малює деталі в трьох режимах: межі (для вписування), силует (тінь і білий контур), фарба.
class _Details {
  _Details(this.f, this.x);

  final _Figure f;
  final StickerExtras x;

  _Mode _mode = _Mode.paint;
  Canvas? _c;
  Paint? _sil;
  Rect? _bounds;
  bool _behindPass = false;

  Rect? measure() {
    _mode = _Mode.measure;
    _bounds = null;
    _all();
    return _bounds;
  }

  void silhouette(Canvas canvas, Paint sil) {
    _mode = _Mode.silhouette;
    _sil = sil;
    f.within(canvas, () {
      _c = canvas;
      _all();
    });
  }

  void paint(Canvas canvas, {required bool behind}) {
    _mode = _Mode.paint;
    _behindPass = behind;
    f.within(canvas, () {
      _c = canvas;
      _all();
    });
  }

  void _all() {
    _layer = true;
    _item(behindOnly: true);
    _layer = false;
    _hat();
    _item(behindOnly: false);
    _fx();
  }

  /// Чи поточна деталь — позаду персонажа (наплічник).
  bool _layer = false;

  bool get _skip => _mode == _Mode.paint && _layer != _behindPass;

  // Збільшення дрібної деталі навколо її точки (рука, груди, сама деталь).
  Offset _za = Offset.zero;
  double _zk = 1;
  void _zoomAt(Offset a, double k) {
    _za = a;
    _zk = k;
  }

  Rect _zr(Rect r) => _zk == 1 ? r : Rect.fromPoints(_za + (r.topLeft - _za) * _zk, _za + (r.bottomRight - _za) * _zk);

  void _zoomed(void Function(Canvas c) draw) {
    final c = _c!;
    if (_zk == 1) return draw(c);
    c.save();
    c.translate(_za.dx, _za.dy);
    c.scale(_zk);
    c.translate(-_za.dx, -_za.dy);
    draw(c);
    c.restore();
  }

  /// Частина деталі з контуром: заливка + тонкий темний обвід; у силуеті — білий контур.
  void shape(Path p, Paint fill, {Color? outline, bool border = true, double width = 1.4}) {
    switch (_mode) {
      case _Mode.measure:
        if (border) {
          final r = _zr(p.getBounds()).inflate(4.5);
          _bounds = (_bounds ?? r).expandToInclude(r);
        }
      case _Mode.silhouette:
        if (!border) return;
        _zoomed((c) => _silPath(c, p));
      case _Mode.paint:
        if (_skip) return;
        _zoomed((c) {
          c.drawPath(p, fill);
          if (outline != null) {
            c.drawPath(p, Paint()
              ..color = outline
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..strokeJoin = StrokeJoin.round);
          }
        });
    }
  }

  void _silPath(Canvas c, Path p) {
    c.drawPath(p, Paint()
      ..color = _sil!.color
      ..maskFilter = _sil!.maskFilter);
    c.drawPath(p, Paint()
      ..color = _sil!.color
      ..maskFilter = _sil!.maskFilter
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7 / _zk
      ..strokeJoin = StrokeJoin.round);
  }

  /// Дрібниці всередині деталі — лише у фарбі.
  void deco(void Function(Canvas c) draw) {
    if (_mode != _Mode.paint || _skip) return;
    _zoomed(draw);
  }

  /// Межі для ефектів без контуру.
  void extent(Rect r) {
    if (_mode != _Mode.measure) return;
    final z = _zr(r);
    _bounds = (_bounds ?? z).expandToInclude(z);
  }

  Paint fill(Color c) => Paint()..color = c;
  Paint grad(Rect r, Color c) => Paint()..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, [_lighten(c, 0.3), c, _darken(c, 0.2)], [0, 0.5, 1]);

  // ─── Капелюхи ─────────────────────────────────────────────────────────────

  void _hat() {
    _zk = 1;
    final id = x.hat;
    if (id == null) return;
    final t = f.top;
    final w = (f.topWidth * 0.66).clamp(30.0, 50.0);
    final cx = t.dx;
    final y = t.dy + (f.s.cap == SCap.none ? 6 : 5); // низ капелюха трохи «сидить» на шапці
    switch (id) {
      case 'leaf':
        final leaf = Path()
          ..moveTo(cx - 2, y)
          ..cubicTo(cx - 16, y - 6, cx - 14, y - 22, cx + 4, y - 24)
          ..cubicTo(cx + 6, y - 12, cx + 4, y - 4, cx - 2, y)
          ..close();
        const g = Color(0xff7cb342);
        shape(leaf, grad(leaf.getBounds(), g), outline: _darken(g, 0.5));
        deco((c) {
          c.drawPath(Path()..moveTo(cx - 2, y)..quadraticBezierTo(cx - 4, y - 12, cx + 3, y - 22), Paint()
            ..color = _darken(g, 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
        });
      case 'wreath':
        // Віночок: дуга з листя й квітів і стрічки збоку.
        final r = Rect.fromCenter(center: Offset(cx, y - 2), width: w * 1.5, height: w * 0.48);
        final band = Path()..addOval(r);
        final ribbon = Path()
          ..moveTo(r.right - 6, r.center.dy)
          ..lineTo(r.right + 2, r.center.dy + 15)
          ..lineTo(r.right - 2, r.center.dy + 13)
          ..lineTo(r.right - 5, r.center.dy + 16)
          ..close();
        shape(ribbon, fill(const Color(0xffe53935)), outline: const Color(0xff7f0000), width: 1);
        final ribbon2 = Path()
          ..moveTo(r.right - 8, r.center.dy)
          ..lineTo(r.right - 7, r.center.dy + 18)
          ..lineTo(r.right - 10, r.center.dy + 15)
          ..lineTo(r.right - 13, r.center.dy + 17)
          ..close();
        shape(ribbon2, fill(const Color(0xff1e88e5)), outline: const Color(0xff0d47a1), width: 1);
        shape(band, fill(const Color(0xff558b2f)), outline: const Color(0xff2e4a14));
        deco((c) {
          final colors = [const Color(0xffe53935), const Color(0xffffeb3b), const Color(0xff1e88e5), const Color(0xffff7043), const Color(0xffffffff), const Color(0xffe53935)];
          for (var i = 0; i < colors.length; i++) {
            final a = math.pi * (0.05 + i * 0.9 / (colors.length - 1));
            final p = Offset(r.center.dx - math.cos(a) * r.width / 2 * 0.92, r.center.dy + math.sin(a) * r.height / 2 * 0.6);
            for (var k = 0; k < 5; k++) {
              final pa = k * math.pi * 2 / 5;
              c.drawCircle(p + Offset(math.cos(pa), math.sin(pa)) * 2.3, 1.9, Paint()..color = colors[i]);
            }
            c.drawCircle(p, 1.4, Paint()..color = const Color(0xffffb300));
          }
        });
      case 'cap':
        final dome = Path()
          ..moveTo(cx - w / 2, y)
          ..cubicTo(cx - w / 2, y - w * 0.62, cx + w / 2, y - w * 0.62, cx + w / 2, y)
          ..close();
        final visor = Path()
          ..moveTo(cx + w * 0.2, y - 2)
          ..quadraticBezierTo(cx + w * 0.95, y - 3, cx + w * 0.9, y + 3)
          ..quadraticBezierTo(cx + w * 0.5, y + 4, cx + w * 0.2, y + 1)
          ..close();
        const col = Color(0xff1e88e5);
        shape(visor, fill(_darken(col, 0.15)), outline: _darken(col, 0.6));
        shape(dome, grad(dome.getBounds(), col), outline: _darken(col, 0.6));
        deco((c) => c.drawCircle(Offset(cx, y - w * 0.46), 1.8, Paint()..color = _darken(col, 0.4)));
      case 'beanie':
        final dome = Path()
          ..moveTo(cx - w / 2, y)
          ..cubicTo(cx - w / 2, y - w * 0.8, cx + w / 2, y - w * 0.8, cx + w / 2, y)
          ..close();
        final cuff = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(cx - w / 2 - 2, y - 7, cx + w / 2 + 2, y + 2), const Radius.circular(4)));
        final pom = Path()..addOval(Rect.fromCircle(center: Offset(cx, y - w * 0.62), radius: 5));
        const col = Color(0xffe64a19);
        shape(pom, fill(const Color(0xfffff3e0)), outline: const Color(0xff8d6e63));
        shape(dome, grad(dome.getBounds(), col), outline: _darken(col, 0.55));
        shape(cuff, fill(_darken(col, 0.1)), outline: _darken(col, 0.55));
        deco((c) {
          final rib = Paint()
            ..color = _darken(col, 0.3)
            ..strokeWidth = 1;
          for (var xx = cx - w / 2 + 2; xx < cx + w / 2; xx += 3.5) {
            c.drawLine(Offset(xx, y - 6), Offset(xx, y + 1), rib);
          }
        });
      case 'straw':
        final brim = Path()..addOval(Rect.fromCenter(center: Offset(cx, y - 2), width: w * 1.7, height: w * 0.38));
        final crown = Path()
          ..moveTo(cx - w * 0.38, y - 2)
          ..cubicTo(cx - w * 0.42, y - w * 0.6, cx + w * 0.42, y - w * 0.6, cx + w * 0.38, y - 2)
          ..close();
        const col = Color(0xfff2c94c);
        shape(brim, grad(brim.getBounds(), col), outline: const Color(0xff8a6d1a));
        shape(crown, grad(crown.getBounds(), col), outline: const Color(0xff8a6d1a));
        deco((c) {
          c.save();
          c.clipPath(crown);
          c.drawRect(Rect.fromLTRB(cx - w, y - 9, cx + w, y - 4), Paint()..color = const Color(0xffd32f2f));
          c.restore();
          final weave = Paint()
            ..color = const Color(0xffc9a227)
            ..strokeWidth = 0.7;
          for (var i = -4; i <= 4; i++) {
            c.drawLine(Offset(cx + i * w * 0.18, y - 6), Offset(cx + i * w * 0.2, y + 2), weave);
          }
        });
      case 'ranger':
        final brim = Path()..addOval(Rect.fromCenter(center: Offset(cx, y - 1), width: w * 1.6, height: w * 0.34));
        final crown = Path()
          ..moveTo(cx - w * 0.4, y - 1)
          ..lineTo(cx - w * 0.34, y - w * 0.58)
          ..quadraticBezierTo(cx - w * 0.17, y - w * 0.7, cx, y - w * 0.56)
          ..quadraticBezierTo(cx + w * 0.17, y - w * 0.7, cx + w * 0.34, y - w * 0.58)
          ..lineTo(cx + w * 0.4, y - 1)
          ..close();
        const col = Color(0xff5d7a3a);
        final feather = Path()
          ..moveTo(cx + w * 0.3, y - 6)
          ..cubicTo(cx + w * 0.6, y - 14, cx + w * 0.7, y - 24, cx + w * 0.55, y - 30)
          ..cubicTo(cx + w * 0.42, y - 22, cx + w * 0.3, y - 14, cx + w * 0.3, y - 6)
          ..close();
        shape(feather, fill(const Color(0xffff7043)), outline: const Color(0xff8d2b0b), width: 1);
        shape(brim, grad(brim.getBounds(), col), outline: _darken(col, 0.6));
        shape(crown, grad(crown.getBounds(), col), outline: _darken(col, 0.6));
        deco((c) {
          c.save();
          c.clipPath(crown);
          c.drawRect(Rect.fromLTRB(cx - w, y - 8, cx + w, y - 3), Paint()..color = const Color(0xff6d4c2f));
          c.restore();
        });
      case 'wizard':
        final brim = Path()..addOval(Rect.fromCenter(center: Offset(cx, y - 1), width: w * 1.7, height: w * 0.36));
        final cone = Path()
          ..moveTo(cx - w * 0.42, y - 2)
          ..quadraticBezierTo(cx - w * 0.1, y - w * 0.9, cx + w * 0.2, y - w * 1.45)
          ..quadraticBezierTo(cx + w * 0.12, y - w * 0.8, cx + w * 0.42, y - 2)
          ..close();
        const col = Color(0xff5e35b1);
        shape(brim, grad(brim.getBounds(), col), outline: _darken(col, 0.6));
        shape(cone, grad(cone.getBounds(), col), outline: _darken(col, 0.6));
        deco((c) {
          _star4(c, Offset(cx - w * 0.05, y - w * 0.45), 3.5, const Color(0xffffd54f));
          _star4(c, Offset(cx + w * 0.12, y - w * 0.85), 2.4, const Color(0xffffd54f));
          c.drawCircle(Offset(cx + w * 0.18, y - w * 0.2), 1.3, Paint()..color = const Color(0xffffd54f));
        });
      case 'tophat':
        final brim = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, y - 2), width: w * 1.4, height: 6), const Radius.circular(3)));
        final crown = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(cx - w * 0.38, y - w * 0.95, cx + w * 0.38, y - 3), const Radius.circular(3)));
        const col = Color(0xff263238);
        shape(crown, grad(crown.getBounds(), col), outline: Colors.black);
        shape(brim, fill(col), outline: Colors.black);
        deco((c) {
          c.drawRect(Rect.fromLTRB(cx - w * 0.38, y - 11, cx + w * 0.38, y - 6), Paint()..color = const Color(0xffc62828));
          c.drawRect(Rect.fromLTRB(cx - w * 0.3, y - w * 0.9, cx - w * 0.22, y - 13), Paint()..color = Colors.white.withValues(alpha: 0.25));
        });
      case 'crown':
        final yy = y + 1;
        final p = Path()
          ..moveTo(cx - w * 0.45, yy)
          ..lineTo(cx - w * 0.55, yy - w * 0.5)
          ..lineTo(cx - w * 0.22, yy - w * 0.25)
          ..lineTo(cx, yy - w * 0.62)
          ..lineTo(cx + w * 0.22, yy - w * 0.25)
          ..lineTo(cx + w * 0.55, yy - w * 0.5)
          ..lineTo(cx + w * 0.45, yy)
          ..close();
        shape(p, Paint()..shader = ui.Gradient.linear(Offset(cx, yy - w * 0.62), Offset(cx, yy), [const Color(0xffffe082), const Color(0xffffb300)]), outline: const Color(0xff8d5a00));
        deco((c) {
          for (final (dx, col) in [(-0.28, const Color(0xffe53935)), (0.0, const Color(0xff1e88e5)), (0.28, const Color(0xff43a047))]) {
            c.drawCircle(Offset(cx + dx * w, yy - 4), 2, Paint()..color = col);
          }
        });
      case 'santa':
        final cone = Path()
          ..moveTo(cx - w * 0.5, y - 2)
          ..quadraticBezierTo(cx - w * 0.2, y - w * 1.1, cx + w * 0.62, y - w * 0.55)
          ..quadraticBezierTo(cx + w * 0.2, y - w * 0.55, cx + w * 0.5, y - 2)
          ..close();
        final trim = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(cx - w * 0.58, y - 8, cx + w * 0.58, y + 2), const Radius.circular(5)));
        final pom = Path()..addOval(Rect.fromCircle(center: Offset(cx + w * 0.64, y - w * 0.52), radius: 4.5));
        const col = Color(0xffd32f2f);
        shape(cone, grad(cone.getBounds(), col), outline: _darken(col, 0.6));
        shape(trim, fill(Colors.white), outline: const Color(0xffb0bec5));
        shape(pom, fill(Colors.white), outline: const Color(0xffb0bec5));
      case 'pumpkin':
        final body = Path()..addOval(Rect.fromCenter(center: Offset(cx, y - w * 0.3), width: w * 1.1, height: w * 0.66));
        final stem = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 2.5, y - w * 0.72, 5, 8), const Radius.circular(2)));
        const col = Color(0xffef6c00);
        shape(stem, fill(const Color(0xff6d4c2f)), outline: const Color(0xff3e2a17));
        shape(body, grad(body.getBounds(), col), outline: _darken(col, 0.6));
        deco((c) {
          final rib = Paint()
            ..color = _darken(col, 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1;
          for (final k in [-0.25, 0.0, 0.25]) {
            c.drawArc(Rect.fromCenter(center: Offset(cx + k * w * 0.9, y - w * 0.3), width: w * 0.3, height: w * 0.62), -math.pi / 2, math.pi, false, rib);
          }
          c.drawPath(Path()..moveTo(cx + 2, y - w * 0.66)..quadraticBezierTo(cx + 10, y - w * 0.9, cx + 14, y - w * 0.66)..quadraticBezierTo(cx + 8, y - w * 0.62, cx + 2, y - w * 0.66), Paint()..color = const Color(0xff689f38));
        });
    }
  }

  // ─── Речі ─────────────────────────────────────────────────────────────────

  void _item({required bool behindOnly}) {
    _zk = 1;
    final id = x.item;
    if (id == null) return;
    if ((id == 'backpack') != behindOnly) return;
    final b = f.bodyBox;
    final hl = f.arms.isEmpty ? b.centerLeft : f.arms[0].to;
    final hr = f.arms.length < 2 ? b.centerRight : f.arms[1].to;
    final chest = Offset(f.face.dx, f.chestY);
    switch (id) {
      case 'backpack':
        // Наплічник за спиною: видно збоку, згорнута ковдра зверху.
        final top = f.face.dy - 10;
        final bag = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(b.right - 22, top, b.right + 12, top + 34), const Radius.circular(9)));
        final roll = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(b.right - 20, top - 8, b.right + 14, top + 2), const Radius.circular(5)));
        const col = Color(0xffc0682e);
        shape(bag, grad(bag.getBounds(), col), outline: _darken(col, 0.6));
        shape(roll, grad(roll.getBounds(), const Color(0xff43a047)), outline: const Color(0xff1b5e20));
        deco((c) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(b.right + 1, top + 14, b.right + 11, top + 28), const Radius.circular(3)), Paint()..color = _darken(col, 0.15));
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(b.right + 1, top + 14, b.right + 11, top + 28), const Radius.circular(3)), Paint()
            ..color = _darken(col, 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
          c.drawLine(Offset(b.right - 16, top - 7), Offset(b.right - 16, top + 1), Paint()
            ..color = const Color(0xff6d4c2f)
            ..strokeWidth = 2);
          c.drawLine(Offset(b.right + 8, top - 7), Offset(b.right + 8, top + 1), Paint()
            ..color = const Color(0xff6d4c2f)
            ..strokeWidth = 2);
        });
      case 'basket':
        final o = hr + const Offset(4, 6);
        _zoomAt(hr, 1.35);
        final handle = Path()..addArc(Rect.fromCenter(center: o + const Offset(0, -2), width: 18, height: 18), math.pi, math.pi);
        final bowl = Path()
          ..moveTo(o.dx - 11, o.dy - 2)
          ..lineTo(o.dx + 11, o.dy - 2)
          ..lineTo(o.dx + 8, o.dy + 10)
          ..quadraticBezierTo(o.dx, o.dy + 12, o.dx - 8, o.dy + 10)
          ..close();
        final shroom = Path()..addArc(Rect.fromCenter(center: o + const Offset(-3, -1), width: 12, height: 10), math.pi, math.pi);
        const col = Color(0xffb7834a);
        extent(handle.getBounds().inflate(5));
        deco((c) => c.drawPath(handle, Paint()
          ..color = _darken(col, 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2));
        shape(shroom, fill(const Color(0xff8a5a32)), outline: const Color(0xff3e2a17), border: false);
        shape(bowl, grad(bowl.getBounds(), col), outline: _darken(col, 0.6));
        deco((c) {
          c.save();
          c.clipPath(bowl);
          final weave = Paint()
            ..color = _darken(col, 0.3)
            ..strokeWidth = 0.9;
          for (var yy = o.dy + 1; yy < o.dy + 11; yy += 3) {
            c.drawLine(Offset(o.dx - 12, yy), Offset(o.dx + 12, yy), weave);
          }
          for (var xx = o.dx - 9; xx < o.dx + 10; xx += 4) {
            c.drawLine(Offset(xx, o.dy - 2), Offset(xx + (xx - o.dx) * -0.2, o.dy + 11), weave);
          }
          c.restore();
        });
      case 'glasses':
        if (f.s.eyes == SEyes.shades) return;
        final l = f.eye(-1), r = f.eye(1);
        deco((c) {
          final frame = Paint()
            ..color = const Color(0xff4e342e)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8;
          for (final e in [l, r]) {
            c.drawCircle(e, 7, Paint()..color = const Color(0xffb3e5fc).withValues(alpha: 0.25));
            c.drawCircle(e, 7, frame);
          }
          c.drawArc(Rect.fromCenter(center: Offset((l.dx + r.dx) / 2, l.dy - 1), width: r.dx - l.dx - 14, height: 5), math.pi, math.pi, false, frame);
        });
      case 'scarf':
        final y = f.s.body == SBody.potato ? b.bottom - 6 : f.chestY;
        final half = _halfWidthAt(y) + 2;
        final band = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(chest.dx - half, y - 3.5, chest.dx + half, y + 3.5), const Radius.circular(3.5)));
        final tail = Path()
          ..moveTo(chest.dx + half * 0.3, y)
          ..lineTo(chest.dx + half * 0.55, y + 14)
          ..lineTo(chest.dx + half * 0.15, y + 15)
          ..lineTo(chest.dx + half * 0.02, y + 2)
          ..close();
        const col = Color(0xffc62828);
        shape(tail, grad(tail.getBounds(), col), outline: _darken(col, 0.6));
        shape(band, grad(band.getBounds(), col), outline: _darken(col, 0.6));
        deco((c) {
          final stripe = Paint()
            ..color = Colors.white
            ..strokeWidth = 1.6;
          c.save();
          c.clipPath(band);
          for (var xx = chest.dx - half; xx < chest.dx + half; xx += 6) {
            c.drawLine(Offset(xx, y - 5), Offset(xx + 4, y + 5), stripe);
          }
          c.restore();
          c.drawLine(Offset(chest.dx + half * 0.2, y + 13), Offset(chest.dx + half * 0.5, y + 12), stripe);
        });
      case 'flower':
        final hb = f.headBox;
        final o = Offset(hb.right - hb.width * 0.2, hb.top + hb.height * 0.3);
        _zoomAt(o, 1.7);
        final petals = Path();
        for (var k = 0; k < 6; k++) {
          final a = k * math.pi / 3;
          petals.addOval(Rect.fromCenter(center: o + Offset(math.cos(a), math.sin(a)) * 4.2, width: 5.6, height: 5.6));
        }
        shape(petals, fill(Colors.white), outline: const Color(0xffbdbdbd), width: 0.9);
        deco((c) {
          c.drawCircle(o, 3, Paint()..color = const Color(0xffffc107));
          c.drawCircle(o, 3, Paint()
            ..color = const Color(0xffb27b00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
        });
      case 'map':
        final o = hl + const Offset(-4, 2);
        _zoomAt(hl, 1.35);
        final paper = Path()
          ..moveTo(o.dx - 9, o.dy - 6)
          ..lineTo(o.dx - 3, o.dy - 8)
          ..lineTo(o.dx + 3, o.dy - 6)
          ..lineTo(o.dx + 9, o.dy - 8)
          ..lineTo(o.dx + 9, o.dy + 6)
          ..lineTo(o.dx + 3, o.dy + 8)
          ..lineTo(o.dx - 3, o.dy + 6)
          ..lineTo(o.dx - 9, o.dy + 8)
          ..close();
        shape(paper, fill(const Color(0xfffff3d6)), outline: const Color(0xff8d6e63));
        deco((c) {
          c.drawRect(Rect.fromLTRB(o.dx - 3, o.dy - 7, o.dx + 3, o.dy + 7), Paint()..color = const Color(0xffe8d9b5));
          final path = Paint()
            ..color = const Color(0xffd32f2f)
            ..strokeWidth = 1.1
            ..strokeCap = StrokeCap.round;
          for (var i = 0; i < 4; i++) {
            c.drawLine(Offset(o.dx - 7 + i * 3.6, o.dy + 3 - i * 1.2), Offset(o.dx - 5.5 + i * 3.6, o.dy + 2.5 - i * 1.2), path);
          }
          c.drawCircle(Offset(o.dx + 6, o.dy - 3), 1.6, Paint()..color = const Color(0xff2e7d32));
        });
      case 'magnifier':
        final o = hr + const Offset(4, -8);
        _zoomAt(hr, 1.35);
        final handle = Path()
          ..moveTo(hr.dx - 1, hr.dy + 3)
          ..lineTo(o.dx - 2, o.dy + 6)
          ..lineTo(o.dx + 1, o.dy + 7)
          ..lineTo(hr.dx + 2, hr.dy + 4)
          ..close();
        final ring = Path()..addOval(Rect.fromCircle(center: o, radius: 7.5));
        shape(handle, fill(const Color(0xff6d4c2f)), outline: const Color(0xff3e2a17));
        shape(ring, fill(const Color(0xffb3e5fc).withValues(alpha: 0.6)), outline: const Color(0xff455a64), width: 2.4);
        deco((c) => c.drawArc(Rect.fromCircle(center: o, radius: 4.5), math.pi * 1.1, math.pi * 0.5, false, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round));
      case 'medal':
        final o = chest + Offset(-_halfWidthAt(chest.dy) * 0.45, 2);
        _zoomAt(o, 1.3);
        final ribbon = Path()
          ..moveTo(o.dx - 4, o.dy - 8)
          ..lineTo(o.dx + 4, o.dy - 8)
          ..lineTo(o.dx + 2, o.dy)
          ..lineTo(o.dx - 2, o.dy)
          ..close();
        final disc = Path()..addOval(Rect.fromCircle(center: o + const Offset(0, 4), radius: 5));
        shape(ribbon, fill(const Color(0xff1565c0)), outline: const Color(0xff0d2b5c), width: 1);
        shape(disc, Paint()..shader = ui.Gradient.radial(o + const Offset(-1.5, 2.5), 6, [const Color(0xffffecb3), const Color(0xffffb300)]), outline: const Color(0xff8d5a00));
        deco((c) => c.drawPath(starPath(o + const Offset(0, 4), 2.8), Paint()..color = const Color(0xffb26a00)));
      case 'bowtie':
        final o = chest + const Offset(0, -2);
        _zoomAt(o, 1.25);
        final bow = Path()
          ..moveTo(o.dx, o.dy)
          ..lineTo(o.dx - 9, o.dy - 5)
          ..quadraticBezierTo(o.dx - 11, o.dy, o.dx - 9, o.dy + 5)
          ..close()
          ..moveTo(o.dx, o.dy)
          ..lineTo(o.dx + 9, o.dy - 5)
          ..quadraticBezierTo(o.dx + 11, o.dy, o.dx + 9, o.dy + 5)
          ..close();
        const col = Color(0xff8e24aa);
        shape(bow, grad(bow.getBounds(), col), outline: _darken(col, 0.6));
        shape(Path()..addOval(Rect.fromCircle(center: o, radius: 2.6)), fill(_darken(col, 0.15)), outline: _darken(col, 0.6));
      case 'lantern':
        final o = hl + const Offset(-2, 10);
        _zoomAt(hl, 1.6);
        final hook = Path()
          ..moveTo(hl.dx, hl.dy)
          ..lineTo(o.dx, o.dy - 8);
        final body = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 11, height: 14), const Radius.circular(3)));
        final topCap = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o + const Offset(0, -8), width: 13, height: 4), const Radius.circular(2)));
        extent(Rect.fromCircle(center: o, radius: 14));
        deco((c) {
          c.drawCircle(o, 13, Paint()
            ..color = const Color(0xffffe082).withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
          c.drawPath(hook, Paint()
            ..color = const Color(0xff37474f)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
        });
        shape(body, fill(const Color(0xfffff8e1)), outline: const Color(0xff37474f));
        shape(topCap, fill(const Color(0xff455a64)), outline: const Color(0xff263238));
        deco((c) {
          c.drawOval(Rect.fromCenter(center: o + const Offset(0, 1), width: 4, height: 7), Paint()..color = const Color(0xffffa000));
          c.drawOval(Rect.fromCenter(center: o + const Offset(0, 2), width: 2, height: 3.5), Paint()..color = const Color(0xffffee58));
        });
    }
  }

  /// Півширина тіла на висоті y (для шарфа, медалі).
  double _halfWidthAt(double y) {
    final b = f.bodyBox;
    switch (f.s.body) {
      case SBody.round:
        final dy = ((y - b.center.dy) / (b.height / 2)).clamp(-1.0, 1.0);
        return b.width / 2 * math.sqrt(1 - dy * dy);
      case SBody.potato:
        return b.width / 2 - 4;
      case SBody.puff:
        return b.width / 2 - 4;
      default:
        return b.width / 2 + 1;
    }
  }

  // ─── Ефекти навколо ───────────────────────────────────────────────────────

  void _fx() {
    _zk = 1;
    final id = x.fx;
    if (id == null) return;
    final hb = f.headBox;
    final b = f.bodyBox;
    final all = hb.expandToInclude(b);
    switch (id) {
      case 'sparkle':
        for (final (o, r) in [(Offset(all.left - 6, all.top + 8), 5.0), (Offset(all.right + 5, all.top + 20), 4.0), (Offset(all.left - 2, b.bottom - 12), 3.4), (Offset(all.right + 3, b.bottom - 4), 2.8)]) {
          _zoomAt(o, 1.5);
          extent(Rect.fromCircle(center: o, radius: r + 1));
          deco((c) => _star4(c, o, r, const Color(0xffffd54f)));
        }
      case 'hearts':
        for (final (o, r) in [(Offset(all.right + 3, all.top + 6), 5.0), (Offset(all.right + 10, all.top + 20), 3.4), (Offset(all.left - 5, all.top + 18), 3.8)]) {
          _zoomAt(o, 1.5);
          final p = Path()
            ..moveTo(o.dx, o.dy + r * 0.9)
            ..cubicTo(o.dx - r * 1.4, o.dy - r * 0.1, o.dx - r * 0.7, o.dy - r * 1.2, o.dx, o.dy - r * 0.45)
            ..cubicTo(o.dx + r * 0.7, o.dy - r * 1.2, o.dx + r * 1.4, o.dy - r * 0.1, o.dx, o.dy + r * 0.9)
            ..close();
          shape(p, fill(const Color(0xffff5c8a)), outline: const Color(0xffad1457), width: 1);
        }
      case 'notes':
        for (final (o, k, dbl) in [(Offset(all.left - 8, all.top + 12), 1.0, true), (Offset(all.right + 6, all.top + 4), 0.8, false)]) {
          _zoomAt(o, 1.5);
          final p = Path()
            ..addOval(Rect.fromCenter(center: o, width: 7 * k, height: 5.5 * k))
            ..addRect(Rect.fromLTWH(o.dx + 2.4 * k, o.dy - 13 * k, 1.8 * k, 13 * k));
          if (dbl) {
            p
              ..addOval(Rect.fromCenter(center: o + Offset(9 * k, -2 * k), width: 7 * k, height: 5.5 * k))
              ..addRect(Rect.fromLTWH(o.dx + 11.4 * k, o.dy - 15 * k, 1.8 * k, 13 * k))
              ..addPolygon([o + Offset(2.4 * k, -13 * k), o + Offset(13.2 * k, -15 * k), o + Offset(13.2 * k, -12 * k), o + Offset(2.4 * k, -10 * k)], true);
          } else {
            p.addPolygon([o + Offset(4.2 * k, -13 * k), o + Offset(8 * k, -9 * k), o + Offset(7 * k, -7 * k), o + Offset(4.2 * k, -10 * k)], true);
          }
          shape(p, fill(const Color(0xff3949ab)), outline: const Color(0xff1a237e), width: 0.8);
        }
      case 'leaves':
        for (final (o, a, col) in [(Offset(all.left - 6, all.top + 14), -0.6, const Color(0xffef6c00)), (Offset(all.right + 6, all.top + 30), 0.8, const Color(0xffd84315)), (Offset(all.left - 3, b.bottom - 6), 2.2, const Color(0xfffbc02d))]) {
          _zoomAt(o, 1.5);
          Offset rot(double px, double py) => o + Offset(px * math.cos(a) - py * math.sin(a), px * math.sin(a) + py * math.cos(a));
          final p = Path()
            ..moveTo(rot(0, -6).dx, rot(0, -6).dy)
            ..quadraticBezierTo(rot(5, 0).dx, rot(5, 0).dy, rot(0, 6).dx, rot(0, 6).dy)
            ..quadraticBezierTo(rot(-5, 0).dx, rot(-5, 0).dy, rot(0, -6).dx, rot(0, -6).dy)
            ..close();
          shape(p, fill(col), outline: _darken(col, 0.5), width: 1);
          deco((c) => c.drawLine(o + Offset(math.sin(a), -math.cos(a)) * -5, o + Offset(math.sin(a), -math.cos(a)) * 5, Paint()
            ..color = _darken(col, 0.35)
            ..strokeWidth = 0.8));
        }
      case 'cloud':
        final o = Offset(all.left + 2, all.top - 10);
        _zoomAt(o + const Offset(8, 0), 1.7);
        final cloud = Path()
          ..addOval(Rect.fromCircle(center: o, radius: 7))
          ..addOval(Rect.fromCircle(center: o + const Offset(8, -3), radius: 8))
          ..addOval(Rect.fromCircle(center: o + const Offset(16, 1), radius: 6))
          ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(o.dx - 3, o.dy - 1, o.dx + 19, o.dy + 6), const Radius.circular(4)));
        shape(cloud, fill(const Color(0xffeceff1)), outline: const Color(0xff78909c));
        deco((c) {
          final ink = Paint()
            ..color = const Color(0xff455a64)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..strokeCap = StrokeCap.round;
          c.drawArc(Rect.fromCenter(center: o + const Offset(5, 0), width: 3, height: 2.4), math.pi, math.pi, false, ink);
          c.drawArc(Rect.fromCenter(center: o + const Offset(11, 0), width: 3, height: 2.4), math.pi, math.pi, false, ink);
          for (final dx in [0.0, 8.0, 15.0]) {
            drop(c, o + Offset(dx, 12 + (dx == 8 ? 3 : 0)), 2.2, const Color(0xff4fc3f7));
          }
        });
        extent(Rect.fromLTRB(o.dx - 4, o.dy + 6, o.dx + 20, o.dy + 18));
      case 'butterfly':
        for (final (o, k, col) in [(Offset(all.right + 6, all.top + 10), 1.0, const Color(0xffab47bc)), (Offset(all.left - 8, all.top + 30), 0.75, const Color(0xff29b6f6))]) {
          _zoomAt(o, 1.5);
          final wings = Path()
            ..addOval(Rect.fromCenter(center: o + Offset(-4.5 * k, -3 * k), width: 8 * k, height: 9 * k))
            ..addOval(Rect.fromCenter(center: o + Offset(4.5 * k, -3 * k), width: 8 * k, height: 9 * k))
            ..addOval(Rect.fromCenter(center: o + Offset(-3.5 * k, 3.5 * k), width: 6 * k, height: 6 * k))
            ..addOval(Rect.fromCenter(center: o + Offset(3.5 * k, 3.5 * k), width: 6 * k, height: 6 * k));
          shape(wings, grad(wings.getBounds(), col), outline: _darken(col, 0.55), width: 1);
          deco((c) {
            c.drawLine(o + Offset(0, -5 * k), o + Offset(0, 6 * k), Paint()
              ..color = _ink
              ..strokeWidth = 1.8 * k
              ..strokeCap = StrokeCap.round);
            for (final sx in [-1.0, 1.0]) {
              c.drawCircle(o + Offset(sx * 4.5 * k, -3 * k), 1.4 * k, Paint()..color = Colors.white.withValues(alpha: 0.8));
            }
          });
        }
      case 'fireflies':
        for (final (o, r) in [(Offset(all.left - 8, all.top + 10), 2.4), (Offset(all.right + 8, all.top + 4), 2.0), (Offset(all.right + 4, all.top + 34), 2.6), (Offset(all.left - 4, b.bottom - 10), 2.0), (Offset(all.right + 9, b.bottom - 4), 1.6)]) {
          _zoomAt(o, 1.5);
          extent(Rect.fromCircle(center: o, radius: r + 4));
          deco((c) {
            c.drawCircle(o, r * 3, Paint()
              ..color = const Color(0xffc6ff00).withValues(alpha: 0.45)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
            c.drawCircle(o, r, Paint()..color = const Color(0xfff4ff81));
          });
        }
      case 'snow':
        for (final (o, r) in [(Offset(all.left - 6, all.top + 6), 4.5), (Offset(all.right + 6, all.top + 16), 3.8), (Offset(all.left - 2, b.bottom - 14), 3.2), (Offset(all.right + 4, b.bottom - 2), 3.0)]) {
          _zoomAt(o, 1.5);
          extent(Rect.fromCircle(center: o, radius: r + 1));
          deco((c) {
            _snowflake(c, o, r, const Color(0xff4fc3f7));
            c.drawCircle(o, 1, Paint()..color = const Color(0xff4fc3f7));
          });
        }
    }
  }
}

enum _Mode { measure, silhouette, paint }
