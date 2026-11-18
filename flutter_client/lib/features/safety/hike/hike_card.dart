import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/safety/hike/compass_screen.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_geo.dart';
import 'package:flutter_client/features/safety/safety_device.dart';

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _dur(Duration d) => d.inHours > 0 ? '${d.inHours} год ${d.inMinutes % 60} хв' : '${d.inMinutes} хв';

/// «Похід» на вкладці «Безпека» (ADR-022 §22.3 п.4, 11, 13): маршрут → почати → повернутися.
/// Без маршруту похід не почати (§22.5 п.4). Усе на телефоні — гостю теж.
class HikeCard extends ConsumerStatefulWidget {
  const HikeCard({super.key});

  @override
  ConsumerState<HikeCard> createState() => _HikeCardState();
}

class _HikeCardState extends ConsumerState<HikeCard> {
  bool _locating = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Час походу й «до заходу» — щохвилини.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(hikeProvider).active) ref.read(hikeProvider.notifier).refreshBattery();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _startHere() async {
    setState(() => _locating = true);
    final r = await ref.read(safetyDeviceProvider).locate();
    if (!mounted) return;
    setState(() => _locating = false);
    final f = r.fix;
    if (f == null) {
      _snack(r.error == LocateError.denied ? 'Дозвольте доступ до геолокації' : 'Не вдалося визначити місце — вийдіть на відкрите місце');
      return;
    }
    ref.read(hikeProvider.notifier).addPoint(f.lat, f.lng, label: ref.read(hikeProvider).route.isEmpty ? 'Старт' : null);
  }

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _start() async {
    final ok = await ref.read(hikeProvider.notifier).start();
    if (!ok && mounted) _snack('Потрібен дозвіл на геолокацію, щоб записувати шлях');
  }

  Future<void> _finish() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Завершити похід?'),
        content: const Text('Запис шляху зупиниться, трек і маршрут зітруться з телефона.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ні')),
          TextButton(key: const ValueKey('hike-finish-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Я вдома')),
        ],
      ),
    );
    if (yes == true) await ref.read(hikeProvider.notifier).finish();
  }

  @override
  Widget build(BuildContext context) {
    final hike = ref.watch(hikeProvider);
    final ctrl = ref.read(hikeProvider.notifier);
    final dim = AppTheme.darkGreen.withValues(alpha: 0.75);
    final sunset = hike.sunset;
    final now = HikeController.now();
    final children = <Widget>[
      Row(
        children: [
          Icon(hike.active ? Icons.hiking_rounded : Icons.route_rounded, color: AppTheme.darkGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(hike.active ? 'Похід триває' : 'Похід',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.darkGreen)),
          ),
          if (!hike.active && hike.hasRoute)
            IconButton(
              key: const ValueKey('route-clear'),
              tooltip: 'Очистити маршрут',
              onPressed: ctrl.clearRoute,
              icon: Icon(Icons.delete_outline_rounded, color: dim),
            ),
        ],
      ),
    ];

    if (!hike.hasRoute) {
      children.addAll([
        Text('Спершу маршрут: точка старту — де лишаєте машину чи входите в ліс. Без маршруту похід не почати.',
            style: TextStyle(color: dim)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('route-start-here'),
              onPressed: _locating ? null : _startHere,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen),
              icon: _locating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('Старт тут'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('route-on-map'),
              onPressed: () {
                ref.read(routeEditProvider.notifier).state = true;
                context.go('/map');
              },
              icon: const Icon(Icons.map_rounded, size: 18),
              label: const Text('На карті'),
            ),
          ],
        ),
      ]);
    } else if (!hike.active) {
      children.addAll([
        Text(hike.route.map((p) => p.label).join(' → '), key: const ValueKey('route-summary'), style: TextStyle(color: dim)),
        if (sunset != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Захід сонця о ${_hm(sunset)}', style: TextStyle(color: dim, fontSize: 13)),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('hike-start'),
              onPressed: _start,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Почати похід'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('route-add-here'),
              onPressed: _locating ? null : _startHere,
              icon: const Icon(Icons.add_location_alt_rounded, size: 18),
              label: const Text('Точка тут'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                ref.read(routeEditProvider.notifier).state = true;
                context.go('/map');
              },
              icon: const Icon(Icons.map_rounded, size: 18),
              label: const Text('На карті'),
            ),
          ],
        ),
      ]);
    } else {
      final elapsed = hike.startedAt == null ? Duration.zero : now.difference(hike.startedAt!);
      final left = sunset?.difference(now);
      children.addAll([
        Text('${_dur(elapsed)} · пройдено ${distanceLabel(hike.walkedM)}',
            key: const ValueKey('hike-stats'), style: const TextStyle(color: AppTheme.darkGreen, fontWeight: FontWeight.w600)),
        if (sunset != null && left != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              left.isNegative ? 'Сонце зайшло о ${_hm(sunset)} — повертайтеся' : 'Захід о ${_hm(sunset)} — через ${_dur(left)}',
              key: const ValueKey('hike-sunset'),
              style: TextStyle(
                color: left <= const Duration(hours: 1) ? const Color(0xffb45309) : dim,
                fontWeight: left <= const Duration(hours: 1) ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        if (hike.economy)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Батарея ${hike.battery ?? '≤ 20'} % — трек пишемо рідше, бережіть заряд',
                key: const ValueKey('hike-battery'), style: const TextStyle(color: Color(0xffb45309), fontWeight: FontWeight.w700)),
          ),
        if (hike.rejected > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Можливі збої GPS: пропущено точок — ${hike.rejected}',
                key: const ValueKey('hike-gps'), style: const TextStyle(color: Color(0xffb45309), fontSize: 12.5)),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('hike-return'),
                onPressed: () {
                  if (hike.returnMode == null) {
                    ctrl.startReturn(hike.track.length >= 2 ? ReturnMode.track : ReturnMode.direct);
                  }
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReturnScreen()));
                },
                style: FilledButton.styleFrom(backgroundColor: const Color(0xffd97706), padding: const EdgeInsets.symmetric(vertical: 12)),
                icon: const Icon(Icons.home_rounded),
                label: const Text('Додому'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              key: const ValueKey('hike-compass'),
              tooltip: 'Компас за маршрутом',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompassScreen())),
              icon: const Icon(Icons.explore_rounded),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('hike-finish'),
              onPressed: _finish,
              child: const Text('Я вдома'),
            ),
          ],
        ),
      ]);
    }

    return Container(
      key: const ValueKey('hike-card'),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: hike.active ? Border.all(color: const Color(0xffd97706), width: 1.5) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
