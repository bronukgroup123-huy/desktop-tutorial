import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/forecast.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart' show SpeciesIcon;

/// «Як відрізнити» (рішення PO 2026-11-15): ознаки з довідника — кожна з анімованим
/// стікером-схемою гриба, де підсвічено потрібну частину (шапка переливається її кольорами,
/// низ шапки — трубочки / пластинки / складки / шипи, ніжка, кільце є чи немає); далі —
/// двійник поруч із відмінностями ✓ / ✗ і головне правило. Анімація — один раз під час
/// відкриття; без анімацій у системі — одразу кінцевий вигляд.
class IdentifyView extends StatefulWidget {
  const IdentifyView({super.key, required this.card, required this.species});

  final IdentifyCard card;
  final ForecastSpecies species;

  @override
  State<IdentifyView> createState() => _IdentifyViewState();
}

class _IdentifyViewState extends State<IdentifyView> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  /// Переливання кольорів шапки — кілька разів, потім зупиняється.
  late final AnimationController _colors = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _intro.value = 1;
      _colors.value = 0;
    } else if (!_intro.isAnimating && _intro.value == 0) {
      _intro.forward();
      _colors.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _colors.dispose();
    super.dispose();
  }

  /// Поява i-го елемента з n: зсув і прозорість.
  Widget _appear(int i, int n, Widget child) => AnimatedBuilder(
        animation: _intro,
        builder: (context, c) {
          final start = i / (n + 1);
          final v = Curves.easeOutBack.transform(((_intro.value - start) / (1 / (n + 1) * 1.6)).clamp(0.0, 1.0));
          return Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: c),
          );
        },
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final rows = <Widget>[
      for (final f in card.features)
        _FeatureRow(
            glyph: _PartGlyph(
              part: f.part,
              kind: f.kind ?? card.underside,
              colors: [for (final c in card.capColors) c.color],
              anim: _colors,
            ),
            title: f.title,
            text: f.text,
            extra: f.part == 'cap' && card.capColors.isNotEmpty
                ? Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final c in card.capColors)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: c.color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(c.label, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        ),
                    ],
                  )
                : null,
          ),
      if (card.ring != null)
        _FeatureRow(
          glyph: _PartGlyph(part: 'ring', ring: card.ring, colors: const [], anim: _colors),
          title: 'Кільце на ніжці',
          text: card.ring! ? 'Є — «спідничка» на ніжці' : 'Немає кільця',
          badge: card.ring!
              ? const Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.success)
              : const Icon(Icons.cancel_rounded, size: 18, color: AppTheme.danger),
        ),
    ];
    final twin = card.twin;
    final n = rows.length + (twin == null ? 0 : 1) + (card.rule == null ? 0 : 1);
    var k = 0;
    return Column(
      key: const ValueKey('identify-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows) _appear(k++, n, r),
        if (twin != null) ...[
          const SizedBox(height: 10),
          _appear(k++, n, _TwinCompare(twin: twin, species: widget.species, intro: _intro)),
        ],
        if (card.rule != null) ...[
          const SizedBox(height: 10),
          _appear(
            k++,
            n,
            Container(
              key: const ValueKey('identify-rule'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfffff4d6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 20, color: Color(0xffb7791f)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(card.rule!, style: const TextStyle(color: Color(0xff6b4a12)))),
                ],
              ),
            ),
          ),
        ],
        // Повний опис і фото — у довіднику (рішення PO 2026-11-15).
        _CatalogLink(speciesId: widget.species.mushroomType),
      ],
    );
  }
}

/// «Переглянути в довіднику» → сторінка цього ж виду з фото й описом; немає виду — не показуємо.
class _CatalogLink extends ConsumerWidget {
  const _CatalogLink({required this.speciesId});

  final String speciesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final has = ref.watch(catalogProvider.select((c) => c.valueOrNull?.byId(speciesId) != null));
    if (!has) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const ValueKey('identify-catalog'),
          onPressed: () => context.push('/catalog/$speciesId'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.darkGreen,
            side: const BorderSide(color: AppTheme.darkGreen),
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.menu_book_rounded, size: 20),
          label: const Text('Переглянути в довіднику'),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.glyph, required this.title, required this.text, this.extra, this.badge});

  final Widget glyph;
  final String title;
  final String text;
  final Widget? extra;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: const Color(0xfff4f1e8), borderRadius: BorderRadius.circular(12)),
              child: glyph,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                      if (badge != null) ...[const SizedBox(width: 6), badge!],
                    ],
                  ),
                  Text(text, style: TextStyle(color: AppTheme.textMuted, height: 1.25)),
                  if (extra != null) ...[const SizedBox(height: 4), extra!],
                ],
              ),
            ),
          ],
        ),
      );
}

/// Двійник поруч: наш гриб і двійник (сірий, зі знаком небезпеки), відмінності ✓ / ✗.
class _TwinCompare extends StatelessWidget {
  const _TwinCompare({required this.twin, required this.species, required this.intro});

  final IdentifyTwin twin;
  final ForecastSpecies species;
  final Animation<double> intro;

  @override
  Widget build(BuildContext context) {
    final danger = twin.dangerous;
    final red = AppTheme.danger;
    final dangerColor = danger ? red : const Color(0xff8a6d3b);
    return Container(
      key: const ValueKey('identify-twin'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger ? red.withValues(alpha: 0.05) : const Color(0xfff7f5ef),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: danger ? red.withValues(alpha: 0.7) : Colors.transparent, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows_rounded, size: 18, color: dangerColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Не сплутайте',
                    style: TextStyle(fontWeight: FontWeight.w800, color: dangerColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    SpeciesIcon(type: species.mushroomType, fallbackColor: species.levelColor, size: 46),
                    const SizedBox(height: 4),
                    Text(species.nameUa,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen, fontSize: 13)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text('vs', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xff9e9e9e))),
              ),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Positioned.fill(child: CustomPaint(painter: _GenericMushroomPainter())),
                          if (danger)
                            Positioned(
                              right: -6,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: Icon(Icons.warning_rounded, size: 16, color: red),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(twin.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff555555), fontSize: 13)),
                    Text(twin.dangerLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dangerColor)),
                  ],
                ),
              ),
            ],
          ),
          for (final (i, d) in twin.diffs.indexed)
            AnimatedBuilder(
              animation: intro,
              builder: (context, child) {
                final v = ((intro.value - 0.55 - i * 0.12) / 0.2).clamp(0.0, 1.0);
                return Opacity(opacity: v, child: child);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    Text(d.feature,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _DiffCell(text: d.ours, good: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _DiffCell(text: d.twin, good: false)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DiffCell extends StatelessWidget {
  const _DiffCell({required this.text, required this.good});

  final String text;
  final bool good;

  @override
  Widget build(BuildContext context) {
    // Книжкові ✅ / ❌ — у значок, а не в текст.
    final clean = text.replaceAll(RegExp(r'[✅❌]\s*'), '');
    final color = good ? AppTheme.success : AppTheme.danger;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(good ? Icons.check_rounded : Icons.close_rounded, size: 16, color: color),
        const SizedBox(width: 3),
        Expanded(child: Text(clean, style: TextStyle(fontSize: 13, color: AppTheme.darkGreen))),
      ],
    );
  }
}

/// Двійник — узагальнений гриб у сірих тонах (окремих малюнків двійників немає).
class _GenericMushroomPainter extends CustomPainter {
  const _GenericMushroomPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 46;
    final stroke = Paint()
      ..color = const Color(0xff555555)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * s;
    final stem = RRect.fromRectAndRadius(Rect.fromLTWH(19 * s, 22 * s, 8 * s, 20 * s), Radius.circular(3 * s));
    canvas.drawRRect(stem, Paint()..color = const Color(0xffe6e6e6));
    canvas.drawRRect(stem, stroke);
    final cap = Path()
      ..moveTo(6 * s, 25 * s)
      ..quadraticBezierTo(23 * s, -2 * s, 40 * s, 25 * s)
      ..close();
    canvas.drawPath(cap, Paint()..color = const Color(0xffb0b0b0));
    canvas.drawPath(cap, stroke);
    for (final p in [Offset(16 * s, 16 * s), Offset(26 * s, 13 * s), Offset(31 * s, 19 * s)]) {
      canvas.drawCircle(p, 1.8 * s, Paint()..color = Colors.white.withValues(alpha: 0.7));
    }
  }

  @override
  bool shouldRepaint(_GenericMushroomPainter old) => false;
}

/// Стікер-схема гриба з підсвіченою частиною.
class _PartGlyph extends StatelessWidget {
  const _PartGlyph({required this.part, required this.colors, required this.anim, this.kind, this.ring});

  final String part;
  final String? kind;
  final bool? ring;
  final List<Color> colors;
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) => CustomPaint(
        key: ValueKey('glyph-$part'),
        painter: _GlyphPainter(part: part, kind: kind, ring: ring, colors: colors, anim: anim),
      );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.part, required this.kind, required this.ring, required this.colors, required this.anim})
      : super(repaint: anim);

  final String part;
  final String? kind;
  final bool? ring;
  final List<Color> colors;
  final Animation<double> anim;

  static const _dim = Color(0xffd9d2c3);
  static const _ink = Color(0xff4a3b2a);
  static const _hi = AppTheme.success;

  Color get _capColor {
    if (colors.isEmpty) return const Color(0xff8b5a2b);
    if (colors.length == 1) return colors.first;
    final t = anim.value * colors.length;
    final i = t.floor() % colors.length;
    return Color.lerp(colors[i], colors[(i + 1) % colors.length], Curves.easeInOut.transform(t - t.floor()))!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 46;
    canvas.translate(0, 1 * s);
    final stroke = Paint()
      ..color = _ink.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * s;
    final hiStroke = Paint()
      ..color = _hi
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s;

    // Ніжка.
    final stemHi = part == 'stem' || part == 'ring';
    final stem = RRect.fromRectAndRadius(Rect.fromLTWH(19 * s, 21 * s, 8 * s, 19 * s), Radius.circular(3 * s));
    canvas.drawRRect(stem, Paint()..color = stemHi ? const Color(0xfff6ecd2) : _dim.withValues(alpha: 0.6));
    canvas.drawRRect(stem, part == 'stem' ? hiStroke : stroke);

    // Шапка (купол).
    final capHi = part == 'cap';
    final cap = Path()
      ..moveTo(5 * s, 22 * s)
      ..quadraticBezierTo(23 * s, -4 * s, 41 * s, 22 * s)
      ..close();
    canvas.drawPath(cap, Paint()..color = capHi ? _capColor : _dim);
    canvas.drawPath(cap, capHi ? hiStroke : stroke);
    if (capHi) {
      canvas.drawPath(
        Path()
          ..moveTo(13 * s, 13 * s)
          ..quadraticBezierTo(22 * s, 6 * s, 31 * s, 12 * s),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * s
          ..strokeCap = StrokeCap.round,
      );
    }

    // Низ шапки — візерунок за типом.
    final under = Rect.fromLTWH(6 * s, 20 * s, 34 * s, 5 * s);
    final underHi = part == 'underside';
    canvas.drawRRect(RRect.fromRectAndRadius(under, Radius.circular(2 * s)),
        Paint()..color = underHi ? const Color(0xfff3e3b5) : _dim.withValues(alpha: 0.8));
    final pat = Paint()
      ..color = underHi ? _ink : _ink.withValues(alpha: 0.3)
      ..strokeWidth = 1 * s;
    switch (kind) {
      case 'tubes':
        for (var x = 9.0; x < 39; x += 3.5) {
          canvas.drawCircle(Offset(x * s, 22.5 * s), 0.9 * s, pat);
        }
      case 'folds':
        for (var x = 9.0; x < 39; x += 4.5) {
          canvas.drawLine(Offset(x * s, 20.5 * s), Offset((x + 1.5) * s, 24.5 * s), pat..strokeWidth = 1.6 * s);
        }
      case 'spines':
        for (var x = 8.0; x < 39; x += 3) {
          canvas.drawLine(Offset(x * s, 21 * s), Offset(x * s, 26.5 * s), pat);
        }
      default: // пластинки
        for (var x = 8.0; x < 39; x += 2.2) {
          canvas.drawLine(Offset(x * s, 20.5 * s), Offset(x * s, 24.5 * s), pat);
        }
    }
    if (underHi) canvas.drawRRect(RRect.fromRectAndRadius(under, Radius.circular(2 * s)), hiStroke);

    // Кільце.
    if (part == 'ring') {
      final band = Rect.fromLTWH(16 * s, 27 * s, 14 * s, 4 * s);
      if (ring == true) {
        // «Спідничка» трохи коливається.
        final sway = math.sin(anim.value * 2 * math.pi) * 0.6 * s;
        canvas.drawOval(band.shift(Offset(sway, 0)), Paint()..color = Colors.white);
        canvas.drawOval(band.shift(Offset(sway, 0)), hiStroke);
      } else {
        final dash = Paint()
          ..color = AppTheme.danger
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 * s;
        for (var a = 0.0; a < 2 * math.pi; a += math.pi / 5) {
          canvas.drawArc(band, a, math.pi / 10, false, dash);
        }
      }
    }
    // М'якоть — розріз ніжки.
    if (part == 'flesh') {
      canvas.drawRect(Rect.fromLTWH(21 * s, 23 * s, 4 * s, 15 * s), Paint()..color = Colors.white);
      canvas.drawRRect(stem, hiStroke);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.part != part || old.kind != kind || old.ring != ring;
}

/// Схема гриба з підсвіченою частиною (шапка, низ шапки, ніжка, кільце, м'якоть) — без анімації;
/// для «паспорта» виду в довіднику.
class PartGlyph extends StatelessWidget {
  const PartGlyph({super.key, required this.part, this.kind});

  final String part;

  /// Для низу шапки: `tubes | gills | folds | spines`.
  final String? kind;

  @override
  Widget build(BuildContext context) =>
      _PartGlyph(part: part, kind: kind, colors: const [], anim: const AlwaysStoppedAnimation(0));
}
