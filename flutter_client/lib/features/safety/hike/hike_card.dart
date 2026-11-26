import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/guardian.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/safety/guardian/guardian_session.dart';
import 'package:flutter_client/features/safety/guardian/guardian_start_sheet.dart';
import 'package:flutter_client/features/safety/hike/compass_screen.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_geo.dart';
import 'package:flutter_client/features/safety/safety_content.dart' show safetyContentProvider;
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_client/features/safety/safety_guides.dart' show checklistProvider;

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

  /// «Почати похід»: є Наглядачі, що погодились, — спершу «Йду в ліс» (час повернення,
  /// Наглядач, ADR-022 §22.3 п.2); інакше — похід лише на телефоні.
  Future<void> _start() async {
    GuardianOverview? g;
    try {
      g = await ref.read(guardianProvider.future).timeout(const Duration(seconds: 6));
    } catch (_) {
      g = null; // немає мережі — похід на телефоні, як і раніше
    }
    GuardianStartChoice? choice;
    if (g != null && g.acceptedGuardians.isNotEmpty && mounted) {
      choice = await showGuardianStartSheet(context, g, sunset: ref.read(hikeProvider).sunset);
      if (choice == null) return;
    }
    final ok = await ref.read(hikeProvider.notifier).start();
    if (!ok) {
      if (mounted) _snack('Потрібен дозвіл на геолокацію, щоб записувати шлях');
      return;
    }
    if (choice == null || choice.guardianIds.isEmpty) return;
    // Чек-лист перед походом пройдено повністю сьогодні — позначка для трофея «Готовий до лісу».
    final items = ref.read(safetyContentProvider).valueOrNull?.checklist ?? const [];
    final done = ref.read(checklistProvider).valueOrNull ?? const <String>{};
    final checklistDone = items.isNotEmpty && items.every((i) => done.contains(i.id));
    try {
      await ref.read(guardianSessionProvider.notifier).start(
            expectedReturn: choice.expectedReturn,
            guardianIds: choice.guardianIds,
            checklistDone: checklistDone,
          );
      if (mounted) _snack('Наглядач бачить ваш похід');
    } on ApiException catch (e) {
      if (mounted) _snack('Похід почато без Наглядача: ${e.userMessage}');
    }
  }

  Future<void> _guardianAction(GuardianButton a) async {
    if (a.id == 'finish') return _finish();
    try {
      final done = await ref.read(guardianSessionProvider.notifier).act(a.id);
      if (done != null && mounted) _snack(done);
    } on ApiException catch (e) {
      if (mounted) _snack(e.userMessage);
    }
  }

  /// «Додому», компас і «Я вдома» в один рядок; з великим шрифтом «Я вдома» — окремим рядком, щоб
  /// підпис «Додому» не обрізався (UI-001d).
  List<Widget> _hikeButtons(BuildContext context, HikeState hike, HikeController ctrl) {
    final home = FilledButton.icon(
      key: const ValueKey('hike-return'),
      onPressed: () {
        if (hike.returnMode == null) ctrl.goHome();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReturnScreen()));
      },
      style: FilledButton.styleFrom(backgroundColor: AppTheme.accentOrange, padding: const EdgeInsets.symmetric(vertical: 12)),
      icon: const Icon(Icons.home_rounded),
      label: const Text('Додому'),
    );
    final compass = IconButton.outlined(
      key: const ValueKey('hike-compass'),
      tooltip: 'Компас за маршрутом',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompassScreen())),
      icon: const Icon(Icons.explore_rounded),
    );
    final finish = OutlinedButton(
      key: const ValueKey('hike-finish'),
      onPressed: _finish,
      child: const Text('Я вдома'),
    );
    if (MediaQuery.textScalerOf(context).scale(10) <= 12) {
      return [
        Row(children: [Expanded(child: home), const SizedBox(width: 8), compass, const SizedBox(width: 8), finish]),
      ];
    }
    return [
      Row(children: [Expanded(child: home), const SizedBox(width: 8), compass]),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: finish),
    ];
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
    if (yes != true) return;
    // Поверталися за допомогою «Додому» — позначка для трофея «Своїм слідом».
    final usedHomeNav = ref.read(hikeProvider).returnMode != null;
    await ref.read(hikeProvider.notifier).finish();
    // Наглядач більше не бачить ні місця, ні треку (без мережі — повідомимо пізніше).
    await ref.read(guardianSessionProvider.notifier).finish(usedHomeNav: usedHomeNav);
  }

  @override
  Widget build(BuildContext context) {
    final hike = ref.watch(hikeProvider);
    final ctrl = ref.read(hikeProvider.notifier);
    final session = ref.watch(guardianSessionProvider);
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
                color: left <= const Duration(hours: 1) ? AppTheme.warning : dim,
                fontWeight: left <= const Duration(hours: 1) ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        if (hike.economy)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Батарея ${hike.battery ?? '≤ 20'} % — трек пишемо рідше, бережіть заряд',
                key: const ValueKey('hike-battery'), style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700)),
          ),
        if (hike.rejected > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Можливі збої GPS: пропущено точок — ${hike.rejected}',
                key: const ValueKey('hike-gps'), style: const TextStyle(color: AppTheme.warning, fontSize: 12.5)),
          ),
        if (session.active) _GuardianStatus(view: session.view, onAction: _guardianAction),
        const SizedBox(height: 10),
        ..._hikeButtons(context, hike, ctrl),
      ]);
    }

    if (!hike.active && session.pendingFinish != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Повідомимо Наглядача, що ви вдома, щойно з\'явиться інтернет',
            key: const ValueKey('hike-pending-finish'), style: TextStyle(color: dim, fontSize: 12.5)),
      ));
    }

    return Container(
      key: const ValueKey('hike-card'),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: hike.active ? Border.all(color: AppTheme.accentOrange, width: 1.5) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// Похід із Наглядачем: хто дивиться, до котрої повернення; у час повернення — «Все добре?»
/// з кнопками із сервера («Так, все добре», «Продовжити на годину», «Я вдома»).
class _GuardianStatus extends StatelessWidget {
  const _GuardianStatus({required this.view, required this.onAction});

  final OwnerHike? view;
  final ValueChanged<GuardianButton> onAction;

  @override
  Widget build(BuildContext context) {
    final v = view;
    const violet = Color(0xff6d28d9);
    if (v == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Наглядач: з\'єднуємося…', key: ValueKey('hike-guardian'), style: TextStyle(color: violet)),
      );
    }
    final who = v.guardians.map((g) => '@${g.handle}').join(', ');
    final ask = v.askOk || v.sos;
    final line = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        ask ? (v.detailLabel ?? v.statusLabel) : 'Наглядач $who · ${v.detailLabel ?? v.statusLabel}',
        key: const ValueKey('hike-guardian'),
        style: TextStyle(color: ask ? AppTheme.danger : violet, fontWeight: FontWeight.w600),
      ),
    );
    if (!ask) return line;
    return Container(
      key: const ValueKey('hike-ask-ok'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xfffdecea), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v.sos ? 'SOS надіслано' : 'Все добре?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.danger)),
          line,
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in v.actions)
                a.style == 'primary' || a.style == 'danger'
                    ? FilledButton(
                        key: ValueKey('hike-guardian-${a.id}'),
                        style: FilledButton.styleFrom(backgroundColor: a.style == 'danger' ? AppTheme.danger : AppTheme.darkGreen),
                        onPressed: () => onAction(a),
                        child: Text(a.label),
                      )
                    : OutlinedButton(key: ValueKey('hike-guardian-${a.id}'), onPressed: () => onAction(a), child: Text(a.label)),
            ],
          ),
        ],
      ),
    );
  }
}
