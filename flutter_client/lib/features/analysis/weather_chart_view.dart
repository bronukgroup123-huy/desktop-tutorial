import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';

/// Графік погоди ділянки (рішення PO 2026-11-15): стовпчики опадів і смуга температури
/// (мінімум—максимум) за тиждень до сьогодні та дні прогнозу. Обраний день підсвічено;
/// торкнутися дня прогнозу — обрати його (як у смужці днів).
class WeatherChartView extends StatelessWidget {
  const WeatherChartView({super.key, required this.chart, required this.selected, this.onSelect, this.selectable = const {}});

  final WeatherChart chart;

  /// Дата обраного дня («YYYY-MM-DD»).
  final String selected;

  /// Які дні можна обрати (дні смужки); інші — лише показ.
  final Set<String> selectable;
  final ValueChanged<String>? onSelect;

  static const rainColor = Color(0xff3b8fd4);
  static const maxColor = Color(0xffe8833a);
  static const minColor = Color(0xff6aa9d8);

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final size = Size(box.maxWidth, 168);
            return GestureDetector(
              key: const ValueKey('weather-chart'),
              behavior: HitTestBehavior.opaque,
              onTapUp: onSelect == null
                  ? null
                  : (d) {
                      final n = chart.days.length;
                      final i = (d.localPosition.dx / (size.width / n)).floor().clamp(0, n - 1);
                      final date = chart.days[i].date;
                      if (selectable.contains(date)) onSelect!(date);
                    },
              child: CustomPaint(
                size: size,
                painter: _WeatherChartPainter(
                  chart: chart,
                  selected: selected,
                  textScaler: MediaQuery.textScalerOf(context),
                  baseStyle: DefaultTextStyle.of(context).style,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _Legend(color: rainColor, bar: true, text: chart.rainLegendLabel ?? 'опади, мм'),
            _Legend(color: maxColor, text: 'макс. °'),
            _Legend(color: minColor, text: 'мін. °'),
            if (chart.days.any((d) => d.forecast))
              Text('світліше — прогноз', style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text, this.bar = false});

  final Color color;
  final String text;
  final bool bar;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: bar ? 8 : 14,
            height: bar ? 10 : 3,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: AppTheme.darkGreen.withValues(alpha: 0.7))),
        ],
      );
}

class _WeatherChartPainter extends CustomPainter {
  _WeatherChartPainter({required this.chart, required this.selected, required this.textScaler, required this.baseStyle});

  final WeatherChart chart;
  final String selected;
  final TextScaler textScaler;

  /// Шрифт застосунку — підписи графіка тим самим шрифтом, що й решта екрана.
  final TextStyle baseStyle;

  // Висоти зон: температура зверху, опади знизу, підписи днів унизу.
  static const double _labelsH = 30;
  static const double _gap = 8;

  void _text(Canvas canvas, String s, Offset center, {double size = 10, Color? color, FontWeight? weight, bool above = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: baseStyle.copyWith(fontSize: size, color: color ?? AppTheme.darkGreen, fontWeight: weight, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler.clamp(maxScaleFactor: 1.2),
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, above ? center.dy - tp.height : center.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final days = chart.days;
    final n = days.length;
    if (n == 0) return;
    final colW = size.width / n;
    final plotH = size.height - _labelsH;
    final tempTop = 14.0, tempBottom = plotH * 0.56;
    final rainTop = tempBottom + _gap + 10, rainBottom = plotH;

    // Обраний день — підсвічена колонка.
    final sel = days.indexWhere((d) => d.date == selected);
    if (sel >= 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(sel * colW + 2, 0, colW - 4, size.height), const Radius.circular(10)),
        Paint()..color = AppTheme.darkGreen.withValues(alpha: 0.07),
      );
    }

    // Межа «факт | прогноз».
    final firstForecast = days.indexWhere((d) => d.forecast);
    if (firstForecast > 0) {
      final x = firstForecast * colW;
      final dash = Paint()
        ..color = AppTheme.darkGreen.withValues(alpha: 0.25)
        ..strokeWidth = 1;
      for (var y = 0.0; y < plotH; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(plotH, y + 3)), dash);
      }
    }

    // Опади — стовпчики.
    final maxRain = math.max(10.0, days.map((d) => d.rain).reduce(math.max));
    for (var i = 0; i < n; i++) {
      final d = days[i];
      final cx = i * colW + colW / 2;
      final h = (d.rain / maxRain) * (rainBottom - rainTop);
      final bw = math.min(18.0, colW * 0.5);
      final color = WeatherChartView.rainColor.withValues(alpha: d.forecast ? 0.45 : 0.9);
      if (d.rain >= 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(cx - bw / 2, rainBottom - math.max(2, h), bw, math.max(2, h)),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = color,
        );
        _text(canvas, '${d.rain.round()}', Offset(cx, rainBottom - math.max(2, h) - 1),
            size: 10, color: WeatherChartView.rainColor, weight: FontWeight.w600, above: true);
      } else {
        canvas.drawLine(Offset(cx - bw / 2, rainBottom), Offset(cx + bw / 2, rainBottom),
            Paint()..color = WeatherChartView.rainColor.withValues(alpha: 0.25)..strokeWidth = 1.5);
      }
    }

    // Температура — смуга мін…макс і дві лінії.
    final lo = days.map((d) => d.tmin).reduce(math.min);
    final hi = days.map((d) => d.tmax).reduce(math.max);
    final span = math.max(4.0, hi - lo);
    double ty(double t) => tempBottom - (t - lo) / span * (tempBottom - tempTop);
    final maxPts = [for (var i = 0; i < n; i++) Offset(i * colW + colW / 2, ty(days[i].tmax))];
    final minPts = [for (var i = 0; i < n; i++) Offset(i * colW + colW / 2, ty(days[i].tmin))];
    final band = Path()..moveTo(maxPts.first.dx, maxPts.first.dy);
    for (final p in maxPts.skip(1)) {
      band.lineTo(p.dx, p.dy);
    }
    for (final p in minPts.reversed) {
      band.lineTo(p.dx, p.dy);
    }
    band.close();
    canvas.drawPath(band, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x33e8833a), Color(0x336aa9d8)],
      ).createShader(Rect.fromLTRB(0, tempTop, size.width, tempBottom)));
    void line(List<Offset> pts, Color c) {
      for (var i = 1; i < pts.length; i++) {
        final forecast = days[i].forecast;
        canvas.drawLine(pts[i - 1], pts[i], Paint()
          ..color = c.withValues(alpha: forecast ? 0.55 : 1)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round);
      }
      for (var i = 0; i < pts.length; i++) {
        canvas.drawCircle(pts[i], i == sel ? 4 : 2.6, Paint()..color = c.withValues(alpha: days[i].forecast ? 0.6 : 1));
      }
    }

    line(maxPts, WeatherChartView.maxColor);
    line(minPts, WeatherChartView.minColor);
    // Числа температури — на обраному дні (і на крайніх, щоб було видно масштаб).
    for (final i in {if (sel >= 0) sel}) {
      _text(canvas, '${days[i].tmax.round()}°', maxPts[i] - const Offset(0, 4),
          size: 11, color: WeatherChartView.maxColor, weight: FontWeight.w700, above: true);
      _text(canvas, '${days[i].tmin.round()}°', minPts[i] + const Offset(0, 4),
          size: 11, color: WeatherChartView.minColor, weight: FontWeight.w700);
    }

    // Підписи днів.
    for (var i = 0; i < n; i++) {
      final d = days[i];
      final cx = i * colW + colW / 2;
      final strong = i == sel || d.today;
      _text(canvas, d.today ? 'сьог.' : d.label, Offset(cx, plotH + 4),
          size: 11, weight: strong ? FontWeight.w700 : FontWeight.w400,
          color: AppTheme.darkGreen.withValues(alpha: d.forecast || d.today ? 1 : 0.6));
      _text(canvas, d.dateLabel.split('.').first, Offset(cx, plotH + 17),
          size: 9, color: AppTheme.darkGreen.withValues(alpha: 0.5));
    }
  }

  @override
  bool shouldRepaint(_WeatherChartPainter old) => old.chart != chart || old.selected != selected;
}
