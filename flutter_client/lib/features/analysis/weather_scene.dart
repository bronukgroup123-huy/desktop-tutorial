import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Сцени погоди для блоку «Погода» (рішення PO 2026-11-15). Яку показати, каже сервер.
enum WeatherSceneKind { sunny, partlyCloudy, cloudy, rain, heavyRain, fog, frost, snow, heat }

WeatherSceneKind? parseWeatherScene(String? v) => switch (v) {
      'sunny' => WeatherSceneKind.sunny,
      'partly_cloudy' => WeatherSceneKind.partlyCloudy,
      'cloudy' => WeatherSceneKind.cloudy,
      'rain' => WeatherSceneKind.rain,
      'heavy_rain' => WeatherSceneKind.heavyRain,
      'fog' => WeatherSceneKind.fog,
      'frost' => WeatherSceneKind.frost,
      'snow' => WeatherSceneKind.snow,
      'heat' => WeatherSceneKind.heat,
      _ => null,
    };

/// Скільки молодих грибів поруч із маскотом (стадія хвилі): 0 / 2 / 5.
int sproutCount(String? v) => switch (v) { 'many' => 5, 'few' => 2, _ => 0 };

/// Анімована сцена погоди з грибом-маскотом (білий гриб). Сонце — маскот в окулярах засмагає
/// на рушнику; дощ — радіє й підставляє капелюшок; злива — під парасолькою; туман — ледь видно;
/// заморозок — у шарфі, пара з рота; сніг — у шапці; спека — ховається під листком і пітніє.
/// Молоді гриби поруч — за стадією хвилі. Системне «менше анімацій» — сцена нерухома.
class WeatherScene extends StatefulWidget {
  const WeatherScene({super.key, required this.kind, this.sprouts = 0, this.height = 150, this.child});

  final WeatherSceneKind kind;
  final int sprouts;
  final double height;

  /// Підпис поверх сцени (температура).
  final Widget? child;

  @override
  State<WeatherScene> createState() => _WeatherSceneState();
}

class _WeatherSceneState extends State<WeatherScene> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _t.stop();
      _t.value = 0.3;
    } else if (!_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // RepaintBoundary: анімація сцени не перемальовує решту списку.
              RepaintBoundary(
                child: CustomPaint(
                  key: ValueKey('weather-scene-${widget.kind.name}'),
                  painter: WeatherScenePainter(kind: widget.kind, sprouts: widget.sprouts, t: _t),
                ),
              ),
              if (widget.child != null) Positioned(left: 10, top: 10, child: widget.child!),
            ],
          ),
        ),
      );
}

class WeatherScenePainter extends CustomPainter {
  WeatherScenePainter({required this.kind, required this.sprouts, required this.t}) : super(repaint: t);

  final WeatherSceneKind kind;
  final int sprouts;
  final Animation<double> t;

  static const _ink = Color(0xff3a2a1e);

  bool get _wet => kind == WeatherSceneKind.rain || kind == WeatherSceneKind.heavyRain;
  bool get _white => kind == WeatherSceneKind.snow;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final w = size.width, h = size.height;
    final groundY = h * 0.78;
    _sky(canvas, size);
    _sunAndClouds(canvas, size, v);
    _trees(canvas, size, groundY);
    _ground(canvas, size, groundY, v);
    // Маскот праворуч від центру: зліва вгорі — підпис з температурою.
    final mx = w * 0.62, my = groundY;
    final s = math.min(h * 0.5, 78) / 44;
    _sprouts(canvas, mx, my, v);
    _mascot(canvas, Offset(mx, my), math.min(h * 0.5, 78), v);
    _precip(canvas, size, groundY, v, umbrella: Rect.fromLTRB(mx - 36 * s, my - 58 * s, mx + 32 * s, my));
    if (kind == WeatherSceneKind.fog) _fog(canvas, size, v);
  }

  // ─── Тло ─────────────────────────────────────────────────────────────────

  void _sky(Canvas canvas, Size size) {
    final colors = switch (kind) {
      WeatherSceneKind.sunny => [const Color(0xff7cc4f2), const Color(0xffd8f0ff)],
      WeatherSceneKind.heat => [const Color(0xfff7c76b), const Color(0xfffdecc8)],
      WeatherSceneKind.partlyCloudy => [const Color(0xff8ccaf0), const Color(0xffe2f2fb)],
      WeatherSceneKind.cloudy => [const Color(0xffa9b8c4), const Color(0xffdfe5ea)],
      WeatherSceneKind.rain => [const Color(0xff8f9ead), const Color(0xffcdd6de)],
      WeatherSceneKind.heavyRain => [const Color(0xff5f6e7c), const Color(0xffa6b2bd)],
      WeatherSceneKind.fog => [const Color(0xffc9d0d4), const Color(0xffeceff1)],
      WeatherSceneKind.frost => [const Color(0xffa8d4ee), const Color(0xffeef8ff)],
      WeatherSceneKind.snow => [const Color(0xffb3c2d1), const Color(0xffe9eef3)],
    };
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors)
          .createShader(Offset.zero & size),
    );
  }

  void _sunAndClouds(Canvas canvas, Size size, double v) {
    final w = size.width, h = size.height;
    final sun = switch (kind) {
      WeatherSceneKind.sunny || WeatherSceneKind.heat || WeatherSceneKind.partlyCloudy || WeatherSceneKind.frost => true,
      _ => false,
    };
    if (sun) {
      final c = Offset(w * 0.88, h * 0.22);
      final r = h * (kind == WeatherSceneKind.heat ? 0.17 : 0.14);
      final color = kind == WeatherSceneKind.frost ? const Color(0xfffff6c8) : const Color(0xffffd23f);
      // Промені обертаються.
      final rays = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 12; i++) {
        final a = v * 2 * math.pi / 3 + i * math.pi / 6;
        final len = r * (i.isEven ? 0.55 : 0.38) * (1 + 0.12 * math.sin(v * 2 * math.pi * 2 + i));
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r * 1.25),
            c + Offset(math.cos(a), math.sin(a)) * (r * 1.25 + len), rays);
      }
      canvas.drawCircle(c, r * 1.2, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(c, r, Paint()..color = color);
    }
    final cloudColor = switch (kind) {
      WeatherSceneKind.heavyRain => const Color(0xff7d8894),
      WeatherSceneKind.rain || WeatherSceneKind.snow => const Color(0xffb7c0c8),
      WeatherSceneKind.cloudy => const Color(0xffe6eaee),
      _ => Colors.white,
    };
    final clouds = switch (kind) {
      WeatherSceneKind.partlyCloudy => [(0.72, 0.34, 1.0)],
      WeatherSceneKind.cloudy => [(0.15, 0.2, 0.9), (0.55, 0.14, 1.2), (0.88, 0.28, 0.8)],
      WeatherSceneKind.rain || WeatherSceneKind.snow => [(0.1, 0.16, 1.1), (0.48, 0.1, 1.3), (0.85, 0.18, 1.1)],
      WeatherSceneKind.heavyRain => [(0.05, 0.12, 1.3), (0.4, 0.06, 1.5), (0.78, 0.12, 1.4), (1.05, 0.2, 1.1)],
      WeatherSceneKind.frost => [(0.2, 0.18, 0.6)],
      _ => <(double, double, double)>[],
    };
    for (final (i, (x, y, s)) in clouds.indexed) {
      final drift = math.sin(v * 2 * math.pi + i) * w * 0.02;
      _cloud(canvas, Offset(w * x + drift, h * y + 14), h * 0.12 * s, cloudColor);
    }
  }

  void _cloud(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()..color = color;
    canvas.drawCircle(c + Offset(-r * 1.1, r * 0.25), r * 0.75, p);
    canvas.drawCircle(c, r, p);
    canvas.drawCircle(c + Offset(r * 1.05, r * 0.2), r * 0.8, p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - r * 1.8, c.dy + r * 0.1, r * 3.7, r * 0.85), Radius.circular(r * 0.4)),
      p,
    );
  }

  void _trees(Canvas canvas, Size size, double groundY) {
    final color = switch (kind) {
      WeatherSceneKind.fog => const Color(0x5536594a),
      WeatherSceneKind.snow || WeatherSceneKind.frost => const Color(0xff4f7563),
      WeatherSceneKind.heat => const Color(0xff7f8f4a),
      WeatherSceneKind.heavyRain => const Color(0xff35574a),
      _ => const Color(0xff3f7a5b),
    };
    final p = Paint()..color = color;
    final w = size.width;
    for (final (x, s) in [(0.06, 0.9), (0.14, 1.2), (0.24, 0.8), (0.66, 1.0), (0.75, 1.3), (0.93, 1.0)]) {
      final base = Offset(w * x, groundY + 2);
      final th = size.height * 0.36 * s;
      final path = Path()
        ..moveTo(base.dx, base.dy - th)
        ..lineTo(base.dx + th * 0.28, base.dy - th * 0.35)
        ..lineTo(base.dx + th * 0.16, base.dy - th * 0.35)
        ..lineTo(base.dx + th * 0.34, base.dy)
        ..lineTo(base.dx - th * 0.34, base.dy)
        ..lineTo(base.dx - th * 0.16, base.dy - th * 0.35)
        ..lineTo(base.dx - th * 0.28, base.dy - th * 0.35)
        ..close();
      canvas.drawPath(path, p);
      if (_white) {
        canvas.drawPath(
          Path()
            ..moveTo(base.dx, base.dy - th)
            ..lineTo(base.dx + th * 0.12, base.dy - th * 0.7)
            ..lineTo(base.dx - th * 0.12, base.dy - th * 0.7)
            ..close(),
          Paint()..color = Colors.white,
        );
      }
    }
  }

  void _ground(Canvas canvas, Size size, double groundY, double v) {
    final w = size.width, h = size.height;
    final color = switch (kind) {
      WeatherSceneKind.snow => const Color(0xfff4f7fa),
      WeatherSceneKind.frost => const Color(0xffc9dccf),
      WeatherSceneKind.heat => const Color(0xffcaa66a),
      WeatherSceneKind.fog => const Color(0xffa7b8a8),
      _ => const Color(0xff7fb069),
    };
    final hill = Path()
      ..moveTo(0, groundY)
      ..quadraticBezierTo(w * 0.3, groundY - 8, w * 0.6, groundY)
      ..quadraticBezierTo(w * 0.85, groundY + 6, w, groundY - 4)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill, Paint()..color = color);
    if (kind == WeatherSceneKind.heat) {
      // Тріщини посухи.
      final crack = Paint()
        ..color = const Color(0xff8a6a3a)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      for (final x in [0.12, 0.3, 0.68, 0.86]) {
        canvas.drawPath(
          Path()
            ..moveTo(w * x, groundY + 8)
            ..lineTo(w * x + 6, groundY + 14)
            ..lineTo(w * x + 2, groundY + 20)
            ..moveTo(w * x + 6, groundY + 14)
            ..lineTo(w * x + 13, groundY + 16),
          crack,
        );
      }
      // Марево.
      final shimmer = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (var k = 0; k < 3; k++) {
        final y = groundY - 10 - k * 9.0;
        final path = Path()..moveTo(0, y);
        for (var x = 0.0; x <= w; x += 8) {
          path.lineTo(x, y + math.sin(x / 14 + v * 2 * math.pi * 2 + k) * 2);
        }
        canvas.drawPath(path, shimmer);
      }
    }
    if (_wet) {
      // Калюжі з брижами.
      for (final (x, phase) in [(0.2, 0.0), (0.72, 0.5)]) {
        final c = Offset(w * x, groundY + 12);
        canvas.drawOval(Rect.fromCenter(center: c, width: 46, height: 9), Paint()..color = const Color(0x667aa7c7));
        final r = ((v * 3 + phase) % 1);
        canvas.drawOval(
          Rect.fromCenter(center: c, width: 10 + 30 * r, height: 2 + 6 * r),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.6 * (1 - r))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }
    if (kind == WeatherSceneKind.frost) _sparkles(canvas, [for (final x in [0.1, 0.27, 0.6, 0.82, 0.95]) Offset(w * x, groundY + 10)], v);
  }

  void _sparkles(Canvas canvas, List<Offset> at, double v) {
    for (final (i, p) in at.indexed) {
      final a = (math.sin(v * 2 * math.pi * 2 + i * 1.7) + 1) / 2;
      if (a < 0.3) continue;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: a)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      final s = 3 + 2 * a;
      canvas.drawLine(p - Offset(s, 0), p + Offset(s, 0), paint);
      canvas.drawLine(p - Offset(0, s), p + Offset(0, s), paint);
    }
  }

  // ─── Опади й туман ───────────────────────────────────────────────────────

  void _precip(Canvas canvas, Size size, double groundY, double v, {Rect? umbrella}) {
    final w = size.width;
    final rnd = math.Random(7);
    if (_wet) {
      final heavy = kind == WeatherSceneKind.heavyRain;
      final n = heavy ? 70 : 32;
      final p = Paint()
        ..color = const Color(0xff4a86c5).withValues(alpha: heavy ? 0.75 : 0.6)
        ..strokeWidth = heavy ? 1.8 : 1.5
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < n; i++) {
        final x0 = rnd.nextDouble() * w * 1.1;
        final speed = 1 + rnd.nextDouble();
        final y = ((rnd.nextDouble() + v * 4 * speed) % 1) * (groundY + 10) - 10;
        final slant = heavy ? 5.0 : 2.0;
        // Під парасолькою (злива) — сухо.
        if (heavy && umbrella != null && umbrella.contains(Offset(x0 - y * 0.08, y))) continue;
        canvas.drawLine(Offset(x0 - y * 0.08, y), Offset(x0 - y * 0.08 - slant, y + (heavy ? 12 : 9)), p);
      }
    }
    if (kind == WeatherSceneKind.snow) {
      final p = Paint()..color = Colors.white;
      for (var i = 0; i < 40; i++) {
        final x0 = rnd.nextDouble() * w;
        final speed = 0.6 + rnd.nextDouble() * 0.6;
        final y = ((rnd.nextDouble() + v * speed) % 1) * (groundY + 6);
        final x = x0 + math.sin(v * 2 * math.pi * 2 + i) * 6;
        canvas.drawCircle(Offset(x, y), 1.6 + rnd.nextDouble() * 1.6, p);
      }
    }
  }

  void _fog(Canvas canvas, Size size, double v) {
    final w = size.width, h = size.height;
    for (var k = 0; k < 4; k++) {
      final y = h * (0.35 + k * 0.16);
      final dx = math.sin(v * 2 * math.pi + k) * w * 0.08;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-w * 0.2 + dx, y, w * 1.4, h * 0.1), const Radius.circular(20)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.42)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  // ─── Молоді гриби (хвиля) ────────────────────────────────────────────────

  void _sprouts(Canvas canvas, double mx, double groundY, double v) {
    const spots = [(-58.0, 0.55), (52.0, 0.6), (-92.0, 0.42), (82.0, 0.45), (-125.0, 0.38)];
    for (var i = 0; i < math.min(sprouts, spots.length); i++) {
      final (dx, s) = spots[i];
      final grow = 0.92 + 0.08 * math.sin(v * 2 * math.pi + i);
      _mushroomBody(canvas, Offset(mx + dx, groundY + 4), 40 * s * grow, face: false);
    }
  }

  // ─── Маскот ──────────────────────────────────────────────────────────────

  /// Ніжка й капелюшок білого гриба (як стікер), [base] — низ ніжки, [hgt] — висота.
  void _mushroomBody(Canvas canvas, Offset base, double hgt, {bool face = true, double alpha = 1}) {
    final s = hgt / 44;
    final stroke = Paint()
      ..color = _ink.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, 2.2 * s)
      ..strokeJoin = StrokeJoin.round;
    final stem = Path()
      ..moveTo(base.dx - 8 * s, base.dy - 18 * s)
      ..quadraticBezierTo(base.dx - 12 * s, base.dy - 3 * s, base.dx - 6 * s, base.dy)
      ..lineTo(base.dx + 6 * s, base.dy)
      ..quadraticBezierTo(base.dx + 12 * s, base.dy - 3 * s, base.dx + 8 * s, base.dy - 18 * s)
      ..close();
    canvas.drawPath(stem, Paint()..color = const Color(0xfffff8dc).withValues(alpha: alpha));
    canvas.drawPath(stem, stroke);
    final cap = Path()
      ..moveTo(base.dx - 22 * s, base.dy - 26 * s)
      ..cubicTo(base.dx - 22 * s, base.dy - 46 * s, base.dx + 22 * s, base.dy - 46 * s, base.dx + 22 * s, base.dy - 26 * s)
      ..cubicTo(base.dx + 22 * s, base.dy - 20 * s, base.dx + 12 * s, base.dy - 16 * s, base.dx, base.dy - 16 * s)
      ..cubicTo(base.dx - 12 * s, base.dy - 16 * s, base.dx - 22 * s, base.dy - 20 * s, base.dx - 22 * s, base.dy - 26 * s)
      ..close();
    canvas.drawPath(cap, Paint()..color = const Color(0xff8b4513).withValues(alpha: alpha));
    canvas.drawPath(cap, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - 14 * s, base.dy - 33 * s)
        ..quadraticBezierTo(base.dx, base.dy - 41 * s, base.dx + 14 * s, base.dy - 33 * s),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * s
        ..strokeCap = StrokeCap.round,
    );
  }

  void _mascot(Canvas canvas, Offset base, double hgt, double v) {
    final s = hgt / 44;
    final wave = math.sin(v * 2 * math.pi * 2);
    // Пози: дощ — підстрибує від радості; заморозок — тремтить; спека — похилився.
    var dx = 0.0, dy = 0.0, tilt = 0.0;
    switch (kind) {
      case WeatherSceneKind.rain:
        dy = -math.max(0, wave) * 5;
      case WeatherSceneKind.frost:
        dx = math.sin(v * 2 * math.pi * 14) * 1.2;
      case WeatherSceneKind.heat:
        tilt = -0.12;
      case WeatherSceneKind.sunny:
        tilt = 0.04 * wave;
      default:
        dy = -math.max(0, wave) * 1.5;
    }
    final alpha = kind == WeatherSceneKind.fog ? 0.75 : 1.0;

    // Під маскотом: рушник (сонце), тінь.
    if (kind == WeatherSceneKind.sunny) {
      final towel = Rect.fromCenter(center: base + Offset(0, 3 * s), width: 62 * s, height: 9 * s);
      canvas.drawRRect(RRect.fromRectAndRadius(towel, Radius.circular(3 * s)), Paint()..color = const Color(0xffe85d75));
      for (var i = 0; i < 4; i++) {
        canvas.drawRect(
          Rect.fromLTWH(towel.left + towel.width * (0.12 + i * 0.22), towel.top, towel.width * 0.08, towel.height),
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
      }
    } else {
      canvas.drawOval(Rect.fromCenter(center: base + Offset(0, 2), width: 40 * s, height: 7 * s),
          Paint()..color = Colors.black.withValues(alpha: 0.12));
    }

    // Злива — парасолька.
    if (kind == WeatherSceneKind.heavyRain) {
      final top = base + Offset(-2 * s, -54 * s);
      canvas.drawLine(top, base + Offset(-2 * s, -24 * s),
          Paint()
            ..color = _ink
            ..strokeWidth = 2 * s);
      final dome = Path()
        ..moveTo(top.dx - 34 * s, top.dy + 12 * s)
        ..quadraticBezierTo(top.dx, top.dy - 14 * s, top.dx + 34 * s, top.dy + 12 * s)
        ..close();
      canvas.drawPath(dome, Paint()..color = const Color(0xffe53935));
      canvas.drawPath(dome, Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s);
    }

    canvas.save();
    canvas.translate(base.dx + dx, base.dy + dy);
    canvas.rotate(tilt);
    _mushroomBody(canvas, Offset.zero, hgt, alpha: alpha);
    _face(canvas, s, v, alpha);
    _accessories(canvas, s, v);
    canvas.restore();

    // Пара з рота на морозі.
    if (kind == WeatherSceneKind.frost || kind == WeatherSceneKind.snow) {
      final r = (v * 2) % 1;
      canvas.drawCircle(base + Offset(14 * s + 10 * r * s, -12 * s - 6 * r * s), (2 + 4 * r) * s,
          Paint()..color = Colors.white.withValues(alpha: 0.7 * (1 - r)));
    }
    if (kind == WeatherSceneKind.frost) {
      _sparkles(canvas, [base + Offset(-12 * s, -36 * s), base + Offset(10 * s, -40 * s), base + Offset(18 * s, -28 * s)], v);
    }
    // Спека — піт.
    if (kind == WeatherSceneKind.heat) {
      final r = (v * 1.5) % 1;
      canvas.drawCircle(base + Offset(16 * s, -14 * s + 10 * r * s), 2.2 * s, Paint()..color = const Color(0xff6bb7e8));
    }
  }

  void _face(Canvas canvas, double s, double v, double alpha) {
    final ink = Paint()
      ..color = _ink.withValues(alpha: alpha)
      ..strokeWidth = 1.8 * s
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = _ink.withValues(alpha: alpha);
    final eyeY = -11.5 * s;
    final blink = ((v * 3) % 1) > 0.95;
    final happy = kind == WeatherSceneKind.rain || kind == WeatherSceneKind.snow;
    if (kind == WeatherSceneKind.sunny) {
      // Окуляри від сонця.
      final lens = Paint()..color = const Color(0xff1f2933);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(-4 * s, eyeY), width: 7 * s, height: 4.5 * s), Radius.circular(2 * s)), lens);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(4 * s, eyeY), width: 7 * s, height: 4.5 * s), Radius.circular(2 * s)), lens);
      canvas.drawLine(Offset(-0.5 * s, eyeY), Offset(0.5 * s, eyeY), ink);
      canvas.drawLine(Offset(-6 * s, eyeY - 1 * s), Offset(-3 * s, eyeY - 1.4 * s),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.6)
            ..strokeWidth = 0.8 * s);
    } else if (happy || blink) {
      // Очі-дужки ^ ^ (радіє або кліпає).
      for (final x in [-4.0, 4.0]) {
        canvas.drawPath(
          Path()
            ..moveTo((x - 2) * s, eyeY + 0.6 * s)
            ..quadraticBezierTo(x * s, eyeY - 1.8 * s, (x + 2) * s, eyeY + 0.6 * s),
          ink,
        );
      }
    } else {
      final look = kind == WeatherSceneKind.fog ? 1.0 * s : 0.0;
      canvas.drawCircle(Offset(-4 * s + look, eyeY), 1.5 * s, fill);
      canvas.drawCircle(Offset(4 * s + look, eyeY), 1.5 * s, fill);
    }
    // Рот.
    final sad = kind == WeatherSceneKind.heat;
    final big = kind == WeatherSceneKind.rain || kind == WeatherSceneKind.sunny || kind == WeatherSceneKind.snow;
    final mouth = Path()
      ..moveTo(-3 * s, -7 * s)
      ..quadraticBezierTo(0, (sad ? -9 : (big ? -3.5 : -5.5)) * s, 3 * s, -7 * s);
    canvas.drawPath(mouth, ink);
    // Рум'янець.
    canvas.drawCircle(Offset(-7 * s, -8.5 * s), 1.4 * s, Paint()..color = const Color(0x55ff7f7f));
    canvas.drawCircle(Offset(7 * s, -8.5 * s), 1.4 * s, Paint()..color = const Color(0x55ff7f7f));
  }

  void _accessories(Canvas canvas, double s, double v) {
    switch (kind) {
      case WeatherSceneKind.frost:
      case WeatherSceneKind.snow:
        // Шарф.
        final scarf = Paint()..color = const Color(0xffd62f2f);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -4 * s), width: 20 * s, height: 4.5 * s), Radius.circular(2 * s)),
          scarf,
        );
        final flap = math.sin(v * 2 * math.pi * 3) * 1.5 * s;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(5 * s + flap, -4 * s, 4 * s, 10 * s), Radius.circular(1.5 * s)),
          scarf,
        );
        if (kind == WeatherSceneKind.snow) {
          // В'язана шапка на капелюшку.
          final hat = Path()
            ..moveTo(-12 * s, -38 * s)
            ..quadraticBezierTo(0, -54 * s, 12 * s, -38 * s)
            ..close();
          canvas.drawPath(hat, Paint()..color = const Color(0xff2f6fd6));
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -38 * s), width: 26 * s, height: 4 * s), Radius.circular(2 * s)),
            Paint()..color = Colors.white,
          );
          canvas.drawCircle(Offset(0, -49 * s), 3 * s, Paint()..color = Colors.white);
        }
      case WeatherSceneKind.heat:
        // Листок-тінь над капелюшком.
        final leaf = Path()
          ..moveTo(-26 * s, -40 * s)
          ..quadraticBezierTo(-2 * s, -60 * s, 26 * s, -44 * s)
          ..quadraticBezierTo(0, -36 * s, -26 * s, -40 * s)
          ..close();
        canvas.drawPath(leaf, Paint()..color = const Color(0xff6aa84f));
        canvas.drawLine(Offset(-24 * s, -40 * s), Offset(24 * s, -44 * s),
            Paint()
              ..color = const Color(0xff3e7a2d)
              ..strokeWidth = 1 * s);
      case WeatherSceneKind.rain:
        // Краплі відскакують від капелюшка.
        final r = (v * 4) % 1;
        final p = Paint()..color = const Color(0xff4a86c5).withValues(alpha: 1 - r);
        canvas.drawCircle(Offset(-18 * s - 6 * r * s, -30 * s - 8 * math.sin(r * math.pi) * s), 1.6 * s, p);
        canvas.drawCircle(Offset(18 * s + 6 * r * s, -30 * s - 8 * math.sin(r * math.pi) * s), 1.6 * s, p);
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(WeatherScenePainter old) => old.kind != kind || old.sprouts != sprouts;
}
