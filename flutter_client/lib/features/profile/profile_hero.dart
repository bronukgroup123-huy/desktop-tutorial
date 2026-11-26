import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_client/core/app_theme.dart';

/// Оформлення вкладки «Профіль» у стилі аватарів (PO 2026-11-21): шапка — ліс у світлі, що
/// змінюється з рівнем (як рамки аватарів: береза → дуб → мох → камінь → бронза → золото);
/// вітрина трофеїв — дубова поличка. Решта вкладки — спільні картки й плитки (core/ui.dart, UI-004).
/// Лише вигляд — тексти й дані приходять із сервера.

const heroCream = AppTheme.backgroundColor;
const heroGold = Color(0xFFF9C66B);

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

/// Тло шапки: ліс у світлі рівня, світіння за аватаром, промені; спори в повітрі повільно
/// пливуть угору й мерехтять (PO 2026-11-21). Анімований лише шар спор — окремим
/// `RepaintBoundary`, решта малюється раз; у вимкнених анімаціях системи — нерухомо.
class ProfileHeroBackground extends StatefulWidget {
  const ProfileHeroBackground({super.key, required this.child, this.levelId, this.glowCenterY = 0.36});

  final Widget child;
  final String? levelId;

  /// Де світіння по вертикалі (0 — верх, 1 — низ), щоб воно стояло за аватаром.
  final double glowCenterY;

  @override
  State<ProfileHeroBackground> createState() => _ProfileHeroBackgroundState();
}

class _ProfileHeroBackgroundState extends State<ProfileHeroBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _spores = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _spores.stop();
    } else if (!_spores.isAnimating) {
      _spores.repeat();
    }
  }

  @override
  void dispose() {
    _spores.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = heroPalette(widget.levelId);
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.top, p.bottom]),
        ),
        child: CustomPaint(
          painter: _HeroPainter(widget.glowCenterY, p),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: IgnorePointer(child: CustomPaint(painter: _SporesPainter(_spores, p.spore))),
                ),
              ),
              widget.child,
            ],
          ),
        ),
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

/// Спори: кожна пливе вгору зі своєю швидкістю, трохи гойдається і мерехтить; за верхнім
/// краєм з'являється знизу знову.
class _SporesPainter extends CustomPainter {
  _SporesPainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  static final List<({double x, double y, double r, double speed, double sway, double phase, double a})> _spores = () {
    final rnd = math.Random(7);
    return [
      for (var i = 0; i < 34; i++)
        (
          x: rnd.nextDouble(),
          y: rnd.nextDouble(),
          r: 0.8 + rnd.nextDouble() * 2.2,
          speed: 1 + rnd.nextInt(2).toDouble(), // проходить висоту 1–2 рази за цикл
          sway: 4 + rnd.nextDouble() * 10,
          phase: rnd.nextDouble() * math.pi * 2,
          a: 0.25 + rnd.nextDouble() * 0.45,
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final dot = Paint();
    final halo = Paint();
    for (final s in _spores) {
      final y = ((s.y - v * s.speed * 0.5) % 1.0 + 1.0) % 1.0;
      final angle = v * math.pi * 2 * s.speed + s.phase;
      final o = Offset(s.x * size.width + math.sin(angle) * s.sway, y * size.height);
      final twinkle = 0.6 + 0.4 * math.sin(angle * 2);
      dot.color = color.withValues(alpha: s.a * twinkle);
      canvas.drawCircle(o, s.r, dot);
      if (s.r > 2.2) {
        halo.color = color.withValues(alpha: 0.07 * twinkle);
        canvas.drawCircle(o, s.r * 3, halo);
      }
    }
  }

  @override
  bool shouldRepaint(_SporesPainter old) => old.color != color;
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
          Text(label, style: TextStyle(fontFamily: AppTheme.serif, fontSize: 13, fontWeight: FontWeight.w700, color: p.badgeText)),
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
            Text(value, style: TextStyle(fontFamily: AppTheme.serif, fontSize: 14, fontWeight: FontWeight.w800, color: heroCream)),
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

/// Вітрина трофеїв — темна дубова поличка (PO 2026-11-21): задня стінка з дошок морного дуба
/// (текстура `assets/textures/oak_dark.webp`: кільця, пори, промені, сучки — збирає
/// `scripts/textures/oak.py`), рамка з того ж дуба, ще темніша, з фаскою.
class TrophyShowcase extends StatelessWidget {
  const TrophyShowcase({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF2A190C),
          image: const DecorationImage(
            image: AssetImage('assets/textures/oak_plank.webp'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Color(0x99140A03), BlendMode.darken),
          ),
          boxShadow: [BoxShadow(color: const Color(0xFF1E1208).withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        padding: const EdgeInsets.all(6), // рамка
        child: DecoratedBox(
          // фаска рамки: світла кромка згори, темна знизу
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFF9C6B3C).withValues(alpha: 0.55)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF3A2414),
                image: DecorationImage(image: AssetImage('assets/textures/oak_dark.webp'), fit: BoxFit.cover),
              ),
              child: DecoratedBox(
                // тінь від рамки всередину
                decoration: const BoxDecoration(
                  gradient: RadialGradient(radius: 1.05, colors: [Colors.transparent, Color(0x66140A03)], stops: [0.6, 1]),
                ),
                child: Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), child: child),
              ),
            ),
          ),
        ),
      );
}

/// Дубова полиця під медальйонами: верхня грань — світліша (на неї падає світло), передня —
/// темніша, під полицею — тінь на задню стінку.
class OakShelfPlank extends StatelessWidget {
  const OakShelfPlank({super.key});

  static const _wood = DecorationImage(image: AssetImage('assets/textures/oak_plank.webp'), fit: BoxFit.cover);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF6E4524),
              image: DecorationImage(
                image: AssetImage('assets/textures/oak_plank.webp'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Color(0x40F2C48A), BlendMode.lighten),
              ),
            ),
          ),
          Container(
            height: 1,
            color: const Color(0xFFD9A86A).withValues(alpha: 0.55), // кромка
          ),
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFF3A2414),
              image: _wood,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 9, offset: const Offset(0, 5))],
            ),
            foregroundDecoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x22000000), Color(0x88140A03)]),
            ),
          ),
        ],
      );
}

