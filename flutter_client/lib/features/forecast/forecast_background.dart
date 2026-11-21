import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_client/features/catalog/catalog_motion.dart' show reduceMotion;

/// Живий фон вкладки «Прогноз» — «Ліс за матовим склом» (рішення PO 2026-11-20).
///
/// Сталий: однаковий у будь-яку пору року, доби й погоду. Картинка (ліс у тумані з грибами,
/// `assets/forecast_bg/base.webp`) + ефекти кодом: тінь папороті гойдається, хмарка заходить за
/// сонце, з-за неї проступають промені, відблиск проходить по краю, листок опускається, запотівання
/// по краях «дихає», краплі стікають. Петля 30 с.
///
/// Зупиняється сам, коли вкладка прихована (go_router вимикає TickerMode неактивних гілок);
/// без анімацій у системі — нерухомий кадр. Ресурси: `scripts/forecast_bg/`.
class ForecastBackground extends StatefulWidget {
  const ForecastBackground({super.key});

  static const loop = Duration(seconds: 30);

  @override
  State<ForecastBackground> createState() => _ForecastBackgroundState();
}

class _ForecastBackgroundState extends State<ForecastBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: ForecastBackground.loop);
  ForecastBgImages? _images;

  @override
  void initState() {
    super.initState();
    ForecastBgImages.load().then((i) {
      if (!mounted) return;
      setState(() => _images = i);
      _sync();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  /// Анімація — лише коли картинки вже є (до того — однотонне тло) і в системі не вимкнено анімації.
  void _sync() {
    if (_images == null) return;
    if (reduceMotion(context)) {
      _c
        ..stop()
        ..value = kForecastBgStill;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    return RepaintBoundary(
      child: images == null
          ? const ColoredBox(key: ValueKey('forecast-bg-loading'), color: kForecastBgColor)
          : CustomPaint(
              key: const ValueKey('forecast-bg'),
              painter: ForecastBgPainter(images, _c),
              size: Size.infinite,
            ),
    );
  }
}

/// Колір фону, поки картинка вантажиться = тон туману на картинці = колір застосунку.
const kForecastBgColor = Color(0xFFF4F1E1);

/// Момент петлі для нерухомого кадру: без листка, крапель і хмарки перед сонцем.
const kForecastBgStill = 0.36;

class ForecastBgImages {
  ForecastBgImages(this.base, this.fog, this.fern, this.leaf, this.rays);

  final ui.Image base, fog, fern, leaf, rays;

  static Future<ForecastBgImages>? _cache;

  static Future<ForecastBgImages> load() => _cache ??= () async {
        Future<ui.Image> img(String name) async {
          final data = await rootBundle.load('assets/forecast_bg/$name');
          final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
          return (await codec.getNextFrame()).image;
        }

        final list = await Future.wait([img('base.webp'), img('fog.png'), img('fern.png'), img('leaf.png'), img('rays.png')]);
        return ForecastBgImages(list[0], list[1], list[2], list[3], list[4]);
      }();
}

/// Краплина, що стікає: старт, довжина шляху, розмір, коли починає (частка петлі), тривалість.
class _Run {
  const _Run(this.x, this.y, this.length, this.r, this.start, this.dur);
  final double x, y, length, r, start, dur;
}

class ForecastBgPainter extends CustomPainter {
  ForecastBgPainter(this.img, this.t) : super(repaint: t);

  final ForecastBgImages img;
  final Animation<double> t;

  /// Простір макета: малюємо в 540×1200 і вписуємо в екран «cover».
  static const w = 540.0, h = 1200.0;
  static const sun = Offset(28, 40);

  static final List<Offset> _drops = () {
    final r = math.Random(11);
    final out = <Offset>[];
    while (out.length < 70) {
      final p = Offset(8 + r.nextDouble() * (w - 16), 8 + r.nextDouble() * (h - 16));
      final edge = [p.dx, w - p.dx, p.dy, h - p.dy].reduce(math.min);
      if (edge < 150 || r.nextDouble() < 0.15) out.add(p);
    }
    return out;
  }();
  static final List<double> _dropR = List.generate(70, (i) => 2 + math.Random(100 + i).nextDouble() * 4.5);

  static final List<_Run> _runs = () {
    final r = math.Random(21);
    return [
      const _Run(w - 58, 120, h * 0.62, 10, 0.03, 0.42),
      const _Run(70, 260, h * 0.5, 9, 0.52, 0.4),
      for (var i = 0; i < 9; i++)
        _Run(30 + r.nextDouble() * (w - 60), 60 + r.nextDouble() * h * 0.5, 90 + r.nextDouble() * 170, 3.2 + r.nextDouble() * 2.3, r.nextDouble(), 0.14 + r.nextDouble() * 0.12),
    ];
  }();

  static double _smooth(double x) => x * x * (3 - 2 * x);

  @override
  void paint(Canvas canvas, Size size) {
    final tt = t.value;
    final k = math.max(size.width / w, size.height / h);
    canvas.save();
    // Низ картинки (гриби з травою) — рівно на нижньому краю вкладки, над панеллю навігації;
    // якщо картинка вища за екран, обрізається верх, а не гриби (рішення PO 2026-11-21).
    canvas.translate((size.width - w * k) / 2, size.height - h * k);
    canvas.scale(k);
    const full = Rect.fromLTWH(0, 0, w, h);
    // Скільки картинки сховано згори: сонце, хмарка, гілка, запотівання й краплі — від видимого верху.
    final top = math.max(0.0, h - size.height / k);
    final vis = h - top;

    // 1. Ліс у тумані за матовим склом (зерно й розмиття вже в картинці).
    _image(canvas, img.base, full, Paint()..filterQuality = FilterQuality.medium);
    if (top > 0) canvas.translate(0, top);

    // 2. Хмарка пропливає двічі за петлю; перед сонцем — сонце тьмяніє.
    final ct = (tt * 2) % 1;
    final cx = -260 + (w + 520) * ct;
    final cy = 70 + 18 * math.sin(2 * math.pi * tt);
    final cover = math.exp(-math.pow((sun.dx - cx) / 230, 2));
    canvas.drawCircle(sun, 520, Paint()..shader = ui.Gradient.radial(sun, 520, [Color.fromRGBO(40, 50, 30, 0.2 * cover), const Color(0x00283220)]));
    _oval(canvas, Offset(cx - 18, cy - 8), 205, 92, const Color(0xFFFFECAA), 0.42 * math.max(0, 1 - (Offset(cx, cy) - sun).distance / 520));
    _oval(canvas, Offset(cx + 12, cy + 6), 210, 95, const Color(0xFFFFFAEE), 0.3);

    // 3. Тінь папороті з верхнього правого кута: повільне велике коливання + дрібне.
    final ang = (3.2 * math.sin(2 * math.pi * tt * 2) + 1.1 * math.sin(2 * math.pi * tt * 5 + 1.3)) * math.pi / 180;
    const fernSize = 675.0;
    const fernPos = Offset(w - fernSize + 40, -40);
    final pivot = Offset(fernPos.dx + 880 * 0.75, fernPos.dy + 20 * 0.75);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(ang);
    canvas.translate(-pivot.dx, -pivot.dy);
    _image(canvas, img.fern, fernPos & const Size(fernSize, fernSize), _tint(const Color(0xFF3E6846), 0.32));
    canvas.restore();

    // 4. Листок за склом — двічі за петлю, по черзі зліва й справа.
    for (final (start, left) in const [(0.12, true), (0.62, false)]) {
      final lt = (tt - start) / 0.3;
      if (lt < 0 || lt > 1) continue;
      final ly = -120 + lt * h * 0.75;
      final lx = (left ? 70.0 : w - 90) + 45 * math.sin(lt * math.pi * 3);
      canvas.save();
      canvas.translate(lx, ly);
      canvas.rotate(-35 * math.sin(lt * math.pi * 3 + 0.6) * math.pi / 180);
      // перевертається в повітрі: «вузький» листок ребром — і знову плазом
      final flip = math.cos(lt * math.pi * 2.4);
      canvas.scale(math.max(0.22, flip.abs()), 1);
      _image(canvas, img.leaf, const Rect.fromLTWH(-80, -110, 160, 220), _tint(const Color(0xFF788C46), 0.26 * math.sin(math.pi * lt)));
      canvas.restore();
    }

    // 5. Запотівання по краях — повільно «дихає».
    _image(canvas, img.fog, Rect.fromLTWH(0, 0, w, vis), _tint(const Color(0xFFF8F6EB), 0.62 * (0.88 + 0.12 * math.sin(2 * math.pi * tt))));

    // 6. Сонце світить крізь скло; тьмяніє, коли хмарка перед ним.
    for (final (r, a) in [(300.0, 0.55 * (1 - 0.65 * cover)), (110.0, 0.45 * (1 - 0.8 * cover))]) {
      canvas.drawCircle(
          sun,
          r,
          Paint()
            ..blendMode = BlendMode.screen
            ..shader = ui.Gradient.radial(sun, r, [Color.fromRGBO(255, 236, 170, a), const Color(0x00FFECAA)]));
    }

    // 7. Промені: проступають, коли хмарка відходить від сонця, і ледь повертаються.
    final rayOn = math.max(0.0, math.sin(math.pi * ((ct - 0.45) / 0.5).clamp(0.0, 1.0))) * (1 - cover);
    if (rayOn > 0.01) {
      canvas.save();
      canvas.translate(sun.dx, sun.dy);
      canvas.rotate(0.04 * math.sin(2 * math.pi * tt * 3));
      _image(canvas, img.rays, const Rect.fromLTWH(0, 0, 700, 700), _tint(const Color(0xFFFFF0BE), 0.6 * rayOn)..blendMode = BlendMode.screen);
      canvas.restore();
    }

    // 8. Краплі стікають (2 великі, 9 малих), лишаючи прозорий слід у запотіванні.
    for (final r in _runs) {
      final dt = ((tt - r.start) % 1) / r.dur;
      if (dt > 1) continue;
      final dy = r.y + _smooth(dt) * r.length + r.r * 0.8 * math.sin(dt * 18);
      final wob = r.r * 0.6;
      final fade = 1 - math.max(0.0, (dt - 0.85) / 0.15);
      final trail = Path()..moveTo(r.x, r.y);
      for (var y = r.y; y < dy; y += 6) {
        trail.lineTo(r.x + wob * math.sin((y - r.y) / math.max(r.length, 1) * 7), y);
      }
      // слід — прозоріше скло; вгорі вже знову запотіває (згасає)
      final a0 = (0.12 + r.r / 90) * fade;
      canvas.drawPath(
          trail,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r.r * 0.8
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(Offset(r.x, r.y), Offset(r.x, math.max(dy, r.y + 1)),
                [const Color.fromRGBO(150, 142, 112, 0), const Color.fromRGBO(150, 142, 112, 0), Color.fromRGBO(150, 142, 112, a0 * 0.8)], const [0, 0.45, 1]));
      _drop(canvas, Offset(r.x + wob * math.sin(dt * 7), dy), r.r, 1.3, 1.4 + r.r / 30);
    }

    // 9. Відблиск: широка світла смуга двічі за петлю проходить по правому краю.
    final gt = ((tt * 2) % 1 - 0.55) / 0.35;
    final glareOn = gt >= 0 && gt <= 1 ? math.sin(math.pi * gt) : 0.0;
    final gy = -300 + gt * (h + 600);
    if (glareOn > 0) {
      const zone = Rect.fromLTWH(w * 0.25, 0, w * 0.75, h);
      canvas.saveLayer(zone, Paint());
      canvas.save();
      canvas.translate(w, gy);
      canvas.rotate(math.atan(0.6));
      canvas.drawRect(
          const Rect.fromLTWH(-900, -170, 1800, 340),
          Paint()
            ..blendMode = BlendMode.screen
            ..shader =
                ui.Gradient.linear(const Offset(0, -170), const Offset(0, 170), [const Color(0x00FFFAE1), Color.fromRGBO(255, 250, 225, 0.5 * glareOn), const Color(0x00FFFAE1)], const [0, 0.5, 1]));
      canvas.restore();
      // ліворуч відблиск плавно сходить нанівець (раніше обрізався рівною вертикальною лінією)
      canvas.drawRect(
          zone,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(Offset(zone.left, 0), const Offset(w * 0.6, 0), [const Color(0x00000000), const Color(0xFF000000)]));
      canvas.restore();
    }

    // 10. Дрібні краплі на склі; під відблиском — яскравіші.
    for (var i = 0; i < _drops.length; i++) {
      final p = Offset(_drops[i].dx, _drops[i].dy * vis / h);
      final g = glareOn <= 0 ? 0.0 : math.exp(-math.pow(((p.dy - gy) + (p.dx - w) * 0.6) / 140, 2)) * ((p.dx - w * 0.35) / (w * 0.65)).clamp(0.0, 1.0) * glareOn;
      _drop(canvas, p, _dropR[i], 1 + 3 * g, 1);
    }
    canvas.restore();
  }

  static void _image(Canvas c, ui.Image i, Rect dst, Paint p) => c.drawImageRect(i, Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble()), dst, p);

  static Paint _tint(Color color, double opacity) => Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = ColorFilter.mode(color.withValues(alpha: opacity.clamp(0.0, 1.0)), BlendMode.srcIn);

  static void _oval(Canvas c, Offset center, double rx, double ry, Color color, double a) {
    if (a <= 0.005) return;
    c.save();
    c.translate(center.dx, center.dy);
    c.scale(1, ry / rx);
    c.drawCircle(Offset.zero, rx * 1.6, Paint()..shader = ui.Gradient.radial(Offset.zero, rx * 1.6, [color.withValues(alpha: a), color.withValues(alpha: 0)]));
    c.restore();
  }

  static void _drop(Canvas c, Offset p, double r, double a, double elong) {
    double al(double x) => (x * a).clamp(0.0, 1.0);
    c.drawOval(Rect.fromLTRB(p.dx - r, p.dy - r * elong, p.dx + r, p.dy + r), Paint()..color = Color.fromRGBO(255, 255, 255, al(0.16)));
    c.drawOval(
        Rect.fromLTRB(p.dx - r * 0.9, p.dy - r * 0.2 * elong, p.dx + r * 0.9, p.dy + r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.fromRGBO(98, 90, 66, al(0.24)));
    c.drawOval(Rect.fromLTRB(p.dx - r * 0.45, p.dy - r * 0.6 * elong, p.dx - r * 0.05, p.dy - r * 0.2 * elong), Paint()..color = Color.fromRGBO(255, 255, 255, al(0.78)));
  }

  @override
  bool shouldRepaint(covariant ForecastBgPainter old) => old.img != img || old.t != t;
}
