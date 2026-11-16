import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Анімації довідника (рішення PO 2026-11-16): грибниця між розділами, картка-перевертень двійника.
/// (Картки списку не анімуються — лише фото плавно проявляється: catalog_photo.dart.) Кожна — один раз; без анімацій у системі — одразу кінцевий вигляд.

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

double seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

// ─── Поява при гортанні ─────────────────────────────────────────────────────

/// Запускає анімацію, коли віджет уперше з'являється на екрані під час гортання.
class RevealOnScroll extends StatefulWidget {
  const RevealOnScroll({super.key, required this.duration, required this.builder});

  final Duration duration;
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  ScrollPosition? _pos;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value > 0 || _c.isAnimating) return;
    if (reduceMotion(context)) {
      _c.value = 1;
      return;
    }
    _pos?.removeListener(_check);
    _pos = Scrollable.maybeOf(context)?.position;
    _pos?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!mounted || _c.value > 0 || _c.isAnimating) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final y = box.localToGlobal(Offset.zero).dy;
    if (y < MediaQuery.sizeOf(context).height * 0.92) {
      _c.forward();
      _pos?.removeListener(_check);
    }
  }

  @override
  void dispose() {
    _pos?.removeListener(_check);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, _c.value));
}

// ─── 5. Грибниця між розділами ──────────────────────────────────────────────

/// Роздільник розділів — тонкі нитки грибниці: при гортанні проростає головна нитка, від неї
/// розгалужуються відгалуження, на кінчиках набухають вузлики.
class MyceliumDivider extends StatelessWidget {
  const MyceliumDivider({super.key, required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) => RevealOnScroll(
        duration: const Duration(milliseconds: 1400),
        builder: (context, t) => SizedBox(
          key: ValueKey('mycelium-$seed'),
          height: 30,
          width: double.infinity,
          child: CustomPaint(painter: MyceliumPainter(progress: t, seed: seed)),
        ),
      );
}

class MyceliumPainter extends CustomPainter {
  MyceliumPainter({required this.progress, required this.seed});

  final double progress;
  final int seed;

  static const _thread = Color(0xffcbbd9c);
  static const _node = Color(0xffe8dcc0);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final w = size.width, mid = size.height / 2;
    final paint = Paint()
      ..color = _thread
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.3;

    // Головна нитка — хвиляста, від лівого краю.
    final main = Path()..moveTo(0, mid);
    const steps = 6;
    for (var i = 1; i <= steps; i++) {
      final x = w * i / steps;
      main.cubicTo(x - w / steps * 0.6, mid + (r.nextDouble() - 0.5) * 8, x - w / steps * 0.3, mid + (r.nextDouble() - 0.5) * 8, x, mid + (r.nextDouble() - 0.5) * 4);
    }
    _drawPartial(canvas, main, seg(progress, 0, 0.6), paint);

    // Відгалуження: виростають, коли головна нитка до них дійшла.
    final branches = 7 + r.nextInt(3);
    for (var b = 0; b < branches; b++) {
      final fx = 0.06 + 0.88 * (b + r.nextDouble() * 0.6) / branches;
      final start = Offset(w * fx, mid + (r.nextDouble() - 0.5) * 4);
      final up = r.nextBool() ? -1.0 : 1.0;
      final len = 7 + r.nextDouble() * 9;
      final end = start + Offset((r.nextDouble() - 0.3) * 18, up * len);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(start.dx + (end.dx - start.dx) * 0.2, start.dy + up * len * 0.7, end.dx, end.dy);
      // Розвилка на кінці.
      final fork = end + Offset((r.nextDouble() - 0.5) * 10, up * (3 + r.nextDouble() * 4));
      path
        ..moveTo(end.dx, end.dy)
        ..lineTo(fork.dx, fork.dy);
      final local = seg(progress, 0.6 * fx + 0.05, 0.6 * fx + 0.4);
      _drawPartial(canvas, path, local, paint..strokeWidth = 0.9);
      // Вузлик на кінчику — набухає наприкінці.
      final node = seg(progress, 0.75, 1.0) * (local >= 1 ? 1 : 0);
      if (node > 0) canvas.drawCircle(fork, 1.6 * node + (b.isEven ? 0.6 : 0), Paint()..color = _node);
    }
  }

  void _drawPartial(Canvas canvas, Path path, double p, Paint paint) {
    if (p <= 0) return;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * p), paint);
    }
  }

  @override
  bool shouldRepaint(covariant MyceliumPainter old) => old.progress != progress || old.seed != seed;
}

// ─── 7. Картка-перевертень ──────────────────────────────────────────────────

/// Картка з двома боками: дотик — перевертається в 3D (з легким підскоком), ще дотик — назад.
class FlipCard extends StatefulWidget {
  const FlipCard({super.key, required this.front, required this.back});

  final Widget front;
  final Widget back;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  bool _back = false;

  void _flip() {
    setState(() => _back = !_back);
    if (reduceMotion(context)) {
      _c.value = _back ? 1 : 0;
    } else {
      _back ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const ValueKey('flip-card'),
        onTap: _flip,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(_c.value);
            final angle = math.pi * t;
            // Підскок і тінь посередині перевороту.
            final lift = math.sin(math.pi * t);
            final showBack = angle > math.pi / 2;
            return Transform.translate(
              offset: Offset(0, -10 * lift),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0014)
                  ..rotateY(angle)
                  ..scaleByDouble(1 + 0.04 * lift, 1 + 0.04 * lift, 1, 1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08 + 0.12 * lift), blurRadius: 8 + 14 * lift, offset: Offset(0, 3 + 8 * lift))],
                  ),
                  child: showBack
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(math.pi),
                          child: KeyedSubtree(key: const ValueKey('flip-back'), child: widget.back),
                        )
                      : KeyedSubtree(key: const ValueKey('flip-front'), child: widget.front),
                ),
              ),
            );
          },
        ),
      );
}
