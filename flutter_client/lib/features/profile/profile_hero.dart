import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Оформлення вкладки «Профіль» у стилі аватарів (PO 2026-11-21): шапка — ліс у світлі, що
/// змінюється з рівнем (як рамки аватарів: береза → дуб → мох → камінь → бронза → золото);
/// решта — пергаментні картки, медальйони-іконки, вітрина трофеїв.
/// Лише вигляд — тексти й дані приходять із сервера.

const heroCream = Color(0xFFF4F1E1);
const heroGold = Color(0xFFF9C66B);
const _amber = Color(0xFFD97706);
const _forest = Color(0xFF14532D);
const _ink = Color(0xFF2B2416);

/// Палітра шапки для рівня.
class HeroPalette {
  const HeroPalette({
    required this.top,
    required this.bottom,
    required this.glow,
    required this.spore,
    required this.accent,
    required this.badge,
    required this.badgeText,
    this.rays = 0.10,
  });

  final Color top;
  final Color bottom;

  /// Світіння за аватаром.
  final Color glow;
  final Color spore;

  /// Облямівка плиток і смужка прогресу.
  final Color accent;

  /// Значок рівня (як рамка аватарів рівня).
  final List<Color> badge;
  final Color badgeText;
  final double rays;
}

HeroPalette heroPalette(String? levelId) => switch (levelId) {
      // Слідопит — дубовий ліс, тепле бурштинове світло
      'tracker' => const HeroPalette(
          top: Color(0xFF4A3A22), bottom: Color(0xFF1C2414), glow: Color(0xFFF2B861), spore: Color(0xFFFFCF7A), accent: Color(0xFFE0A050),
          badge: [Color(0xFF9A6634), Color(0xFF6B4423)], badgeText: Colors.white),
      // Грибознавець — живий мох, зелено-золоте світло
      'expert' => const HeroPalette(
          top: Color(0xFF2F5A1E), bottom: Color(0xFF0F2A12), glow: Color(0xFFD7E36B), spore: Color(0xFFE8F08C), accent: Color(0xFFB9D25A),
          badge: [Color(0xFF6B8E23), Color(0xFF3F6212)], badgeText: Colors.white),
      // Лісовик — туманний камінь, сріблясте світло
      'forester' => const HeroPalette(
          top: Color(0xFF4A5650), bottom: Color(0xFF1A221E), glow: Color(0xFFE8E2CF), spore: Color(0xFFF1EEDF), accent: Color(0xFFC9C3AE),
          badge: [Color(0xFF9CA3A0), Color(0xFF5F6662)], badgeText: Colors.white),
      // Хранитель лісу — бронза з патиною, бурштин
      'keeper' => const HeroPalette(
          top: Color(0xFF24504A), bottom: Color(0xFF0D2321), glow: Color(0xFFE6A85A), spore: Color(0xFFFFC46B), accent: Color(0xFFD9A15A),
          badge: [Color(0xFFB7843F), Color(0xFF4F7A68)], badgeText: Colors.white, rays: 0.13),
      // Грибний Майстер — золото, сяйво
      'master' => const HeroPalette(
          top: Color(0xFF4A3410), bottom: Color(0xFF1A1205), glow: Color(0xFFFFD45E), spore: Color(0xFFFFE08A), accent: Color(0xFFF6C744),
          badge: [Color(0xFFF6C744), Color(0xFFC98A0C)], badgeText: Color(0xFF3B2A06), rays: 0.18),
      // Мандрівник — березовий гай уранці
      _ => const HeroPalette(
          top: Color(0xFF3E5E3A), bottom: Color(0xFF16301C), glow: Color(0xFFF6E3A8), spore: Color(0xFFFFF0C2), accent: Color(0xFFF0D58C),
          badge: [Color(0xFFF3EBD6), Color(0xFFD9CBA6)], badgeText: Color(0xFF4A3B1F)),
    };

/// Тло шапки: ліс у світлі рівня, світіння за аватаром, промені й спори (статично).
class ProfileHeroBackground extends StatelessWidget {
  const ProfileHeroBackground({super.key, required this.child, this.levelId, this.glowCenterY = 0.36});

  final Widget child;
  final String? levelId;

  /// Де світіння по вертикалі (0 — верх, 1 — низ), щоб воно стояло за аватаром.
  final double glowCenterY;

  @override
  Widget build(BuildContext context) {
    final p = heroPalette(levelId);
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.top, p.bottom]),
        ),
        child: CustomPaint(painter: _HeroPainter(glowCenterY, p), child: child),
      ),
    );
  }
}

class _HeroPainter extends CustomPainter {
  _HeroPainter(this.glowY, this.p);

  final double glowY;
  final HeroPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * glowY);
    final r = size.width * 0.6;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          p.glow.withValues(alpha: 0.55),
          p.glow.withValues(alpha: 0.16),
          Colors.transparent,
        ], stops: const [0, 0.45, 1]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // промені з лівого верхнього кута (світло в аватарах — зліва згори)
    final ray = Paint()..blendMode = BlendMode.plus;
    final src = Offset(-size.width * 0.1, -size.height * 0.15);
    final far = size.longestSide * 1.6;
    for (var i = 0; i < 5; i++) {
      final a = 0.55 + i * 0.16;
      final w = 0.05 + (i % 2) * 0.03;
      final path = Path()
        ..moveTo(src.dx, src.dy)
        ..lineTo(src.dx + math.cos(a - w) * far, src.dy + math.sin(a - w) * far)
        ..lineTo(src.dx + math.cos(a + w) * far, src.dy + math.sin(a + w) * far)
        ..close();
      ray.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [p.glow.withValues(alpha: p.rays), Colors.transparent],
      ).createShader(Offset.zero & size);
      canvas.drawPath(path, ray);
    }
    // спори в повітрі — сталий візерунок, без анімації
    final rnd = math.Random(7);
    final spore = Paint();
    for (var i = 0; i < 34; i++) {
      final o = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final sr = 0.8 + rnd.nextDouble() * 2.2;
      spore.color = p.spore.withValues(alpha: 0.25 + rnd.nextDouble() * 0.45);
      canvas.drawCircle(o, sr, spore);
      if (sr > 2.2) canvas.drawCircle(o, sr * 3, Paint()..color = p.spore.withValues(alpha: 0.06));
    }
    // темніше знизу — щоб текст читався
    final low = Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45);
    canvas.drawRect(
      low,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, p.bottom.withValues(alpha: 0.7)]).createShader(low),
    );
  }

  @override
  bool shouldRepaint(_HeroPainter old) => old.glowY != glowY || old.p != p;
}

/// Значок рівня — стрічка в кольорі рамки рівня.
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.levelId, required this.label});

  final String? levelId;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = heroPalette(levelId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: p.badge, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.eco_rounded, size: 15, color: p.badgeText),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w700, color: p.badgeText)),
        ],
      ),
    );
  }
}

/// Показник у шапці: число й підпис в одному рядку, на напівпрозорому склі.
class HeroStat extends StatelessWidget {
  const HeroStat({super.key, required this.icon, required this.value, required this.label, required this.accent});

  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 5),
            Text(value, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w800, color: heroCream)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: heroCream.withValues(alpha: 0.75))),
          ],
        ),
      );
}

/// Смужка прогресу рівня — у кольорі рівня, з відблиском, на темному тлі.
class HeroProgress extends StatelessWidget {
  const HeroProgress({super.key, required this.value, required this.label, required this.accent});

  final double value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Color.lerp(accent, Colors.white, 0.35)!, accent]),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 8)],
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: heroCream.withValues(alpha: 0.82))),
        ],
      );
}

// ─── Решта вкладки: пергамент, медальйони, вітрина ──────────────────────────

/// Пергаментна картка з тонкою золотавою облямівкою; з [onTap] — натискається.
class ParchmentCard extends StatelessWidget {
  const ParchmentCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14), this.radius = 18});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFFBEF), Color(0xFFF6ECD3)]),
          border: Border.all(color: const Color(0xFFC9A45C).withValues(alpha: 0.45)),
          boxShadow: [BoxShadow(color: const Color(0xFF3B2A12).withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

/// Іконка-медальйон: кругла, золото-бурштинова, з тонким обідком — як рамки аватарів.
class MedallionIcon extends StatelessWidget {
  const MedallionIcon(this.icon, {super.key, this.size = 44, this.danger = false});

  final IconData icon;
  final double size;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.4),
            colors: danger ? const [Color(0xFFF3C1B5), Color(0xFFC0533F)] : const [Color(0xFFFFE6A6), Color(0xFFD9962F)],
          ),
          border: Border.all(color: danger ? const Color(0xFF8E2F1F) : const Color(0xFF8A5A1C), width: 1.5),
          boxShadow: [BoxShadow(color: const Color(0xFF3B2A12).withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, size: size * 0.5, color: danger ? const Color(0xFF5E1A10) : _forest),
      );
}

/// Рядок-кнопка на пергаменті: медальйон, назва, підпис, стрілка.
class ParchmentTile extends StatelessWidget {
  const ParchmentTile({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.danger = false, this.trailing, this.badge});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;

  /// Число в кружечку (нові запити тощо).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFF9A2A1A) : _forest;
    return ParchmentCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        children: [
          MedallionIcon(icon, danger: danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.merriweather(fontSize: 14.5, fontWeight: FontWeight.w700, color: color)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12.5, color: _ink.withValues(alpha: 0.65))),
                  ),
              ],
            ),
          ),
          if (badge != null && badge! > 0)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: _amber, borderRadius: BorderRadius.circular(10)),
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          trailing ?? (onTap == null ? const SizedBox.shrink() : Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

/// Вітрина трофеїв: темний оксамит у золотій рамці, медальйони сяють на ньому.
class TrophyShowcase extends StatelessWidget {
  const TrophyShowcase({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const RadialGradient(center: Alignment(0, -0.6), radius: 1.3, colors: [Color(0xFF2A4A30), Color(0xFF122619)]),
          border: Border.all(color: const Color(0xFFC9A45C), width: 1.5),
          boxShadow: [BoxShadow(color: const Color(0xFF3B2A12).withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: child,
      );
}

/// Полиця під медальйонами — темне дерево з відблиском.
class TrophyShelf extends StatelessWidget {
  const TrophyShelf({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 7,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFA9773F), Color(0xFF5E3A1A)]),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 6, offset: const Offset(0, 3))],
        ),
      );
}

/// Заголовок розділу: листочок, Merriweather і золотава риска, що згасає.
class ProfileSectionTitle extends StatelessWidget {
  const ProfileSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10, left: 2),
        child: Row(
          children: [
            const Icon(Icons.eco_rounded, size: 18, color: _amber),
            const SizedBox(width: 6),
            Text(title, style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold, color: _forest)),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFFC9A45C).withValues(alpha: 0.7), Colors.transparent])),
              ),
            ),
          ],
        ),
      );
}
