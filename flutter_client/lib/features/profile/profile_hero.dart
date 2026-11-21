import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


/// Оформлення вкладки «Профіль» у стилі аватарів (PO 2026-11-21): темний ліс, тепле золоте
/// світло, промені, спори в повітрі; кремові картки з тонкою бурштиновою облямівкою.
/// Лише вигляд — тексти й дані приходять із сервера.

const _cream = Color(0xFFF4F1E1);
const _amber = Color(0xFFD97706);
const _forestDeep = Color(0xFF0B2E1A);
const _forest = Color(0xFF14532D);

/// Картка профілю: кремова, тонка бурштинова облямівка, м'яка тінь.
BoxDecoration profileCardDecoration({double radius = 18}) => BoxDecoration(
      color: const Color(0xFFFFFCF3),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _amber.withValues(alpha: 0.22)),
      boxShadow: [BoxShadow(color: const Color(0xFF3B2A12).withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3))],
    );

ShapeBorder profileCardShape({double radius = 14}) =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: _amber.withValues(alpha: 0.22)));

/// Колір значка рівня — як рамка аватарів цього рівня (береза, дуб, мох, камінь, бронза, золото).
({List<Color> colors, Color text}) levelBadgeStyle(String? id) => switch (id) {
      'tracker' => (colors: const [Color(0xFF9A6634), Color(0xFF6B4423)], text: Colors.white),
      'expert' => (colors: const [Color(0xFF6B8E23), Color(0xFF3F6212)], text: Colors.white),
      'forester' => (colors: const [Color(0xFF9CA3A0), Color(0xFF5F6662)], text: Colors.white),
      'keeper' => (colors: const [Color(0xFFB7843F), Color(0xFF5E7F6B)], text: Colors.white),
      'master' => (colors: const [Color(0xFFF6C744), Color(0xFFC98A0C)], text: const Color(0xFF3B2A06)),
      _ => (colors: const [Color(0xFFF3EBD6), Color(0xFFD9CBA6)], text: const Color(0xFF4A3B1F)), // береза
    };

/// Тло шапки: лісова глибина, золоте світло за аватаром, промені й спори.
class ProfileHeroBackground extends StatelessWidget {
  const ProfileHeroBackground({super.key, required this.child, this.glowCenterY = 0.36});

  final Widget child;

  /// Де світіння по вертикалі (0 — верх, 1 — низ), щоб воно стояло за аватаром.
  final double glowCenterY;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1E4D2B), _forestDeep]),
          ),
          child: CustomPaint(painter: _HeroPainter(glowCenterY), child: child),
        ),
      );
}

class _HeroPainter extends CustomPainter {
  _HeroPainter(this.glowY);

  final double glowY;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * glowY);
    // золоте світіння за аватаром
    canvas.drawCircle(
      c,
      size.width * 0.62,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFF9C66B).withValues(alpha: 0.55),
          _amber.withValues(alpha: 0.18),
          Colors.transparent,
        ], stops: const [0, 0.45, 1]).createShader(Rect.fromCircle(center: c, radius: size.width * 0.62)),
    );
    // промені з лівого верхнього кута (світло в аватарах — зліва згори)
    final ray = Paint()..blendMode = BlendMode.plus;
    final src = Offset(-size.width * 0.1, -size.height * 0.15);
    for (var i = 0; i < 5; i++) {
      final a = 0.55 + i * 0.16;
      final w = 0.05 + (i % 2) * 0.03;
      final far = size.longestSide * 1.6;
      final path = Path()
        ..moveTo(src.dx, src.dy)
        ..lineTo(src.dx + math.cos(a - w) * far, src.dy + math.sin(a - w) * far)
        ..lineTo(src.dx + math.cos(a + w) * far, src.dy + math.sin(a + w) * far)
        ..close();
      ray.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFFFFE2A8).withValues(alpha: 0.10), Colors.transparent],
      ).createShader(Offset.zero & size);
      canvas.drawPath(path, ray);
    }
    // спори, що світяться в повітрі (сталий візерунок — без анімації, нічого не гальмує)
    final rnd = math.Random(7);
    final spore = Paint();
    for (var i = 0; i < 34; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final r = 0.8 + rnd.nextDouble() * 2.2;
      spore.color = const Color(0xFFFFD98A).withValues(alpha: 0.25 + rnd.nextDouble() * 0.45);
      canvas.drawCircle(p, r, spore);
      if (r > 2.2) {
        canvas.drawCircle(p, r * 3, Paint()..color = const Color(0xFFFFD98A).withValues(alpha: 0.06));
      }
    }
    // темніша смуга знизу — щоб текст читався
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45),
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, _forestDeep.withValues(alpha: 0.65)])
            .createShader(Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45)),
    );
  }

  @override
  bool shouldRepaint(_HeroPainter old) => old.glowY != glowY;
}

/// Значок рівня — стрічка в кольорі рамки рівня.
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.levelId, required this.label});

  final String? levelId;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = levelBadgeStyle(levelId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: s.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.eco_rounded, size: 16, color: s.text),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.merriweather(fontSize: 13.5, fontWeight: FontWeight.w700, color: s.text)),
        ],
      ),
    );
  }
}

/// Показник у шапці: велике число й підпис під ним, на напівпрозорому склі.
class HeroStat extends StatelessWidget {
  const HeroStat({super.key, required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF9C66B).withValues(alpha: 0.28)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: const Color(0xFFF9C66B)),
                const SizedBox(width: 5),
                Text(value, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w800, color: _cream)),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: _cream.withValues(alpha: 0.75))),
          ],
        ),
      );
}

/// Смужка прогресу рівня — бурштинова, з відблиском, на темному тлі.
class HeroProgress extends StatelessWidget {
  const HeroProgress({super.key, required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 10,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF9C66B), _amber]),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [BoxShadow(color: const Color(0xFFF9C66B).withValues(alpha: 0.5), blurRadius: 8)],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: _cream.withValues(alpha: 0.82))),
        ],
      );
}

/// Заголовок розділу: Merriweather із листочком і бурштиновою рискою.
class ProfileSectionTitle extends StatelessWidget {
  const ProfileSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10, left: 2),
        child: Row(
          children: [
            Container(width: 4, height: 18, decoration: BoxDecoration(color: _amber, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold, color: _forest)),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: _amber.withValues(alpha: 0.18))),
          ],
        ),
      );
}

const heroCream = _cream;
const heroGold = Color(0xFFF9C66B);
