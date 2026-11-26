import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';

/// Контури областей: код → кільця [lon, lat] (assets/catalog/ukraine_oblasts.json, Natural Earth,
/// суспільне надбання; Крим і Севастополь — у складі України).
typedef Oblasts = Map<String, List<List<Offset>>>;

Oblasts parseOblasts(String json) {
  final j = jsonDecode(json) as Map<String, dynamic>;
  return {
    for (final e in (j['oblasts'] as Map<String, dynamic>).entries)
      e.key: [
        for (final ring in e.value as List)
          [for (final p in ring as List) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
      ],
  };
}

final oblastsProvider = FutureProvider<Oblasts>(
  (ref) async => parseOblasts(await rootBundle.loadString('assets/catalog/ukraine_oblasts.json')),
);

/// Карта України: області, де вид поширений, — зеленим.
class OblastMap extends ConsumerWidget {
  const OblastMap({super.key, required this.zones});

  final List<String> zones;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oblasts = ref.watch(oblastsProvider).valueOrNull;
    if (oblasts == null || zones.isEmpty) return const SizedBox.shrink();
    final known = zones.where(oblasts.containsKey).length;
    return Container(
      key: const ValueKey('oblast-map'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1.55,
            child: CustomPaint(painter: OblastMapPainter(oblasts: oblasts, zones: zones.toSet())),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xff4f9a5a), borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 4),
              Expanded(
                child: Text('Поширений: $known з ${oblasts.length} областей',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ),
              const SizedBox(width: 6),
              Text('Межі: Natural Earth', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class OblastMapPainter extends CustomPainter {
  OblastMapPainter({required this.oblasts, required this.zones});

  final Oblasts oblasts;
  final Set<String> zones;

  /// Рівнопроміжна проєкція з поправкою на широту України (~48.5°).
  static final _k = math.cos(48.5 * math.pi / 180);

  @override
  void paint(Canvas canvas, Size size) {
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final rings in oblasts.values) {
      for (final ring in rings) {
        for (final p in ring) {
          minX = math.min(minX, p.dx * _k);
          maxX = math.max(maxX, p.dx * _k);
          minY = math.min(minY, -p.dy);
          maxY = math.max(maxY, -p.dy);
        }
      }
    }
    final scale = math.min(size.width / (maxX - minX), size.height / (maxY - minY));
    final ox = (size.width - (maxX - minX) * scale) / 2, oy = (size.height - (maxY - minY) * scale) / 2;
    Offset proj(Offset p) => Offset(ox + (p.dx * _k - minX) * scale, oy + (-p.dy - minY) * scale);

    final on = Paint()..color = const Color(0xff4f9a5a);
    final off = Paint()..color = const Color(0xffe9e4d6);
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round;
    for (final e in oblasts.entries) {
      for (final ring in e.value) {
        final path = Path()..addPolygon([for (final p in ring) proj(p)], true);
        canvas.drawPath(path, zones.contains(e.key) ? on : off);
        canvas.drawPath(path, border);
      }
    }
  }

  @override
  bool shouldRepaint(covariant OblastMapPainter old) => old.zones != zones || old.oblasts != oblasts;
}
