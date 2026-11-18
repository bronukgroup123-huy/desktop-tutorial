import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_device.dart';
import 'package:flutter_client/features/safety/hike/hike_geo.dart';
import 'package:flutter_client/features/safety/hike/hike_nav.dart';

export 'package:flutter_client/features/safety/hike/hike_nav.dart' show kArrivedM;

/// Курс телефона зі справжньою північчю (магнітний + схилення для України), згладжений.
/// Остаточну плавність дає анімація циферблата ([CompassDial]). `null` — компаса немає / телефон «на ребрі».
final headingProvider = StreamProvider.autoDispose<double?>((ref) {
  final device = ref.watch(hikeDeviceProvider);
  double? smooth;
  return device.heading().map((raw) {
    if (raw == null) return smooth;
    final lng = ref.read(hikeProvider).here?.lng ?? 30.5;
    final trueHeading = (raw + declinationUa(lng)) % 360;
    if (smooth == null) {
      smooth = trueHeading;
    } else {
      // Дрібне тремтіння (< 1,5°) — ігноруємо; великі повороти — швидше.
      final d = relativeDeg(trueHeading, smooth!).abs();
      if (d >= 1.5) smooth = smoothAngle(smooth!, trueHeading, d > 30 ? 0.5 : 0.25);
    }
    return smooth;
  });
});

/// Куди йти: шлях, назва цілі й підпис під відстанню.
typedef NavTarget = ({NavPlan plan, String label, String key});

/// Шлях для компаса з поточного походу (ADR-022 §22.7):
/// - повернення «Своїм слідом» — назад власним треком до старту;
/// - «Навпростець» — прямо до вибраної точки маршруту;
/// - похід триває, повернення не почато — вперед за створеним маршрутом.
final navTargetProvider = Provider.autoDispose<NavTarget?>((ref) {
  final hike = ref.watch(hikeProvider);
  if (!hike.active || hike.route.isEmpty) return null;
  final here = hike.here == null ? null : geoOf(hike.here!);
  final start = (lat: hike.route.first.lat, lng: hike.route.first.lng);
  final mode = hike.returnMode;
  if (mode == ReturnMode.track && hike.outbound.length >= 2) {
    final pts = [for (final p in hike.outbound.reversed) geoOf(p)];
    if (distanceM(pts.last, start) > 10) pts.add(start);
    return (
      plan: NavPlan(pts, kinds: const ['own'], destination: hike.route.first.label),
      label: 'до «${hike.route.first.label}» своїм слідом',
      key: 'own',
    );
  }
  if (mode != null) {
    final p = hike.route[hike.target.clamp(0, hike.route.length - 1)];
    if (here == null) return null;
    final to = (lat: p.lat, lng: p.lng);
    // Стоїмо на самій точці — шлях у 2 м, щоб показати «Ви на місці».
    final from = distanceM(here, to) < 1 ? (lat: to.lat + 0.00002, lng: to.lng) : here;
    return (plan: NavPlan([from, to], kinds: const ['direct'], destination: p.label), label: 'до «${p.label}» навпростець', key: 'direct-${hike.target}');
  }
  if (hike.route.length >= 2) {
    return (
      plan: NavPlan([for (final p in hike.route) (lat: p.lat, lng: p.lng)], kinds: const ['route'], destination: hike.route.last.label, toleranceM: 0),
      label: 'до «${hike.route.last.label}» за маршрутом',
      key: 'route',
    );
  }
  return null;
});

/// Повернення додому (ADR-022 §22.3 п.4, §22.7): «Своїм слідом» — назад тим самим шляхом;
/// «Навпростець» — компасом прямо до машини чи точки маршруту. Покрокові підказки, без інтернету.
class ReturnScreen extends ConsumerWidget {
  const ReturnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hike = ref.watch(hikeProvider);
    final ctrl = ref.read(hikeProvider.notifier);
    final mode = hike.returnMode ?? (hike.outbound.length >= 2 ? ReturnMode.track : ReturnMode.direct);
    return Scaffold(
      appBar: AppBar(title: Text('Додому', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)), actions: const [VoiceToggle()]),
      body: ListView(
        key: const ValueKey('return-screen'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SegmentedButton<ReturnMode>(
            key: const ValueKey('return-mode'),
            segments: [
              ButtonSegment(
                value: ReturnMode.track,
                label: const Text('Своїм слідом'),
                icon: const Icon(Icons.timeline_rounded),
                enabled: hike.outbound.length >= 2,
              ),
              const ButtonSegment(value: ReturnMode.direct, label: Text('Навпростець'), icon: Icon(Icons.explore_rounded)),
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
          if (mode == ReturnMode.direct)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Навпростець — по прямій: дивіться під ноги, обходьте воду й болота. Надійніше — своїм слідом.',
                key: ValueKey('direct-warning'),
                style: TextStyle(fontSize: 12.5, color: Color(0xffb45309)),
              ),
            ),
          const SizedBox(height: 12),
          const NavigationPanel(),
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

/// Голос увімкнено (на екрані компаса й «Додому» — один перемикач).
final navVoiceOnProvider = StateProvider<bool>((ref) => false);

class VoiceToggle extends ConsumerWidget {
  const VoiceToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(navVoiceOnProvider);
    return IconButton(
      key: const ValueKey('voice-toggle'),
      tooltip: on ? 'Вимкнути голос' : 'Голосові підказки',
      icon: Icon(on ? Icons.record_voice_over_rounded : Icons.voice_over_off_rounded),
      onPressed: () => ref.read(navVoiceOnProvider.notifier).state = !on,
    );
  }
}

/// Підказка, циферблат, залишок і голос — з одного [Guidance], тож усе синхронно.
class NavigationPanel extends ConsumerStatefulWidget {
  const NavigationPanel({super.key});

  @override
  ConsumerState<NavigationPanel> createState() => _NavigationPanelState();
}

class _NavigationPanelState extends ConsumerState<NavigationPanel> {
  String? _key;
  double? _along;
  NavVoice _voice = NavVoice();

  @override
  Widget build(BuildContext context) {
    final hike = ref.watch(hikeProvider);
    final target = ref.watch(navTargetProvider);
    final heading = ref.watch(headingProvider).valueOrNull;
    final here = hike.here == null ? null : geoOf(hike.here!);
    if (target?.key != _key) {
      // Інша ціль — підказки з початку.
      _key = target?.key;
      _along = null;
      _voice = NavVoice();
    }
    final g = target == null || here == null ? null : guide(target.plan, here, fromAlong: _along);
    if (g != null) _along = g.along;
    final relative = g != null && heading != null ? relativeDeg(g.aimBearing, heading) : null;
    if (g != null && ref.watch(navVoiceOnProvider)) {
      final say = _voice.next(g, relative: relative);
      if (say != null) ref.read(hikeDeviceProvider).speak(say);
    }
    final cue = relative == null ? null : cueOf(relative);
    final good = cue == Cue.onTrack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (g != null && !g.arrived) _InstructionCard(g: g),
        const SizedBox(height: 14),
        Center(
          child: CompassDial(
            heading: heading,
            aimBearing: g?.arrived == true ? null : g?.aimBearing,
            legBearing: g == null || g.arrived || g.offRoute ? null : g.leg.bearing,
            nextBearing: g == null || g.arrived || g.offRoute ? null : g.next?.bearing,
            arrived: g?.arrived ?? false,
          ),
        ),
        const SizedBox(height: 10),
        if (target == null)
          const Text('Немає цілі: створіть маршрут і почніть похід.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.darkGreen))
        else if (here == null)
          const Text('Шукаємо GPS… Вийдіть на відкрите місце.',
              key: ValueKey('return-no-fix'), textAlign: TextAlign.center, style: TextStyle(color: AppTheme.darkGreen))
        else if (g!.arrived)
          const Text('Ви на місці!',
              key: ValueKey('return-arrived'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xff2e7d32)))
        else ...[
          if (cue != null)
            Text(
              cueText(cue),
              key: const ValueKey('nav-cue'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: good ? const Color(0xff2e7d32) : const Color(0xffd97706)),
            ),
          const SizedBox(height: 4),
          Text(distanceLabel(g.remainingM),
              key: const ValueKey('return-distance'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppTheme.darkGreen)),
          Text(target.label, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.75))),
          if (heading == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Компас недоступний — тримайте телефон рівно. Напрямок: на ${directionWord(g.aimBearing)} (${g.aimBearing.round()}°)',
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
      ],
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.g});

  final Guidance g;

  @override
  Widget build(BuildContext context) {
    final off = g.offRoute;
    final color = off ? const Color(0xffb45309) : AppTheme.darkGreen;
    final title = off ? 'Ви зійшли з маршруту на ${distanceLabel(g.offRouteM)}' : legInstruction(g.leg);
    final sub = off
        ? 'Поверніться на ${directionWord(g.aimBearing)} — стрілка веде до маршруту'
        : '${distanceLabel(g.toTurnM)} ${g.lastLeg ? 'до мети' : 'до повороту'}';
    return Container(
      key: ValueKey(off ? 'nav-off-route' : 'nav-instruction'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: off ? const Color(0xfffff3e0) : AppTheme.darkGreen.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(off ? Icons.wrong_location_rounded : Icons.navigation_rounded, size: 40, color: off ? color : const Color(0xffd97706)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: color)),
                Text(sub, key: const ValueKey('nav-to-turn'), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: color)),
                if (!off && g.next != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(nextInstruction(g),
                        key: const ValueKey('nav-next'), style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.75))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Компас (ADR-022 §22.3 п.3): курс і сторона світу без GPS та інтернету. Під час походу —
/// той самий компас веде маршрутом: стрілка, підказки, голос, кнопка «Додому».
class CompassScreen extends ConsumerWidget {
  const CompassScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heading = ref.watch(headingProvider).valueOrNull;
    final hike = ref.watch(hikeProvider);
    final target = ref.watch(navTargetProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Компас', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)),
        actions: [if (target != null) const VoiceToggle()],
      ),
      body: target == null
          ? Center(
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
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (heading != null)
                  Text('${cardinal(heading)} · ${heading.round()}°',
                      key: const ValueKey('compass-heading'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen.withValues(alpha: 0.7))),
                const NavigationPanel(),
                if (hike.returnMode == null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const ValueKey('compass-home'),
                    onPressed: () {
                      ref.read(hikeProvider.notifier).startReturn(hike.track.length >= 2 ? ReturnMode.track : ReturnMode.direct);
                      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ReturnScreen()));
                    },
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xffd97706), padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('Додому'),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Циферблат: шкала плавно обертається за курсом (північ — червона); помаранчева стрілка —
/// куди йти зараз; мітка на краю — напрямок відрізка, сіра — напрямок після повороту.
/// Стрілка зеленіє, коли телефон дивиться туди, куди треба.
class CompassDial extends StatefulWidget {
  const CompassDial({
    super.key,
    required this.heading,
    this.aimBearing,
    this.legBearing,
    this.nextBearing,
    this.arrived = false,
    this.size = 260,
  });

  final double? heading;

  /// Куди показує стрілка (азимут від справжньої півночі); `null` — без стрілки.
  final double? aimBearing;
  final double? legBearing;
  final double? nextBearing;
  final bool arrived;
  final double size;

  @override
  State<CompassDial> createState() => _CompassDialState();
}

class _CompassDialState extends State<CompassDial> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  double? _shown;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _shown = widget.heading;
  }

  @override
  void didUpdateWidget(CompassDial old) {
    super.didUpdateWidget(old);
    final h = widget.heading;
    if (h == null) return;
    if (_shown == null) {
      _shown = h;
    } else if (relativeDeg(h, _shown!).abs() > 0.2 && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  /// Плавно доганяємо курс (≈ 150 мс), найкоротшим шляхом через 0°.
  void _tick(Duration t) {
    final h = widget.heading;
    if (h == null || _shown == null) {
      _ticker.stop();
      return;
    }
    final dt = _last == Duration.zero ? 1 / 60 : (t - _last).inMicroseconds / 1e6;
    _last = t;
    final d = relativeDeg(h, _shown!);
    if (d.abs() <= 0.2) {
      _ticker.stop();
      setState(() => _shown = h);
      return;
    }
    final k = 1 - math.exp(-dt / 0.15);
    setState(() => _shown = (_shown! + d * k + 360) % 360);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _shown ?? widget.heading;
    final rel = widget.aimBearing == null ? null : relativeDeg(widget.aimBearing!, h ?? 0);
    return SizedBox(
      key: const ValueKey('compass-dial'),
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _DialPainter(
          heading: h,
          relative: rel,
          legBearing: widget.legBearing,
          nextBearing: widget.nextBearing,
          arrived: widget.arrived,
          onTrack: rel != null && h != null && rel.abs() < 15,
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.heading,
    required this.relative,
    required this.legBearing,
    required this.nextBearing,
    required this.arrived,
    required this.onTrack,
  });

  final double? heading;
  final double? relative;
  final double? legBearing;
  final double? nextBearing;
  final bool arrived;
  final bool onTrack;

  static const _orange = Color(0xffd97706);
  static const _green = Color(0xff2e7d32);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(c, r, Paint()
      ..color = (onTrack ? _green : AppTheme.darkGreen).withValues(alpha: onTrack ? 0.8 : 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = onTrack ? 5 : 2);
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
    // Мітки маршруту на краю шкали: куди йде відрізок і куди — після повороту.
    void marker(double bearing, Color color, double w) {
      final a = bearing * math.pi / 180;
      final dir = Offset(math.sin(a), -math.cos(a));
      final side = Offset(math.cos(a), math.sin(a));
      final tip = dir * (r - 26);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo((dir * (r - 2) + side * w).dx, (dir * (r - 2) + side * w).dy)
        ..lineTo((dir * (r - 2) - side * w).dx, (dir * (r - 2) - side * w).dy)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    if (nextBearing != null) marker(nextBearing!, AppTheme.darkGreen.withValues(alpha: 0.35), 9);
    if (legBearing != null) marker(legBearing!, onTrack ? _green : _orange, 13);
    for (final (d, t) in const [(0, 'Пн'), (90, 'Сх'), (180, 'Пд'), (270, 'Зх')]) {
      final a = d * math.pi / 180;
      final pos = Offset(math.sin(a), -math.cos(a)) * (r - 44);
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

    // Позначка «верх телефона» — куди ви дивитесь.
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r - 2)
        ..lineTo(c.dx - 8, c.dy - r - 14)
        ..lineTo(c.dx + 8, c.dy - r - 14)
        ..close(),
      Paint()..color = AppTheme.darkGreen,
    );

    if (arrived) {
      canvas.drawCircle(c, r * 0.32, Paint()..color = _green);
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
    canvas.drawPath(arrow, Paint()..color = onTrack ? _green : _orange);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.heading != heading ||
      old.relative != relative ||
      old.legBearing != legBearing ||
      old.nextBearing != nextBearing ||
      old.arrived != arrived ||
      old.onTrack != onTrack;
}
