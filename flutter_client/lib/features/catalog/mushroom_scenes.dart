import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart' show SpeciesIcon;
import 'package:flutter_client/features/catalog/catalog_motion.dart' show seg;

/// Ігрові сценки зі значком гриба (рішення PO 2026-11-16): довге натискання на значок виду →
/// коло анімацій → сценка-історія на окремій «сцені» з цим самим грибом:
/// сон, батут, дискотека, чих, ріст, дощ і веселка.

const double kStageW = 300;
const double kStageH = 230;
const double kGround = 195;
const double kMush = 76;

/// Поза гриба: зсув від центру землі, поворот (навколо низу ніжки), масштаб, прозорість.
class Pose {
  const Pose({this.dx = 0, this.dy = 0, this.rot = 0, this.sx = 1, this.sy = 1, this.opacity = 1});

  final double dx, dy, rot, sx, sy, opacity;
}

double _eo(double x) => Curves.easeOutCubic.transform(x);
double _eio(double x) => Curves.easeInOutCubic.transform(x);
double _back(double x) => Curves.easeOutBack.transform(x);
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Стрибок по дузі з (x0,y0) у (x1,y1) — як частка [p] і висота дуги [h].
Offset _hop(Offset a, Offset b, double p, double h) =>
    Offset(_lerp(a.dx, b.dx, p), _lerp(a.dy, b.dy, p) - h * 4 * p * (1 - p));

void _text(Canvas c, String s, Offset center, double size, Color color,
    {FontWeight weight = FontWeight.w800, double opacity = 1}) {
  if (opacity <= 0) return;
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: weight, color: color.withValues(alpha: opacity))),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

void _sparkles(Canvas c, Offset center, double p, int seed, {double radius = 60, Color color = const Color(0xffffc928)}) {
  if (p <= 0 || p >= 1) return;
  final r = math.Random(seed);
  for (var i = 0; i < 10; i++) {
    final a = r.nextDouble() * math.pi * 2;
    final d = radius * (0.4 + 0.6 * r.nextDouble()) * _eo(p);
    final pos = center + Offset(math.cos(a), math.sin(a)) * d;
    final s = (4 + r.nextDouble() * 4) * math.sin(math.pi * p);
    final paint = Paint()..color = color.withValues(alpha: 1 - p * 0.6);
    final star = Path()
      ..moveTo(pos.dx, pos.dy - s)
      ..quadraticBezierTo(pos.dx, pos.dy, pos.dx + s, pos.dy)
      ..quadraticBezierTo(pos.dx, pos.dy, pos.dx, pos.dy + s)
      ..quadraticBezierTo(pos.dx, pos.dy, pos.dx - s, pos.dy)
      ..quadraticBezierTo(pos.dx, pos.dy, pos.dx, pos.dy - s);
    c.drawPath(star, paint);
  }
}

void _sun(Canvas c, Offset at, double p, double t) {
  if (p <= 0) return;
  final rays = Paint()
    ..color = const Color(0xffffc928).withValues(alpha: p)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 10; i++) {
    final a = i * math.pi / 5 + t * 4;
    c.drawLine(at + Offset(math.cos(a), math.sin(a)) * 22 * p, at + Offset(math.cos(a), math.sin(a)) * 30 * p, rays);
  }
  c.drawCircle(at, 16 * p, Paint()..color = const Color(0xffffd54f));
}

void _cloud(Canvas c, Offset at, double scale, {Color color = Colors.white, double opacity = 1}) {
  if (opacity <= 0) return;
  final p = Paint()..color = color.withValues(alpha: opacity);
  for (final (dx, dy, r) in [(-26.0, 6.0, 16.0), (-6.0, -6.0, 22.0), (18.0, 2.0, 18.0), (34.0, 10.0, 12.0), (0.0, 12.0, 16.0)]) {
    c.drawCircle(at + Offset(dx, dy) * scale, r * scale, p);
  }
}

/// Сценка: поза гриба в часі і малюнки за ним (back) та перед ним (front).
abstract class MushroomScene {
  const MushroomScene();

  String get id;
  String get emoji;
  String get label;
  Duration get duration;

  Pose pose(double t);
  void back(Canvas c, double t) {}
  void front(Canvas c, double t) {}
}

// ─── 😴 Сон ─────────────────────────────────────────────────────────────────

class SleepScene extends MushroomScene {
  const SleepScene();

  @override
  String get id => 'sleep';
  @override
  String get emoji => '😴';
  @override
  String get label => 'Сон';
  @override
  Duration get duration => const Duration(milliseconds: 7500);

  static const _mattress = 150.0;
  static const _lie = Offset(150, 122);

  double _bedK(double t) => _back(seg(t, 0.04, 0.16)) * (1 - _eio(seg(t, 0.94, 1.0)));
  double _night(double t) => seg(t, 0.02, 0.14) - seg(t, 0.9, 0.98);

  @override
  Pose pose(double t) {
    Offset base = const Offset(150, kGround);
    var rot = 0.0, sy = 1.0;
    if (t < 0.16) {
      rot = -0.12 * math.sin(math.pi * seg(t, 0.08, 0.16)); // дивиться на ліжко
    } else if (t < 0.26) {
      base = _hop(const Offset(150, kGround), const Offset(150, _mattress), _eio(seg(t, 0.16, 0.26)), 36);
    } else if (t < 0.34) {
      final p = _eio(seg(t, 0.26, 0.34));
      base = Offset.lerp(const Offset(150, _mattress), _lie, p)!;
      rot = -math.pi / 2 * p;
    } else if (t < 0.9) {
      base = _lie;
      rot = -math.pi / 2;
      sy = 1 + 0.025 * math.sin(seg(t, 0.44, 0.84) * math.pi * 8); // дихає
      if (t > 0.85 && t < 0.88) base += Offset(0, -9 * math.sin(math.pi * seg(t, 0.85, 0.88))); // будильник!
    } else if (t < 0.95) {
      final p = _eio(seg(t, 0.9, 0.95));
      base = Offset.lerp(_lie, const Offset(150, _mattress), p)!;
      rot = -math.pi / 2 * (1 - p);
    } else {
      base = _hop(const Offset(150, _mattress), const Offset(150, kGround), _eio(seg(t, 0.95, 1.0)), 20);
    }
    return Pose(dx: base.dx - 150, dy: base.dy - kGround, rot: rot, sy: sy);
  }

  @override
  void back(Canvas c, double t) {
    final night = _night(t);
    if (night > 0) {
      c.drawRect(const Rect.fromLTWH(0, 0, kStageW, kGround), Paint()..color = const Color(0xff1a2347).withValues(alpha: 0.85 * night));
      // Місяць-серпик і зорі, що мерехтять.
      final moon = Offset(250, 42 - 10 * (1 - night));
      c.drawCircle(moon, 16, Paint()..color = const Color(0xfffff3c4).withValues(alpha: night));
      c.drawCircle(moon + const Offset(7, -5), 14, Paint()..color = const Color(0xff1a2347).withValues(alpha: night));
      final r = math.Random(7);
      for (var i = 0; i < 14; i++) {
        final p = Offset(r.nextDouble() * kStageW, r.nextDouble() * 90);
        final tw = 0.5 + 0.5 * math.sin(t * 40 + i);
        c.drawCircle(p, 1.2 + tw, Paint()..color = Colors.white.withValues(alpha: night * (0.4 + 0.6 * tw)));
      }
    }
    final k = _bedK(t);
    if (k <= 0) return;
    c.save();
    c.translate(0, kGround);
    c.scale(1, k);
    c.translate(0, -kGround);
    final wood = Paint()..color = const Color(0xff8d5a36);
    // Узголів'я, ніжки, каркас.
    c.drawRRect(RRect.fromLTRBR(50, kGround - 82, 62, kGround, const Radius.circular(4)), wood);
    c.drawRRect(RRect.fromLTRBR(238, kGround - 62, 250, kGround, const Radius.circular(4)), wood);
    c.drawRect(const Rect.fromLTRB(56, kGround - 30, 244, kGround - 18), wood);
    // Матрац і простирадло.
    c.drawRRect(RRect.fromLTRBR(58, _mattress, 242, kGround - 28, const Radius.circular(6)), Paint()..color = Colors.white);
    c.drawRRect(RRect.fromLTRBR(58, _mattress, 242, _mattress + 6, const Radius.circular(4)), Paint()..color = const Color(0xffe3eaf5));
    // Подушка.
    final pillow = seg(t, 0.12, 0.18);
    if (pillow > 0) {
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(88, 140), width: 46 * pillow, height: 18 * pillow), const Radius.circular(9)),
        Paint()..color = const Color(0xfffff8e1),
      );
    }
    // Тумбочка з будильником.
    c.drawRRect(RRect.fromLTRBR(256, kGround - 34, 290, kGround, const Radius.circular(3)), Paint()..color = const Color(0xffa1693f));
    c.restore();
  }

  @override
  void front(Canvas c, double t) {
    final k = _bedK(t);
    // Ковдра: насувається від ніг, дихає, злітає від будильника.
    final cover = _eio(seg(t, 0.34, 0.44));
    final fly = _eio(seg(t, 0.88, 0.93));
    if (cover > 0 && fly < 1 && k > 0) {
      final breath = 2.5 * math.sin(seg(t, 0.44, 0.84) * math.pi * 8);
      final left = _lerp(242, 116, cover);
      c.save();
      c.translate(fly * 190, -fly * 70);
      c.rotate(fly * 0.4);
      final rect = Rect.fromLTRB(left, 128 - breath, 246, 162);
      c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), Paint()..color = const Color(0xff5c8fd6));
      final stripe = Paint()..color = Colors.white.withValues(alpha: 0.55);
      for (var x = rect.left + 10; x < rect.right - 4; x += 16) {
        c.drawRect(Rect.fromLTWH(x, rect.top + 2, 4, rect.height - 4), stripe);
      }
      c.drawRRect(RRect.fromLTRBR(rect.left, rect.top, rect.left + 10, rect.bottom, const Radius.circular(8)), Paint()..color = const Color(0xff3f6fb5));
      c.restore();
    }
    // «z» з-над подушки — одна за одною.
    for (var i = 0; i < 4; i++) {
      final p = seg(t, 0.46 + i * 0.09, 0.62 + i * 0.09);
      if (p <= 0 || p >= 1 || t > 0.85) continue;
      final pos = Offset(84 + 26 * p + 6 * math.sin(p * 9), 104 - 70 * p);
      _text(c, 'z', pos, 12 + 14 * p, Colors.white, opacity: math.sin(math.pi * p));
    }
    // Будильник: «дзинь!»
    if (k > 0) {
      final ring = seg(t, 0.84, 0.9);
      final shake = ring > 0 && ring < 1 ? math.sin(ring * math.pi * 24) * 0.35 : 0.0;
      c.save();
      c.translate(273, kGround - 44);
      c.scale(k, k);
      c.rotate(shake);
      c.drawCircle(Offset.zero, 10, Paint()..color = const Color(0xffe53935));
      c.drawCircle(Offset.zero, 7, Paint()..color = Colors.white);
      final hand = Paint()
        ..color = Colors.black87
        ..strokeWidth = 1.4;
      c.drawLine(Offset.zero, const Offset(0, -5), hand);
      c.drawLine(Offset.zero, const Offset(4, 0), hand);
      c.drawCircle(const Offset(-7, -9), 3.5, Paint()..color = const Color(0xffe53935));
      c.drawCircle(const Offset(7, -9), 3.5, Paint()..color = const Color(0xffe53935));
      c.restore();
      if (ring > 0 && ring < 1) _text(c, 'дзинь!', const Offset(262, 118), 14, const Color(0xffffeb3b), opacity: math.sin(math.pi * ring));
    }
  }
}

// ─── 🤸 Батут ───────────────────────────────────────────────────────────────

class TrampolineScene extends MushroomScene {
  const TrampolineScene();

  @override
  String get id => 'trampoline';
  @override
  String get emoji => '🤸';
  @override
  String get label => 'Батут';
  @override
  Duration get duration => const Duration(milliseconds: 6500);

  static const _mat = kGround - 20;
  static const _bounces = [(0.18, 0.36, 40.0), (0.36, 0.56, 62.0), (0.56, 0.82, 88.0)];

  double _k(double t) => _back(seg(t, 0.0, 0.1)) * (1 - _eio(seg(t, 0.9, 0.98)));

  /// Наскільки прогнувся батут (гриб приземляється / відштовхується).
  double _dip(double t) {
    for (final (a, b, _) in _bounces) {
      final p = seg(t, a, b);
      if (p > 0 && p < 1) {
        final edge = math.min(p, 1 - p);
        return edge < 0.1 ? 9 * (1 - edge / 0.1) : 0;
      }
    }
    if (t >= 0.16 && t < 0.18) return 9;
    return 0;
  }

  @override
  Pose pose(double t) {
    var base = const Offset(150, kGround);
    var rot = 0.0, sx = 1.0, sy = 1.0;
    if (t < 0.1) {
      sy = 1 - 0.12 * math.sin(math.pi * seg(t, 0.04, 0.1)); // присідає перед стрибком
    } else if (t < 0.18) {
      base = _hop(const Offset(150, kGround), const Offset(150, _mat), _eio(seg(t, 0.1, 0.18)), 30);
    } else if (t < 0.82) {
      for (final (i, (a, b, h)) in _bounces.indexed) {
        final p = seg(t, a, b);
        if (p > 0 && p < 1) {
          base = Offset(150, _mat + _dip(t) - h * 4 * p * (1 - p));
          final stretch = math.sin(math.pi * p);
          sy = 1 + 0.12 * stretch;
          sx = 1 - 0.06 * stretch;
          if (math.min(p, 1 - p) < 0.08) {
            sy = 0.82;
            sx = 1.12;
          }
          if (i == 2) rot = 2 * math.pi * _eio(seg(p, 0.25, 0.75)); // сальто
        }
      }
    } else if (t < 0.9) {
      base = _hop(const Offset(150, _mat), const Offset(232, kGround), _eio(seg(t, 0.82, 0.9)), 40);
    } else {
      base = const Offset(232, kGround);
      rot = 0.45 * math.sin(math.pi * seg(t, 0.92, 1.0)); // уклін
    }
    return Pose(dx: base.dx - 150, dy: base.dy - kGround, rot: rot, sx: sx, sy: sy);
  }

  @override
  void back(Canvas c, double t) {
    final k = _k(t);
    if (k <= 0) return;
    c.save();
    c.translate(150, kGround);
    c.scale(k, k);
    c.translate(-150, -kGround);
    final leg = Paint()
      ..color = const Color(0xff37474f)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final x in [92.0, 124.0, 176.0, 208.0]) {
      c.drawLine(Offset(x, _mat + 2), Offset(x + (x < 150 ? -6 : 6), kGround), leg);
    }
    final dip = _dip(t);
    final mat = Path()
      ..moveTo(82, _mat)
      ..quadraticBezierTo(150, _mat + 2 * dip + 6, 218, _mat)
      ..quadraticBezierTo(150, _mat - 8, 82, _mat);
    c.drawPath(mat, Paint()..color = const Color(0xff263238));
    c.drawOval(Rect.fromCenter(center: const Offset(150, _mat), width: 140, height: 14),
        Paint()
          ..color = const Color(0xff1e88e5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    c.restore();
  }

  @override
  void front(Canvas c, double t) {
    // Іскри на вершині сальто, пил при приземленні, «браво!» після уклону.
    final last = _bounces.last;
    final p = seg(t, last.$1, last.$2);
    _sparkles(c, Offset(150, _mat - last.$3 - 40), seg(p, 0.35, 0.8), 3, radius: 50);
    final dust = seg(t, 0.88, 0.97);
    if (dust > 0 && dust < 1) {
      for (var i = 0; i < 6; i++) {
        final dir = i < 3 ? -1 : 1;
        final pos = Offset(232 + dir * (8 + 26 * _eo(dust)) * (1 + i % 3 * 0.4), kGround - 4 - 6 * (i % 3) * dust);
        c.drawCircle(pos, 6 + 6 * dust, Paint()..color = const Color(0xffd7c4a3).withValues(alpha: 0.7 * (1 - dust)));
      }
    }
    _text(c, 'браво!', const Offset(232, 70), 18, AppTheme.accentOrange, opacity: math.sin(math.pi * seg(t, 0.9, 1.0)));
  }
}

// ─── 🪩 Дискотека ───────────────────────────────────────────────────────────

class DiscoScene extends MushroomScene {
  const DiscoScene();

  @override
  String get id => 'disco';
  @override
  String get emoji => '🪩';
  @override
  String get label => 'Дискотека';
  @override
  Duration get duration => const Duration(milliseconds: 7000);

  double _dark(double t) => seg(t, 0.0, 0.1) - seg(t, 0.88, 0.98);
  double _ballY(double t) => -24 + 72 * _eo(seg(t, 0.02, 0.14)) - 72 * _eio(seg(t, 0.88, 1.0));

  static const _colors = [Color(0xffff4081), Color(0xff40c4ff), Color(0xffffeb3b), Color(0xff69f0ae), Color(0xffb388ff)];

  @override
  Pose pose(double t) {
    var dx = 0.0, dy = 0.0, rot = 0.0, sx = 1.0, sy = 1.0;
    if (t >= 0.14 && t < 0.34) {
      final p = seg(t, 0.14, 0.34); // кроки вбік з підскоками
      dx = 34 * math.sin(2 * math.pi * 2 * p);
      dy = -10 * math.sin(2 * math.pi * 4 * p).abs();
      rot = 0.18 * math.sin(2 * math.pi * 2 * p);
    } else if (t < 0.5 && t >= 0.34) {
      final p = seg(t, 0.34, 0.5); // дві обертки на місці
      rot = 4 * math.pi * _eio(p);
      dy = -16 * math.sin(math.pi * p);
    } else if (t < 0.72 && t >= 0.5) {
      final p = seg(t, 0.5, 0.72); // пружинить у ритм
      sy = 1 + 0.14 * math.sin(2 * math.pi * 6 * p);
      sx = 1 - 0.07 * math.sin(2 * math.pi * 6 * p);
      rot = 0.2 * math.sin(2 * math.pi * 3 * p);
    } else if (t < 0.8 && t >= 0.72) {
      final p = seg(t, 0.72, 0.8); // стрибок у фінальну позу
      dy = -46 * 4 * p * (1 - p);
      rot = -0.3 * p;
    } else if (t >= 0.8 && t < 0.9) {
      rot = -0.3;
      sx = 1.06;
      sy = 0.96;
    } else if (t >= 0.9) {
      rot = -0.3 * (1 - _eio(seg(t, 0.9, 1.0)));
    }
    return Pose(dx: dx, dy: dy, rot: rot, sx: sx, sy: sy);
  }

  @override
  void back(Canvas c, double t) {
    final dark = _dark(t);
    if (dark <= 0) return;
    c.drawRect(const Rect.fromLTWH(0, 0, kStageW, kStageH), Paint()..color = const Color(0xff12082b).withValues(alpha: 0.88 * dark));
    final lights = seg(t, 0.12, 0.88) > 0 && t < 0.88;
    if (!lights) return;
    final ball = Offset(150, _ballY(t));
    for (var i = 0; i < _colors.length; i++) {
      final spot = Offset(150 + 120 * math.sin(t * 9 + i * 1.7), 120 + 70 * math.sin(t * 7.3 + i * 2.3));
      final beam = Path()
        ..moveTo(ball.dx, ball.dy)
        ..lineTo(spot.dx - 18, spot.dy)
        ..lineTo(spot.dx + 18, spot.dy)
        ..close();
      c.drawPath(beam, Paint()..color = _colors[i].withValues(alpha: 0.12 * dark));
      c.drawCircle(spot, 22, Paint()..color = _colors[i].withValues(alpha: 0.35 * dark));
    }
  }

  @override
  void front(Canvas c, double t) {
    final y = _ballY(t);
    if (y > -20) {
      c.drawLine(const Offset(150, 0), Offset(150, y - 16), Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.2);
      final ball = Offset(150, y);
      c.drawCircle(ball, 16, Paint()..color = const Color(0xffb0bec5));
      // Дзеркальні грані мерехтять.
      for (var row = -2; row <= 2; row++) {
        for (var col = -3; col <= 3; col++) {
          final p = ball + Offset(col * 4.6 + (t * 60 % 4.6), row * 5.6);
          if ((p - ball).distance > 14) continue;
          final shine = 0.5 + 0.5 * math.sin(t * 50 + row * 3 + col * 7);
          c.drawRect(Rect.fromCenter(center: p, width: 3.4, height: 4.2), Paint()..color = Color.lerp(const Color(0xff78909c), Colors.white, shine)!);
        }
      }
    }
    // Ноти летять з обох боків.
    if (t > 0.14 && t < 0.86) {
      for (var i = 0; i < 6; i++) {
        final p = ((t - 0.14) * 3 + i / 6) % 1;
        final left = i.isEven;
        final pos = Offset(left ? 40 + 30 * p : 260 - 30 * p, 180 - 130 * p) + Offset(8 * math.sin(p * 12), 0);
        _text(c, i % 3 == 0 ? '♫' : '♪', pos, 18, _colors[i % _colors.length], opacity: math.sin(math.pi * p));
      }
    }
    _sparkles(c, const Offset(150, 130), seg(t, 0.78, 0.92), 11, radius: 80, color: const Color(0xffff80ab));
  }
}

// ─── 🤧 Чих ─────────────────────────────────────────────────────────────────

class SneezeScene extends MushroomScene {
  const SneezeScene();

  @override
  String get id => 'sneeze';
  @override
  String get emoji => '🤧';
  @override
  String get label => 'Чих';
  @override
  Duration get duration => const Duration(milliseconds: 6000);

  static const _cap = Offset(158, kGround - kMush + 14);

  @override
  Pose pose(double t) {
    var dx = 0.0, rot = 0.0, sx = 1.0, sy = 1.0;
    if (t >= 0.14 && t < 0.2) {
      rot = 0.05 * math.sin(seg(t, 0.14, 0.2) * math.pi * 6); // лоскоче
    } else if (t >= 0.2 && t < 0.42) {
      // Три вдихи: «а…», «а-а…», «а-а-а…» — тягнеться вгору, відхиляється назад.
      final stage = t < 0.27 ? 1 : (t < 0.34 ? 2 : 3);
      final p = seg(t, 0.2 + (stage - 1) * 0.07, 0.25 + (stage - 1) * 0.07);
      final k = (stage - 1 + _eo(p)) / 3;
      sy = 1 + 0.26 * k;
      sx = 1 - 0.08 * k;
      rot = -0.18 * k;
    } else if (t >= 0.42 && t < 0.56) {
      final p = seg(t, 0.42, 0.56); // АПЧХИ — ривок уперед і назад
      final snap = p < 0.15 ? p / 0.15 : 1 - _eo((p - 0.15) / 0.85);
      rot = 0.38 * snap;
      dx = 12 * snap;
      sy = 1 - 0.2 * snap;
      sx = 1 + 0.1 * snap;
    } else if (t >= 0.86 && t < 0.94) {
      dx = 3 * math.sin(seg(t, 0.86, 0.94) * math.pi * 6); // обтрушується
    }
    return Pose(dx: dx, rot: rot, sx: sx, sy: sy);
  }

  /// Спори: вилітають із шапки, падають і де-не-де проростають маленькими грибочками.
  List<({Offset pos, bool landed, int i})> _spores(double t) {
    final q = seg(t, 0.42, 0.74);
    if (q <= 0) return const [];
    final r = math.Random(5);
    final out = <({Offset pos, bool landed, int i})>[];
    for (var i = 0; i < 40; i++) {
      final a = -(0.15 + r.nextDouble() * 1.1);
      final v = 70 + r.nextDouble() * 80; // падають у межах сцени
      final vx = math.cos(a) * v, vy = math.sin(a) * v;
      final sway = 6 * math.sin(q * 10 + i);
      var p = _cap + Offset(vx * q * 1.1 + sway, vy * q * 1.1 + 230 * q * q);
      final landed = p.dy >= kGround - 2;
      if (landed) p = Offset(p.dx, kGround - 2);
      out.add((pos: p, landed: landed, i: i));
    }
    return out;
  }

  @override
  void front(Canvas c, double t) {
    // Пушинка кульбаби падає і лоскоче шапку, від чиху — відлітає.
    final fall = seg(t, 0.0, 0.14);
    final blow = _eo(seg(t, 0.42, 0.6));
    if (blow < 1) {
      final pos = Offset(_lerp(60, _cap.dx, fall) + 14 * math.sin(fall * 9) * (1 - fall), _lerp(18, _cap.dy - 8, _eo(fall))) +
          Offset(260 * blow, -120 * blow);
      final fluff = Paint()
        ..color = const Color(0xff9e9e9e)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 10; i++) {
        final a = i * math.pi / 5 + fall * 3;
        final tip = pos + Offset(math.cos(a), math.sin(a)) * 8;
        c.drawLine(pos, tip, fluff);
        c.drawCircle(tip, 1.4, Paint()..color = Colors.white);
      }
      c.drawLine(pos, pos + const Offset(0, 11), fluff);
      c.drawCircle(pos, 2, Paint()..color = const Color(0xff8d6e63));
    }
    // «а…», «а-а…», «а-а-а…»
    for (final (i, s) in ['а…', 'а-а…', 'а-а-а…'].indexed) {
      final p = seg(t, 0.2 + i * 0.07, 0.27 + i * 0.07);
      if (p > 0 && p < 1 && t < 0.42) _text(c, s, Offset(222, 96 - i * 12.0), 13 + i * 3.0, AppTheme.darkGreen, opacity: math.sin(math.pi * p) * 0.9 + 0.1);
    }
    final achoo = seg(t, 0.42, 0.62);
    if (achoo > 0 && achoo < 1) {
      _text(c, 'АПЧХИ!', const Offset(214, 62), 18 + 10 * _back(seg(achoo, 0, 0.3)), const Color(0xffd84315), opacity: 1 - seg(achoo, 0.7, 1));
    }
    final sporePaint = Paint()..color = const Color(0xffa1887f);
    for (final s in _spores(t)) {
      if (t > 0.95) continue;
      c.drawCircle(s.pos, s.landed ? 1.6 : 2.2, sporePaint..color = const Color(0xffa1887f).withValues(alpha: s.landed ? 0.6 : 0.9));
    }
    // Проростають грибочки там, де впали деякі спори.
    final grow = seg(t, 0.74, 0.86);
    final fade = 1 - seg(t, 0.94, 1.0);
    if (grow > 0) {
      final landed = _spores(0.74).where((s) => s.landed && s.i % 5 == 0 && s.pos.dx < kStageW - 12).take(6);
      for (final s in landed) {
        final h = 20 * _back(grow) * fade;
        if (h <= 0) continue;
        final bob = math.sin((t - 0.86) * 30 + s.i) * (t > 0.86 ? 1.5 : 0);
        final at = Offset(s.pos.dx, kGround);
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(at.dx - 1.8, at.dy - h * 0.6, 3.6, h * 0.6), const Radius.circular(1.5)),
            Paint()..color = const Color(0xfffff3e0));
        c.drawArc(Rect.fromCenter(center: at + Offset(bob, -h * 0.6), width: h * 0.9, height: h * 0.8), math.pi, math.pi, true,
            Paint()..color = const Color(0xffb5651d));
      }
    }
  }
}

// ─── 🌱 Ріст ────────────────────────────────────────────────────────────────

class GrowScene extends MushroomScene {
  const GrowScene();

  @override
  String get id => 'grow';
  @override
  String get emoji => '🌱';
  @override
  String get label => 'Ріст';
  @override
  Duration get duration => const Duration(milliseconds: 7000);

  @override
  Pose pose(double t) {
    if (t < 0.14) {
      final p = _eio(seg(t, 0.02, 0.14)); // ховається в землю
      return Pose(sy: 1 - p, sx: 1 - 0.3 * p, opacity: 1 - seg(t, 0.1, 0.14));
    }
    if (t < 0.7) return const Pose(sy: 0, opacity: 0);
    final p = seg(t, 0.7, 0.88); // виростає з пружинкою
    final g = _back(p);
    var dy = 0.0;
    if (t > 0.9) dy = -14 * math.sin(math.pi * seg(t, 0.9, 0.97));
    return Pose(sx: 0.2 + 0.8 * g, sy: g, dy: dy, opacity: seg(p, 0, 0.1));
  }

  @override
  void back(Canvas c, double t) {
    // Земля в розрізі.
    final soil = seg(t, 0.0, 0.08) * (1 - seg(t, 0.95, 1.0));
    if (soil > 0) {
      c.drawRect(const Rect.fromLTRB(0, kGround + 4, kStageW, kStageH), Paint()..color = const Color(0xff6d4c33).withValues(alpha: soil));
      final r = math.Random(2);
      for (var i = 0; i < 30; i++) {
        c.drawCircle(Offset(r.nextDouble() * kStageW, kGround + 8 + r.nextDouble() * 28), 1 + r.nextDouble() * 1.5,
            Paint()..color = const Color(0xff4e342e).withValues(alpha: soil));
      }
    }
    // Хмара і дощ.
    final cloudIn = _eo(seg(t, 0.3, 0.38));
    final cloudOut = _eio(seg(t, 0.5, 0.6));
    if (cloudIn > 0 && cloudOut < 1) {
      _cloud(c, Offset(_lerp(-40, 150, cloudIn) + 220 * cloudOut, 42), 1.1, color: const Color(0xffb0bec5));
    }
    _sun(c, const Offset(250, 40), _eo(seg(t, 0.72, 0.84)) * (1 - seg(t, 0.96, 1.0)), t);
  }

  @override
  void front(Canvas c, double t) {
    // Грудочки землі, коли гриб ховається.
    final dirt = seg(t, 0.08, 0.2);
    if (dirt > 0 && dirt < 1) {
      final r = math.Random(4);
      for (var i = 0; i < 10; i++) {
        final vx = (r.nextDouble() - 0.5) * 120, vy = -60 - r.nextDouble() * 60;
        c.drawCircle(Offset(150 + vx * dirt, kGround + vy * dirt + 200 * dirt * dirt), 2.5, Paint()..color = const Color(0xff6d4c33));
      }
    }
    // Спора спускається і зникає в ґрунті.
    final spore = seg(t, 0.16, 0.3);
    if (spore > 0 && t < 0.33) {
      final pos = Offset(120 + 30 * spore + 12 * math.sin(spore * 10), _lerp(10, kGround + 6, _eio(spore)));
      c.drawCircle(pos, 6, Paint()..color = const Color(0xffffecb3).withValues(alpha: 0.35 * (1 - seg(t, 0.3, 0.33))));
      c.drawCircle(pos, 3, Paint()..color = const Color(0xffffca28).withValues(alpha: 1 - seg(t, 0.3, 0.33)));
    }
    // Дощ.
    final rain = seg(t, 0.34, 0.52);
    if (rain > 0 && rain < 1) {
      final r = math.Random(9);
      final drop = Paint()
        ..color = const Color(0xff4fc3f7)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 26; i++) {
        final x = 100 + r.nextDouble() * 110;
        final y = 58 + ((r.nextDouble() + rain * 4) % 1) * (kGround - 58);
        c.drawLine(Offset(x, y), Offset(x - 1.5, y + 8), drop);
      }
    }
    // Грибниця під землею: білі нитки розростаються з місця, де лягла спора.
    final myc = seg(t, 0.44, 0.68) * (1 - seg(t, 0.95, 1.0));
    if (myc > 0) {
      final r = math.Random(12);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 9; i++) {
        final a = (i / 9) * math.pi + (r.nextDouble() - 0.5) * 0.3;
        final len = 40 + r.nextDouble() * 70;
        final end = Offset(150 + math.cos(a) * len, kGround + 8 + math.sin(a).abs() * 22);
        final mid = Offset((150 + end.dx) / 2 + (r.nextDouble() - 0.5) * 20, kGround + 10 + r.nextDouble() * 12);
        final path = Path()
          ..moveTo(150, kGround + 8)
          ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
        for (final m in path.computeMetrics()) {
          c.drawPath(m.extractPath(0, m.length * _eo(myc)), paint);
        }
      }
    }
    // Горбик і паросток.
    final bump = seg(t, 0.62, 0.72) * (1 - seg(t, 0.72, 0.78));
    if (bump > 0) {
      c.drawOval(Rect.fromCenter(center: const Offset(150, kGround), width: 30 * bump, height: 12 * bump), Paint()..color = const Color(0xff795548));
      c.drawCircle(Offset(150, kGround - 6 * bump), 3 * bump, Paint()..color = Colors.white);
    }
    _sparkles(c, const Offset(150, kGround - 50), seg(t, 0.86, 0.98), 21, radius: 70);
    _text(c, 'та-дам!', const Offset(150, 30), 18, AppTheme.accentOrange, opacity: math.sin(math.pi * seg(t, 0.88, 1.0)));
  }
}

// ─── 🌈 Дощ і веселка ───────────────────────────────────────────────────────

class RainScene extends MushroomScene {
  const RainScene();

  @override
  String get id => 'rain';
  @override
  String get emoji => '🌈';
  @override
  String get label => 'Дощ';
  @override
  Duration get duration => const Duration(milliseconds: 7000);

  static const _puddle = Offset(212, kGround + 1);

  @override
  Pose pose(double t) {
    var base = const Offset(150, kGround);
    var rot = 0.0, sx = 1.0, sy = 1.0;
    if (t >= 0.14 && t < 0.42) {
      final p = seg(t, 0.14, 0.42); // радісно підстрибує під дощем
      base += Offset(0, -16 * math.sin(math.pi * ((p * 3) % 1)));
      rot = -0.1;
    } else if (t >= 0.44 && t < 0.54) {
      base = _hop(const Offset(150, kGround), _puddle, _eio(seg(t, 0.44, 0.54)), 50); // у калюжу!
    } else if (t >= 0.54) {
      base = _puddle;
      final splat = seg(t, 0.54, 0.62);
      if (splat > 0 && splat < 1) {
        sy = 1 - 0.22 * math.sin(math.pi * splat);
        sx = 1 + 0.12 * math.sin(math.pi * splat);
      }
      if (t > 0.72 && t < 0.92) rot = -0.14 * math.sin(math.pi * seg(t, 0.72, 0.92)); // дивиться на веселку
    }
    return Pose(dx: base.dx - 150, dy: base.dy - kGround, rot: rot, sx: sx, sy: sy);
  }

  @override
  void back(Canvas c, double t) {
    final grey = seg(t, 0.0, 0.1) - seg(t, 0.6, 0.72);
    if (grey > 0) c.drawRect(const Rect.fromLTWH(0, 0, kStageW, kGround), Paint()..color = const Color(0xff78909c).withValues(alpha: 0.45 * grey));
    // Веселка малюється дугою зліва направо.
    final bow = _eio(seg(t, 0.7, 0.9));
    final bowFade = 1 - seg(t, 0.95, 1.0);
    if (bow > 0) {
      const colors = [Color(0xffe53935), Color(0xfffb8c00), Color(0xfffdd835), Color(0xff43a047), Color(0xff1e88e5), Color(0xff3949ab), Color(0xff8e24aa)];
      for (var i = 0; i < colors.length; i++) {
        final rr = 140.0 - i * 6;
        c.drawArc(Rect.fromCircle(center: const Offset(150, kGround + 30), radius: rr), math.pi, math.pi * bow, false,
            Paint()
              ..color = colors[i].withValues(alpha: 0.75 * bowFade)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6);
      }
    }
    _sun(c, const Offset(48, 44), _eo(seg(t, 0.64, 0.76)) * bowFade, t);
    // Калюжа росте.
    final puddle = _eo(seg(t, 0.16, 0.46));
    if (puddle > 0) {
      c.drawOval(Rect.fromCenter(center: _puddle, width: 80 * puddle, height: 12 * puddle), Paint()..color = const Color(0xff64b5f6).withValues(alpha: 0.8));
    }
  }

  @override
  void front(Canvas c, double t) {
    final cloudIn = _eo(seg(t, 0.0, 0.12));
    final cloudOut = _eio(seg(t, 0.6, 0.72));
    if (cloudIn > 0 && cloudOut < 1) {
      _cloud(c, Offset(_lerp(-50, 160, cloudIn) + 240 * cloudOut, 40), 1.4, color: const Color(0xff90a4ae));
    }
    final rain = seg(t, 0.1, 0.62);
    if (rain > 0 && rain < 1) {
      final r = math.Random(3);
      final drop = Paint()
        ..color = const Color(0xff4fc3f7)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 40; i++) {
        final x = 70 + r.nextDouble() * 190 + 240 * cloudOut;
        final y = 60 + ((r.nextDouble() + rain * 7) % 1) * (kGround - 60);
        c.drawLine(Offset(x, y), Offset(x - 2, y + 9), drop);
      }
    }
    // Бризки з калюжі.
    final splash = seg(t, 0.53, 0.68);
    if (splash > 0 && splash < 1) {
      final r = math.Random(8);
      for (var i = 0; i < 14; i++) {
        final a = -math.pi * (0.1 + 0.8 * r.nextDouble());
        final v = 60 + r.nextDouble() * 60;
        final pos = _puddle + Offset(math.cos(a) * v * splash, math.sin(a) * v * splash + 140 * splash * splash);
        c.drawCircle(pos, 2.6, Paint()..color = const Color(0xff4fc3f7).withValues(alpha: 1 - splash));
      }
    }
    // Краплі стікають із шапки.
    final drip = seg(t, 0.66, 0.86);
    if (drip > 0 && drip < 1) {
      for (final (i, x) in [-24.0, 22.0].indexed) {
        final p = ((drip * 2) + i * 0.5) % 1;
        c.drawCircle(Offset(_puddle.dx + x, kGround - kMush * 0.62 + 40 * p), 2.4, Paint()..color = const Color(0xff4fc3f7).withValues(alpha: 1 - p));
      }
    }
  }
}

const kMushroomScenes = <MushroomScene>[SleepScene(), TrampolineScene(), DiscoScene(), SneezeScene(), GrowScene(), RainScene()];

// ─── Сцена ──────────────────────────────────────────────────────────────────

/// Сцена з небом і землею, на якій гриб виду грає [scene].
class MushroomStage extends StatefulWidget {
  const MushroomStage({super.key, required this.speciesId, required this.scene, this.autoplay = true});

  final String speciesId;
  final MushroomScene scene;
  final bool autoplay;

  @override
  State<MushroomStage> createState() => MushroomStageState();
}

class MushroomStageState extends State<MushroomStage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.scene.duration);

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) _c.forward();
  }

  void replay() => _c.forward(from: 0);

  bool get playing => _c.isAnimating;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: kStageW,
          height: kStageH,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final p = widget.scene.pose(t);
              return Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _StagePainter(widget.scene, t, back: true))),
                  Positioned(
                    left: 150 + p.dx - kMush / 2,
                    top: kGround + p.dy - kMush,
                    width: kMush,
                    height: kMush,
                    child: Opacity(
                      opacity: p.opacity.clamp(0.0, 1.0),
                      child: Transform(
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.identity()
                          ..rotateZ(p.rot)
                          ..scaleByDouble(p.sx, math.max(p.sy, 0.001), 1, 1),
                        child: SpeciesIcon(type: widget.speciesId, fallbackColor: const Color(0xff8d6e63), size: kMush),
                      ),
                    ),
                  ),
                  Positioned.fill(child: CustomPaint(painter: _StagePainter(widget.scene, t, back: false))),
                ],
              );
            },
          ),
        ),
      );
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.scene, this.t, {required this.back});

  final MushroomScene scene;
  final double t;
  final bool back;

  @override
  void paint(Canvas c, Size size) {
    if (back) {
      c.drawRect(
        const Rect.fromLTWH(0, 0, kStageW, kGround),
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xffbfe3f7), Color(0xfff3f7e8)])
              .createShader(const Rect.fromLTWH(0, 0, kStageW, kGround)),
      );
      c.drawRect(const Rect.fromLTRB(0, kGround, kStageW, kStageH), Paint()..color = const Color(0xff9ccc65));
      c.drawRect(const Rect.fromLTRB(0, kGround, kStageW, kGround + 4), Paint()..color = const Color(0xff7cb342));
      scene.back(c, t);
    } else {
      scene.front(c, t);
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => old.t != t || old.scene != scene;
}

/// Відкрити сценку у вікні: назва, сцена, «Ще раз».
Future<void> showMushroomScene(BuildContext context, {required String speciesId, required MushroomScene scene}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрити',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (context, a, _, child) => Transform.scale(
        scale: 0.85 + 0.15 * Curves.easeOutBack.transform(a.value),
        child: Opacity(opacity: a.value, child: child),
      ),
      pageBuilder: (context, _, __) => _SceneDialog(speciesId: speciesId, scene: scene),
    );

class _SceneDialog extends StatefulWidget {
  const _SceneDialog({required this.speciesId, required this.scene});

  final String speciesId;
  final MushroomScene scene;

  @override
  State<_SceneDialog> createState() => _SceneDialogState();
}

class _SceneDialogState extends State<_SceneDialog> {
  final _stage = GlobalKey<MushroomStageState>();

  @override
  Widget build(BuildContext context) => Center(
        child: Material(
          color: AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${widget.scene.emoji} ${widget.scene.label}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 56),
                  child: FittedBox(
                    child: MushroomStage(key: _stage, speciesId: widget.speciesId, scene: widget.scene),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('scene-replay'),
                      onPressed: () => _stage.currentState?.replay(),
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Ще раз'),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.darkGreen),
                    ),
                    TextButton(
                      key: const ValueKey('scene-close'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.darkGreen),
                      child: const Text('Закрити'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

// ─── Значок гриба з колом анімацій ──────────────────────────────────────────

/// Значок виду: довге натискання — дугою «вискакують» сценки; вибір — сценка грає.
class PlayfulSpeciesIcon extends StatelessWidget {
  const PlayfulSpeciesIcon({super.key, required this.speciesId, this.size = 40});

  final String speciesId;
  final double size;

  Future<void> _openMenu(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final box = context.findRenderObject()! as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    final picked = await showGeneralDialog<MushroomScene>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрити',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 480),
      pageBuilder: (context, a, _) => _RadialMenu(center: center, animation: a, speciesId: speciesId, iconSize: size),
    );
    if (picked != null && context.mounted) await showMushroomScene(context, speciesId: speciesId, scene: picked);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const ValueKey('icon-play'),
        onLongPress: () => _openMenu(context),
        child: SpeciesIcon(type: speciesId, fallbackColor: const Color(0xff8d6e63), size: size),
      );
}

class _RadialMenu extends StatelessWidget {
  const _RadialMenu({required this.center, required this.animation, required this.speciesId, required this.iconSize});

  final Offset center;
  final Animation<double> animation;
  final String speciesId;
  final double iconSize;

  static const _radius = 124.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final right = center.dx < screen.width / 2; // дуга — у бік, де є місце
    final n = kMushroomScenes.length;
    return Stack(
      children: [
        Positioned.fill(child: GestureDetector(onTap: () => Navigator.of(context).pop())),
        // Сам значок — над затемненням, злегка підстрибує.
        Positioned(
          left: center.dx - iconSize / 2,
          top: center.dy - iconSize / 2,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) => Transform.scale(scale: 1 + 0.25 * Curves.easeOutBack.transform(animation.value), child: child),
            child: SpeciesIcon(type: speciesId, fallbackColor: const Color(0xff8d6e63), size: iconSize),
          ),
        ),
        for (var i = 0; i < n; i++)
          Builder(builder: (context) {
            final deg = -82.0 + 164.0 * i / (n - 1); // дуга ~164°: кнопки не налазять одна на одну
            final a = (right ? deg : 180 - deg) * math.pi / 180;
            final pos = center + Offset(math.cos(a), math.sin(a)) * _radius;
            final scene = kMushroomScenes[i];
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final p = Interval(i * 0.07, 0.55 + i * 0.07, curve: Curves.easeOutBack).transform(animation.value);
                // Кнопка вилітає від значка на своє місце.
                final at = Offset.lerp(center, pos, p)!;
                return Positioned(
                  left: at.dx - 34,
                  top: at.dy - 30,
                  width: 68,
                  child: Opacity(opacity: p.clamp(0.0, 1.0), child: Transform.scale(scale: p.clamp(0.0, 1.2), child: child)),
                );
              },
              child: GestureDetector(
                key: ValueKey('radial-${scene.id}'),
                onTap: () => Navigator.of(context).pop(scene),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: Text(scene.emoji, style: const TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(8)),
                      child: Text(scene.label,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.darkGreen, decoration: TextDecoration.none)),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
