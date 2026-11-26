import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';

/// «Розширені дані погоди» (рішення PO 2026-11-15): не сирий графік, а відповіді грибнику —
/// смужка «дощ → гриби» (опади, дощі-поштовхи, температура дня крапкою, вікно хвилі), що вже
/// сталося, три шкали (вологість ґрунту, тепло, дощ за 2 тижні) і що далі.
class WeatherInsightView extends StatelessWidget {
  const WeatherInsightView({
    super.key,
    required this.insight,
    required this.selected,
    this.selectable = const {},
    this.onSelect,
  });

  final WeatherInsight insight;
  final String selected;
  final Set<String> selectable;
  final ValueChanged<String>? onSelect;

  static const rainColor = Color(0xff4a90d9);
  static const soakColor = Color(0xff1f65b5);
  static const waveColor = Color(0xff43a047);
  static const tempColors = {
    'frost': Color(0xff3d8fe0),
    'cold': Color(0xffa9c3d6),
    'ok': Color(0xff66bb6a),
    'hot': Color(0xffef6c00),
  };

  static const _tone = {
    'good': AppTheme.success,
    'bad': Color(0xffd9480f),
    'neutral': Color(0xff6b7a70),
  };

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.textMuted;
    final title = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textMuted);
    return Column(
      key: const ValueKey('weather-insight'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Дощ → гриби ───
        if (insight.days.length > 1) ...[
          Text(insight.stripTitle ?? 'Дощі й гриби', style: title),
          if (insight.wave != null) ...[
            const SizedBox(height: 6),
            Container(
              key: const ValueKey('insight-wave'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: waveColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.eco_rounded, size: 16, color: waveColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(insight.wave!.label,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.success)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, 128);
            return GestureDetector(
              key: const ValueKey('insight-strip'),
              behavior: HitTestBehavior.opaque,
              onTapUp: onSelect == null
                  ? null
                  : (d) {
                      final n = insight.days.length;
                      final i = (d.localPosition.dx / (size.width / n)).floor().clamp(0, n - 1);
                      final date = insight.days[i].date;
                      if (selectable.contains(date)) onSelect!(date);
                    },
              child: CustomPaint(
                size: size,
                painter: _StripPainter(
                  insight: insight,
                  selected: selected,
                  baseStyle: DefaultTextStyle.of(context).style,
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _LegendItem(
                swatch: const Icon(Icons.water_drop_rounded, size: 13, color: soakColor),
                text: insight.legend['soaking'] ?? 'дощ промочив ґрунт',
              ),
              for (final k in const ['frost', 'cold', 'ok', 'hot'])
                if (insight.legend[k] != null)
                  _LegendItem(
                    swatch: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: tempColors[k], shape: BoxShape.circle),
                    ),
                    text: insight.legend[k]!,
                  ),
            ],
          ),
        ],
        // ─── Що вже сталося ───
        if (insight.events.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(insight.eventsTitle ?? 'Що вже сталося', style: title),
          for (final e in insight.events)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_eventIcon(e.icon), size: 18, color: _eventColor(e.icon)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.label, style: const TextStyle(color: AppTheme.darkGreen))),
                ],
              ),
            ),
        ],
        // ─── Шкали ───
        if (insight.gauges.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final g in insight.gauges) _Gauge(gauge: g, color: _tone[g.tone] ?? _tone['neutral']!),
        ],
        // ─── Що далі ───
        if (insight.outlookLabel != null) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('insight-outlook'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.darkGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.trending_flat_rounded, size: 20, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${insight.outlookTitle ?? 'Що далі'}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: insight.outlookLabel),
                  ]), style: const TextStyle(color: AppTheme.darkGreen)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static IconData _eventIcon(String icon) => switch (icon) {
        'rain' => Icons.water_drop_rounded,
        'frost' => Icons.ac_unit_rounded,
        'thaw' => Icons.wb_twilight_rounded,
        'dry' => Icons.wb_sunny_rounded,
        _ => Icons.circle_outlined,
      };

  static Color _eventColor(String icon) => switch (icon) {
        'rain' => soakColor,
        'frost' => const Color(0xff3d8fe0),
        'thaw' => const Color(0xffe0a100),
        'dry' => const Color(0xffef6c00),
        _ => AppTheme.darkGreen,
      };
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.swatch, required this.text});

  final Widget swatch;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          swatch,
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      );
}

/// Шкала: кроки з позначкою поточного або смужка заповнення з межею «досить».
class _Gauge extends StatelessWidget {
  const _Gauge({required this.gauge, required this.color});

  final InsightGauge gauge;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final g = gauge;
    final muted = AppTheme.textMuted;
    final current = g.index != null && g.index! >= 0 && g.index! < g.steps.length ? g.steps[g.index!] : null;
    return Padding(
      key: ValueKey('gauge-${g.key}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(g.title, style: const TextStyle(fontSize: 13, color: AppTheme.darkGreen))),
              Text(
                g.valueLabel ?? current ?? '',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (g.steps.isNotEmpty && g.index != null) ...[
            Row(
              children: [
                for (var i = 0; i < g.steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == g.index ? color : AppTheme.darkGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(i == 0 ? 4 : 1),
                          right: Radius.circular(i == g.steps.length - 1 ? 4 : 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                for (var i = 0; i < g.steps.length; i++)
                  Expanded(
                    child: Text(
                      g.steps[i],
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: i == g.index ? color : muted,
                        fontWeight: i == g.index ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
          ] else if (g.fill != null)
            LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 12,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          top: 2,
                          bottom: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppTheme.darkGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 2,
                          bottom: 2,
                          width: math.max(4, w * g.fill!.clamp(0, 1)),
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        if (g.mark != null)
                          Positioned(
                            left: w * g.mark!.clamp(0, 1) - 1,
                            top: 0,
                            bottom: 0,
                            width: 2,
                            child: const ColoredBox(color: AppTheme.darkGreen),
                          ),
                      ],
                    ),
                  ),
                  if (g.markLabel != null && g.mark != null)
                    Padding(
                      padding: EdgeInsets.only(left: math.max(0, w * g.mark!.clamp(0, 1) - 4), top: 2),
                      child: Text(g.markLabel!, style: TextStyle(fontSize: 11, color: muted)),
                    ),
                ],
              );
            }),
          if (g.hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(g.hint!, style: TextStyle(fontSize: 12, color: muted, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({required this.insight, required this.selected, required this.baseStyle, required this.textScaler});

  final WeatherInsight insight;
  final String selected;
  final TextStyle baseStyle;
  final TextScaler textScaler;

  void _text(Canvas canvas, String s, Offset center, {double size = 9.5, Color? color, FontWeight? weight, bool above = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: baseStyle.copyWith(fontSize: size, color: color ?? AppTheme.darkGreen, fontWeight: weight, height: 1.1)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler.clamp(maxScaleFactor: 1.15),
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, above ? center.dy - tp.height : center.dy));
  }

  void _drop(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r * 1.6)
      ..quadraticBezierTo(c.dx + r * 1.1, c.dy - r * 0.2, c.dx + r, c.dy + r * 0.2)
      ..arcToPoint(Offset(c.dx - r, c.dy + r * 0.2), radius: Radius.circular(r), clockwise: true)
      ..quadraticBezierTo(c.dx - r * 1.1, c.dy - r * 0.2, c.dx, c.dy - r * 1.6)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final days = insight.days;
    final n = days.length;
    final colW = size.width / n;
    const top = 16.0; // місце для крапель-поштовхів і чисел над стовпчиками
    final barsBottom = size.height - 40;
    final dotY = barsBottom + 9;
    final labelY = barsBottom + 17;

    // Вікно хвилі — зелена підкладка колонок.
    final wave = insight.wave;
    if (wave != null) {
      final from = days.indexWhere((d) => d.date.compareTo(wave.from) >= 0);
      if (from >= 0) {
        final toIdx = wave.to == null ? n - 1 : days.lastIndexWhere((d) => d.date.compareTo(wave.to!) <= 0);
        if (toIdx >= from) {
          final rect = Rect.fromLTRB(from * colW + 1, 0, (toIdx + 1) * colW - 1, barsBottom + 2);
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)),
              Paint()..color = WeatherInsightView.waveColor.withValues(alpha: 0.10));
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTRB(rect.left, 0, rect.right, 4), const Radius.circular(2)),
            Paint()..color = WeatherInsightView.waveColor.withValues(alpha: 0.7),
          );
        }
      }
    }

    // Обраний день.
    final sel = days.indexWhere((d) => d.date == selected);
    if (sel >= 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(sel * colW + 1, 6, colW - 2, size.height - 6), const Radius.circular(8)),
        Paint()
          ..color = AppTheme.darkGreen.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Межа «було | прогноз».
    final firstForecast = days.indexWhere((d) => d.forecast);
    if (firstForecast > 0) {
      final x = firstForecast * colW;
      final dash = Paint()
        ..color = AppTheme.darkGreen.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      for (var y = 6.0; y < barsBottom; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(barsBottom, y + 3)), dash);
      }
    }

    final maxRain = math.max(10.0, days.map((d) => d.rain).reduce(math.max));
    for (var i = 0; i < n; i++) {
      final d = days[i];
      final cx = i * colW + colW / 2;
      final bw = math.min(14.0, colW * 0.6);
      if (d.rain >= 0.5) {
        final h = math.max(3.0, (d.rain / maxRain) * (barsBottom - top - 10));
        final color = (d.soaking ? WeatherInsightView.soakColor : WeatherInsightView.rainColor)
            .withValues(alpha: d.forecast ? 0.5 : 1);
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(cx - bw / 2, barsBottom - h, bw, h),
              topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
          Paint()..color = color,
        );
        if (d.soaking) {
          _drop(canvas, Offset(cx, barsBottom - h - 13), 3.6, WeatherInsightView.soakColor.withValues(alpha: d.forecast ? 0.6 : 1));
        }
        _text(canvas, '${d.rain.round()}', Offset(cx, barsBottom - h - (d.soaking ? 19 : 1)),
            color: WeatherInsightView.soakColor, weight: FontWeight.w600, above: true);
      } else {
        canvas.drawLine(Offset(cx - bw / 2, barsBottom), Offset(cx + bw / 2, barsBottom),
            Paint()
              ..color = WeatherInsightView.rainColor.withValues(alpha: 0.25)
              ..strokeWidth = 1.5);
      }
      // Температура дня — крапка.
      canvas.drawCircle(Offset(cx, dotY), 3.6,
          Paint()..color = (WeatherInsightView.tempColors[d.temp] ?? Colors.grey).withValues(alpha: d.forecast ? 0.6 : 1));
      final strong = d.today || i == sel;
      _text(canvas, d.label, Offset(cx, labelY),
          size: 9.5, weight: strong ? FontWeight.w800 : FontWeight.w400,
          color: AppTheme.darkGreen.withValues(alpha: d.forecast || d.today ? 1 : 0.6));
      _text(canvas, d.dateLabel, Offset(cx, labelY + 12), size: 8.5, color: AppTheme.textMuted);
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.insight != insight || old.selected != selected;
}
