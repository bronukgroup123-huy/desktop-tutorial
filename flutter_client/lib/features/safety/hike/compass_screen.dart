import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_device.dart';
import 'package:flutter_client/features/safety/hike/hike_geo.dart';

/// Ціль ближче — «Ви на місці».
const kArrivedM = 25.0;

/// Курс телефона зі справжньою північчю (магнітний + схилення для України), плавний.
/// `null` — компаса немає / телефон «на ребрі».
final headingProvider = StreamProvider.autoDispose<double?>((ref) {
  final device = ref.watch(hikeDeviceProvider);
  double? smooth;
  return device.heading().map((raw) {
    if (raw == null) return smooth;
    final lng = ref.read(hikeProvider).here?.lng ?? 30.5;
    final trueHeading = (raw + declinationUa(lng)) % 360;
    smooth = smooth == null ? trueHeading : smoothAngle(smooth!, trueHeading, 0.2);
    return smooth;
  });
});

/// Голосові підказки (ADR-022 §22.3 п.3): старт, кожні 250 м, «поверніть», «на місці»;
/// не частіше ніж раз на 12 с для поворотів.
class VoicePrompter {
  VoicePrompter({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  int? _bucket;
  DateTime? _lastTurn;
  DateTime? _offSince;
  bool _arrived = false;

  String? next({required double remainingM, required double? relative}) {
    if (remainingM <= kArrivedM) {
      if (_arrived) return null;
      _arrived = true;
      return 'Ви на місці';
    }
    _arrived = false;
    final bucket = (remainingM / 250).ceil();
    if (_bucket == null) {
      _bucket = bucket;
      return 'Ідіть за стрілкою. Залишилось ${_spoken(remainingM)}';
    }
    if (bucket < _bucket!) {
      _bucket = bucket;
      return 'Залишилось ${_spoken(remainingM)}';
    }
    if (relative != null && relative.abs() > 60) {
      final t = _now();
      _offSince ??= t;
      final steady = t.difference(_offSince!) >= const Duration(seconds: 4);
      final rested = _lastTurn == null || t.difference(_lastTurn!) >= const Duration(seconds: 12);
      if (steady && rested) {
        _lastTurn = t;
        _offSince = null;
        return relative > 0 ? 'Поверніть праворуч' : 'Поверніть ліворуч';
      }
    } else {
      _offSince = null;
    }
    return null;
  }

  static String _spoken(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} кілометра' : '${(m / 10).round() * 10} метрів';
}

/// Повернення (ADR-022 §22.3 п.4): «За маршрутом» — назад по треку; «Новий маршрут» —
/// компас назад: прямо до машини чи точки маршруту. Без інтернету.
class ReturnScreen extends ConsumerStatefulWidget {
  const ReturnScreen({super.key});

  @override
  ConsumerState<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends ConsumerState<ReturnScreen> {
  bool _voice = false;
  final _prompter = VoicePrompter();

  @override
  Widget build(BuildContext context) {
    final hike = ref.watch(hikeProvider);
    final ctrl = ref.read(hikeProvider.notifier);
    final heading = ref.watch(headingProvider).valueOrNull;
    final mode = hike.returnMode ?? (hike.outbound.length >= 2 ? ReturnMode.track : ReturnMode.direct);
    final here = hike.here == null ? null : geoOf(hike.here!);
    final start = hike.route.isEmpty ? null : (lat: hike.route.first.lat, lng: hike.route.first.lng);

    Geo? target;
    double? remaining;
    String targetLabel = '';
    final outbound = hike.outbound;
    if (here != null && hike.route.isNotEmpty) {
      if (mode == ReturnMode.track && outbound.length >= 2) {
        final toStart = distanceM(here, start!);
        if (toStart <= kArrivedM * 2) {
          // Біля старту — прямо до нього.
          target = start;
          remaining = toStart;
        } else {
          final b = backtrackTarget(outbound, here);
          target = b.target;
          remaining = b.remainingM;
        }
        targetLabel = 'до старту по своєму треку';
      } else {
        final p = hike.route[hike.target.clamp(0, hike.route.length - 1)];
        target = (lat: p.lat, lng: p.lng);
        remaining = distanceM(here, target);
        targetLabel = 'до «${p.label}» навпростець';
      }
    }
    final bearing = here != null && target != null ? bearingDeg(here, target) : null;
    final relative = bearing != null && heading != null ? relativeDeg(bearing, heading) : null;
    final arrived = remaining != null && remaining <= kArrivedM;

    if (_voice && remaining != null) {
      final say = _prompter.next(remainingM: remaining, relative: relative);
      if (say != null) ref.read(hikeDeviceProvider).speak(say);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Повернутися', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)),
        actions: [
          IconButton(
            key: const ValueKey('voice-toggle'),
            tooltip: _voice ? 'Вимкнути голос' : 'Голосові підказки',
            icon: Icon(_voice ? Icons.record_voice_over_rounded : Icons.voice_over_off_rounded),
            onPressed: () => setState(() => _voice = !_voice),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('return-screen'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SegmentedButton<ReturnMode>(
            key: const ValueKey('return-mode'),
            segments: [
              ButtonSegment(
                value: ReturnMode.track,
                label: const Text('За маршрутом'),
                icon: const Icon(Icons.timeline_rounded),
                enabled: hike.outbound.length >= 2,
              ),
              const ButtonSegment(value: ReturnMode.direct, label: Text('Новий маршрут'), icon: Icon(Icons.explore_rounded)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ctrl.startReturn(s.first, target: hike.target),
          ),
          if (mode == ReturnMode.direct && hike.route.length > 1) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, p) in hike.route.indexed)
                  ChoiceChip(
                    key: ValueKey('target-$i'),
                    label: Text(p.label),
                    selected: hike.target == i,
                    onSelected: (_) => ctrl.startReturn(ReturnMode.direct, target: i),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Center(child: CompassDial(heading: heading, relative: relative, arrived: arrived)),
          const SizedBox(height: 14),
          if (here == null)
            const Text('Шукаємо GPS… Вийдіть на відкрите місце.',
                key: ValueKey('return-no-fix'), textAlign: TextAlign.center, style: TextStyle(color: AppTheme.darkGreen))
          else if (arrived)
            const Text('Ви на місці!',
                key: ValueKey('return-arrived'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xff2e7d32)))
          else ...[
            Text(distanceLabel(remaining!),
                key: const ValueKey('return-distance'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: AppTheme.darkGreen)),
            Text(targetLabel, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.75))),
            if (heading == null && bearing != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Компас недоступний — тримайте телефон рівно. Напрямок: ${cardinal(bearing)} (${bearing.round()}°)',
                  key: const ValueKey('return-no-compass'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xffb45309)),
                ),
              ),
          ],
          if (hike.rejected > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Пропущено точок: ${hike.rejected} — можливі збої GPS. Стрілка може відхилятися, звіряйтеся з місцевістю.',
                key: const ValueKey('return-gps-warning'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xffb45309), fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('return-home'),
            onPressed: () {
              ctrl.finish();
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.home_rounded),
            label: const Text('Я вдома — завершити похід'),
          ),
        ],
      ),
    );
  }
}

/// Компас без цілі (ADR-022 §22.3 п.3): курс і сторона світу, працює без GPS та інтернету.
class CompassScreen extends ConsumerWidget {
  const CompassScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heading = ref.watch(headingProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('Компас', style: GoogleFonts.merriweather(color: AppTheme.darkGreen))),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CompassDial(heading: heading),
            const SizedBox(height: 16),
            Text(
              heading == null ? 'Компас недоступний на цьому телефоні' : '${cardinal(heading)} · ${heading.round()}°',
              key: const ValueKey('compass-heading'),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.darkGreen),
            ),
            const SizedBox(height: 6),
            Text('Тримайте телефон рівно, подалі від металу й машини',
                style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

/// Циферблат: шкала обертається за курсом (північ — червона), стрілка — на ціль.
class CompassDial extends StatelessWidget {
  const CompassDial({super.key, required this.heading, this.relative, this.arrived = false, this.size = 260});

  final double? heading;

  /// Кут на ціль відносно телефона; `null` — без стрілки.
  final double? relative;
  final bool arrived;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('compass-dial'),
        width: size,
        height: size,
        child: CustomPaint(painter: _DialPainter(heading: heading, relative: relative, arrived: arrived)),
      );
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.heading, required this.relative, required this.arrived});

  final double? heading;
  final double? relative;
  final bool arrived;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(c, r, Paint()
      ..color = AppTheme.darkGreen.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    // Шкала: обертаємо так, щоб північ була там, де вона насправді.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-(heading ?? 0) * math.pi / 180);
    for (var d = 0; d < 360; d += 15) {
      final big = d % 90 == 0;
      final a = d * math.pi / 180;
      final p1 = Offset(math.sin(a), -math.cos(a)) * (r - 6);
      final p2 = Offset(math.sin(a), -math.cos(a)) * (r - (big ? 22 : 14));
      canvas.drawLine(p1, p2, Paint()
        ..color = AppTheme.darkGreen.withValues(alpha: big ? 0.8 : 0.35)
        ..strokeWidth = big ? 3 : 1.5);
    }
    for (final (d, t) in const [(0, 'Пн'), (90, 'Сх'), (180, 'Пд'), (270, 'Зх')]) {
      final a = d * math.pi / 180;
      final pos = Offset(math.sin(a), -math.cos(a)) * (r - 40);
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: d == 0 ? const Color(0xffc62828) : AppTheme.darkGreen),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate((heading ?? 0) * math.pi / 180); // підписи — рівно
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    canvas.restore();

    // Стрілка на ціль (або «на місці»).
    if (arrived) {
      canvas.drawCircle(c, r * 0.32, Paint()..color = const Color(0xff2e7d32));
      final check = Path()
        ..moveTo(c.dx - r * 0.14, c.dy)
        ..lineTo(c.dx - r * 0.03, c.dy + r * 0.11)
        ..lineTo(c.dx + r * 0.16, c.dy - r * 0.11);
      canvas.drawPath(check, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round);
      return;
    }
    final rel = relative;
    if (rel == null) {
      canvas.drawCircle(c, 6, Paint()..color = AppTheme.darkGreen);
      return;
    }
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rel * math.pi / 180);
    final arrow = Path()
      ..moveTo(0, -r * 0.62)
      ..lineTo(r * 0.2, r * 0.12)
      ..lineTo(0, r * 0.02)
      ..lineTo(-r * 0.2, r * 0.12)
      ..close();
    canvas.drawShadow(arrow, Colors.black, 4, false);
    canvas.drawPath(arrow, Paint()..color = const Color(0xffd97706));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) => old.heading != heading || old.relative != relative || old.arrived != arrived;
}
