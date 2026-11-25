import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/analysis_result_view.dart';
import 'package:flutter_client/features/analysis/area_mini_map.dart';
import 'package:flutter_client/features/analysis/analysis_square.dart';
import 'package:flutter_client/features/analysis/forest_area.dart';
import 'package:flutter_client/features/analysis/forest_refine_sheet.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart' show ForecastInfoCard;
import 'package:flutter_client/core/push.dart';
import 'package:flutter_client/features/forecast/home_widget_sync.dart';
import 'package:flutter_client/features/forecast/share_forecast.dart';

/// Вкладка «Прогноз» — робота з ділянками аналізу (ADR-015 §15.4).
///
/// Ділянку створюють на карті; тут — її результат, повторний аналіз, показ на
/// карті й видалення. Змінити (пересунути) ділянку не можна: щоб обрати інше
/// місце, стару видаляють і створюють нову (у Pro можна мати кілька).
class ForecastScreen extends ConsumerWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(analysisOverviewProvider);
    final data = overview.valueOrNull;
    final selectedId = ref.watch(selectedAreaIdProvider);
    final area = data?.areaById(selectedId) ?? (data == null || data.areas.isEmpty ? null : data.areas.first);

    return Scaffold(
      appBar: AppBar(
        title: Text('Прогноз', style: GoogleFonts.merriweather(color: AppTheme.darkGreen, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // «Поділитися прогнозом» — картинка для Viber / Telegram (рішення PO 2026-11-15).
          if (area?.lastResult != null)
            IconButton(
              key: const ValueKey('share-forecast'),
              tooltip: 'Поділитися прогнозом',
              icon: const Icon(Icons.ios_share_rounded, color: AppTheme.darkGreen),
              onPressed: () => showShareForecast(context, areaTitle: area!.title, result: area.lastResult!),
            ),
        ],
      ),
      body: data == null
          ? (overview.hasError
              ? _Message(
                  icon: Icons.cloud_off_rounded,
                  title: 'Не вдалося завантажити ділянки',
                  text: overview.error is ApiException
                      ? (overview.error as ApiException).userMessage
                      : 'Спробуйте ще раз.',
                  action: FilledButton(
                    onPressed: () => ref.invalidate(analysisOverviewProvider),
                    child: const Text('Повторити'),
                  ),
                )
              : const Center(child: CircularProgressIndicator()))
          : data.areas.isEmpty
              ? _Message(
                  icon: Icons.crop_free_rounded,
                  title: 'Оберіть ділянку на карті',
                  text: 'На карті натисніть «Аналіз ділянки», торкніться місця в лісі та запустіть аналіз — '
                      'тут з\'явиться прогноз для ділянки: ліси, погода, які гриби ростуть і чому.',
                  action: FilledButton.icon(
                    onPressed: () => context.go('/map'),
                    icon: const Icon(Icons.map_rounded),
                    label: const Text('Відкрити карту'),
                  ),
                )
              : _AreaPage(overview: data, area: area!),
    );
  }
}

class _AreaPage extends ConsumerStatefulWidget {
  const _AreaPage({required this.overview, required this.area});

  final AnalysisOverview overview;
  final AnalysisArea area;

  @override
  ConsumerState<_AreaPage> createState() => _AreaPageState();
}

class _AreaPageState extends ConsumerState<_AreaPage> {
  bool _busy = false;

  /// ▶ «Хвиля по днях» у верхньому рядку значків (ADR-015 §15.9).
  final _play = WeekPlayController();

  /// Щоденне безкоштовне оновлення: для яких ділянок уже пробували в цій сесії.
  final Set<String> _autoTried = {};
  bool _autoRefreshing = false;
  bool _autoFailed = false;
  bool _weatherOnly = false;

  /// Картку «Сповіщати про хвилі» закрито або вже ввімкнено (на телефоні, LocalStore).
  bool _pushHidden = true;

  @override
  void initState() {
    super.initState();
    // Картка — лише коли push налаштовано в збірці і її ще не закривали.
    if (!PushService.available) return;
    try {
      ref.read(localStoreProvider).read(_pushKey).then((v) {
        if (mounted) setState(() => _pushHidden = v?.data == true);
      }, onError: (_) {});
    } catch (_) {
      // Немає сховища (тести) — картку не показуємо.
    }
  }

  static const _pushKey = 'wave_alerts_card_done';

  Future<void> _enablePush() async {
    final res = await PushService.enable(ref.read(apiClientProvider));
    if (!mounted) return;
    if (res == null) {
      _snack('Сповіщення не ввімкнено — дозвольте їх у налаштуваннях телефону.');
      return;
    }
    setState(() => _pushHidden = true);
    try {
      await ref.read(localStoreProvider).write(_pushKey, true);
    } catch (_) {}
    if (!mounted) return;
    _snack(res.allowed
        ? 'Готово: повідомимо, коли на ділянці почнеться хвиля.'
        : (res.lockedLabel ?? 'Сповіщення про хвилі — у Pro або з рівня «Слідопит»'));
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Аналіз не на сьогодні або до оновлення застосунку — оновити безкоштовно (раз на добу);
  /// погоді понад 3 години — оновити лише погоду (теж безкоштовно, гриби лишаються).
  void _maybeAutoRefresh(AnalysisResult? result, bool offline) {
    if (result == null || offline || _busy || _autoRefreshing) return;
    if (result.isStale(_today())) {
      if (!_autoTried.add(_area.id)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoRefresh());
    } else if (result.weatherStale(DateTime.now())) {
      if (!_autoTried.add('${_area.id}@${result.weatherFreshUntil}')) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoRefresh(weatherOnly: true));
    }
  }

  Future<void> _autoRefresh({bool weatherOnly = false}) async {
    if (!mounted) return;
    setState(() {
      _autoRefreshing = true;
      _weatherOnly = weatherOnly;
      _autoFailed = false;
    });
    try {
      final repo = ref.read(analysisRepositoryProvider);
      final fresh = weatherOnly
          ? await repo.weatherRefresh(_area.id, forest: _forestHint())
          : await repo.dailyRefresh(_area.id, forest: _forestHint());
      if (fresh != null) ref.invalidate(analysisOverviewProvider);
    } catch (_) {
      // Погода не оновилась — лишається попередня, без банера.
      if (mounted && !weatherOnly) setState(() => _autoFailed = true);
    } finally {
      if (mounted) setState(() => _autoRefreshing = false);
    }
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Підписати ділянку: «Назва ділянки», до [AnalysisOverview.labelMax] символів, зберігається на сервері.
  Future<void> _rename(AnalysisArea area) async {
    if (widget.overview.offlineSince != null) {
      _snack('Без інтернету назву змінити не можна.');
      return;
    }
    final label = await showDialog<_RenameResult>(
      context: context,
      builder: (_) => _RenameDialog(initial: area.label ?? '', maxLength: widget.overview.labelMax, slot: area.slot),
    );
    if (label == null || !mounted) return;
    try {
      await ref.read(analysisRepositoryProvider).renameArea(area.id, label.value);
      ref.invalidate(analysisOverviewProvider);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    }
  }

  void _onSlotTap(AnalysisSlot slot) {
    switch (slot.state) {
      case AnalysisSlotState.area:
        ref.read(selectedAreaIdProvider.notifier).state = slot.areaId;
      case AnalysisSlotState.empty:
        context.go('/map');
      case AnalysisSlotState.locked:
        _snack(slot.lockedLabel ?? 'Доступно в Pro');
    }
  }

  AnalysisArea get _area => widget.area;

  /// Ліс у квадраті — з полігонів, які видно на карті (сервер має не всі області).
  Map<String, dynamic>? _forestHint() {
    final slug = ref.read(meProvider).valueOrNull?.homeRegion?.slug;
    if (slug == null) return null;
    final zones = ref.read(regionForestsProvider(slug)).valueOrNull?.zones;
    if (zones == null || zones.isEmpty) return null;
    return forestInSquare(zones, squareAround(_area.center, _area.sizeKm)).toJson();
  }

  /// «Оновити аналіз» — спершу запитати: це витрачає один з аналізів на сьогодні
  /// (рішення PO 2026-11-15: щоб не натискали випадково і з першого разу зрозуміли, що це).
  Future<void> _confirmReanalyze() async {
    final usage = _area.usage;
    final left = usage == null ? null : (usage.limit - usage.used).clamp(0, usage.limit);
    if (left == 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Аналізи на сьогодні закінчились'),
          content: Text('${usage!.label}. Нові аналізи з\'являться після півночі.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Зрозуміло'))],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Оновити аналіз?'),
        content: Text(
          'Прогноз ділянки й так оновлюється автоматично раз на день. Оновити зараз — '
          'перерахувати за найсвіжішою погодою.'
          '${left == null ? '' : ' Буде використано 1 аналіз — сьогодні лишилось $left з ${usage!.limit}.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Скасувати')),
          FilledButton(
            key: const ValueKey('reanalyze-confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Оновити'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _reanalyze();
  }

  Future<void> _reanalyze() async {
    setState(() => _busy = true);
    try {
      await ref.read(analysisRepositoryProvider).analyzeArea(_area.id, forest: _forestHint());
      ref.invalidate(analysisOverviewProvider);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося виконати аналіз. Спробуйте ще раз.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Видалити «${_area.title}»?'),
        content: const Text(
          'Ділянку й її результати буде видалено. Після цього на карті можна створити нову. '
          'Ліміт аналізів на сьогодні не зміниться.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Скасувати')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(analysisRepositoryProvider).deleteArea(_area.id);
      ref.read(selectedAreaIdProvider.notifier).state = null;
      ref.invalidate(analysisOverviewProvider);
      if (mounted) showToast(context, 'Ділянку видалено. Нову можна створити на карті.');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// «Уточнити ліс» (ADR-015 §15.6): породи зі списку → одразу переаналіз ділянки.
  Future<void> _refineForest(AnalysisResult result, ForestEditOptions options) async {
    final choice = await showForestRefineSheet(
      context,
      result: result,
      options: options,
      current: _area.forestOverride,
      usageLabel: _area.forestEdit?.label,
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(analysisRepositoryProvider).refineForest(_area.id, choice.override, forest: _forestHint());
      ref.invalidate(analysisOverviewProvider);
      if (mounted) {
        showToast(context, choice.override == null ? 'Ліс повернуто як на карті' : 'Ліс уточнено — прогноз оновлено');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
      if (e.code == 'forest_edit_limit_reached') ref.invalidate(analysisOverviewProvider);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося уточнити ліс. Спробуйте ще раз.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showOnMap() {
    ref.read(mapFocusAreaProvider.notifier).state = _area;
    context.go('/map');
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.overview;
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    final offline = o.offlineSince != null;
    final result = _area.lastResult;
    _maybeAutoRefresh(result, offline);
    // Віджет на головному екрані — свіжі підписи ділянки.
    if (result != null) {
      final area = _area;
      WidgetsBinding.instance.addPostFrameCallback((_) => HomeWidgetSync.update(area, result));
    }
    final stale = result != null && result.isStale(_today());

    // Верх (ділянки, дії, плашки) зазвичай займає менше половини екрана; з великим шрифтом на
    // малому екрані він гортається, а результат лишається видимим (UI-001).
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.55),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
            AreaSlotsRow(
              slots: o.slots,
              selectedAreaId: _area.id,
              onTap: _onSlotTap,
              onRename: (slot) {
                final a = o.areaById(slot.areaId);
                if (a != null) _rename(a);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _area.usage == null
                        ? const SizedBox.shrink()
                        : Text(_area.usage!.label, style: TextStyle(fontSize: 13, color: muted)),
                  ),
                  // «Оновити аналіз» — компактний значок замість великої кнопки (рішення PO 2026-11-14).
                  if (result != null)
                    IconButton(
                      key: const ValueKey('reanalyze'),
                      tooltip: 'Оновити аналіз',
                      onPressed: _busy || offline ? null : _confirmReanalyze,
                      icon: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.darkGreen),
                            )
                          : const Icon(Icons.refresh_rounded, color: AppTheme.darkGreen),
                    ),
                  // «Хвиля по днях» — завжди тут; доступ і старий аналіз пояснює натискання.
                  if (result != null)
                    ListenableBuilder(
                      listenable: _play,
                      builder: (context, _) => IconButton(
                        key: const ValueKey('play-days'),
                        tooltip: _play.playing ? 'Пауза' : 'Хвиля по днях',
                        onPressed: _play.press,
                        icon: Icon(
                          _play.playing ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                          color: AppTheme.darkGreen,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Показати на карті',
                    onPressed: _showOnMap,
                    icon: const Icon(Icons.map_outlined, color: AppTheme.darkGreen),
                  ),
                  IconButton(
                    tooltip: 'Видалити ділянку',
                    onPressed: _busy || offline ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
            if (result != null && PushService.available && !_pushHidden)
              _WaveAlertsCard(
                onEnable: _enablePush,
                onClose: () => setState(() => _pushHidden = true),
              ),
            if (_autoRefreshing)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  key: const ValueKey('auto-refreshing'),
                  children: [
                    const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkGreen)),
                    const SizedBox(width: 8),
                    Text(_weatherOnly ? 'Оновлюємо погоду…' : 'Оновлюємо прогноз на сьогодні…',
                        style: const TextStyle(fontSize: 13, color: AppTheme.darkGreen)),
                  ],
                ),
              )
            else if (stale && (offline || _autoFailed))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: ForecastInfoCard(
                  key: const ValueKey('stale-banner'),
                  icon: Icons.update_rounded,
                  color: AppTheme.accentOrange,
                  text: result.resultVersion < kExpectedResultVersion
                      ? 'Аналіз зроблено до оновлення застосунку — частина даних недоступна. '
                          '${offline ? 'Оновиться, коли з\'явиться інтернет.' : 'Натисніть ⟳.'}'
                      : 'Прогноз від ${result.date.substring(8, 10)}.${result.date.substring(5, 7)}. '
                          '${offline ? 'Оновиться автоматично, коли з\'явиться інтернет.' : 'Не вдалося оновити — натисніть ⟳.'}',
                ),
              ),
            if (offline)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: ForecastInfoCard(
                  icon: Icons.cloud_off_rounded,
                  color: AppTheme.accentOrange,
                  text: 'Немає інтернету — показано збережений результат.',
                ),
              ),
                ],
              ),
            ),
          ),
          Expanded(
            child: result == null
                ? _Message(
                    icon: Icons.insights_rounded,
                    title: 'Аналізу ще немає',
                    text: 'Натисніть «Аналізувати ділянку», щоб отримати прогноз.',
                    action: FilledButton.icon(
                      onPressed: _busy || offline ? null : _reanalyze,
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, minimumSize: const Size(220, 46)),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.insights_rounded),
                      label: Text(_busy ? 'Аналізуємо…' : 'Аналізувати ділянку'),
                    ),
                  )
                : RefreshIndicator(
                    // Потягнути вниз — оновити ділянки з сервера (без нового аналізу).
                    color: AppTheme.darkGreen,
                    onRefresh: () => ref.refresh(analysisOverviewProvider.future),
                    child: AnalysisResultView(
                    key: ValueKey('result-${_area.id}'),
                    result: result,
                    playController: _play,
                    miniMapBuilder: result.area.bounds == null
                        ? null
                        : (species) => AreaMiniMap(
                              areaId: result.area.id,
                              bounds: result.area.bounds!,
                              species: species,
                              analyzedAt: _area.lastAnalyzedAt,
                              history: result.finds?.lastYear ?? const [],
                            ),
                    refineHintLabel: result.forestTypes.isEmpty ? null : _area.forestEdit?.label,
                    // Уточнювати є що, лише коли в ділянці є ліс; без мережі й понад ліміт — ні.
                    onRefineForest: o.forestEditOptions != null &&
                            result.forestTypes.isNotEmpty &&
                            (_area.forestEdit?.canEdit ?? false) &&
                            !_busy &&
                            !offline
                        ? () => _refineForest(result, o.forestEditOptions!)
                        : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text, this.action});

  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppTheme.darkGreen),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTheme.heading(20),
              ),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}

/// Три клітинки ділянок у стилі смужки днів (ADR-015 §15.9): зайнята — назва й розмір,
/// олівець і довге натискання — «Назва ділянки»; вільна (Pro) — «+ Нова ділянка»;
/// під замком — «Ще 2 ділянки — у Pro».
class AreaSlotsRow extends StatelessWidget {
  const AreaSlotsRow({
    super.key,
    required this.slots,
    required this.selectedAreaId,
    required this.onTap,
    required this.onRename,
  });

  final List<AnalysisSlot> slots;
  final String? selectedAreaId;
  final ValueChanged<AnalysisSlot> onTap;
  final ValueChanged<AnalysisSlot> onRename;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        // Звичайно 68 px; з великим шрифтом плитки ростуть разом із текстом (UI-001).
        child: IntrinsicHeight(
          child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < slots.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _SlotTile(
                  slot: slots[i],
                  selected: slots[i].areaId != null && slots[i].areaId == selectedAreaId,
                  onTap: () => onTap(slots[i]),
                  onRename: () => onRename(slots[i]),
                )),
              ],
            ],
          ),
          ),
        ),
      );
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot, required this.selected, required this.onTap, required this.onRename});

  final AnalysisSlot slot;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final locked = slot.state == AnalysisSlotState.locked;
    final dim = AppTheme.darkGreen.withValues(alpha: 0.45);
    final Widget body = switch (slot.state) {
      AnalysisSlotState.area => Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 24, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    slot.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: AppTheme.darkGreen,
                    ),
                  ),
                  if (slot.subtitle != null)
                    Text(slot.subtitle!, style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6))),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                key: ValueKey('rename-slot-${slot.slot}'),
                tooltip: 'Назва ділянки',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                iconSize: 16,
                onPressed: onRename,
                icon: Icon(Icons.edit_outlined, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      AnalysisSlotState.empty => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, size: 18, color: AppTheme.darkGreen),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                slot.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.darkGreen),
              ),
            ),
          ],
        ),
      AnalysisSlotState.locked => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: dim),
            const SizedBox(height: 2),
            Text(slot.title, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: dim)),
          ],
        ),
    };
    return Material(
      key: ValueKey('slot-${slot.slot}'),
      color: locked ? Colors.white.withValues(alpha: 0.5) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppTheme.darkGreen : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: slot.state == AnalysisSlotState.area ? onRename : null,
        child: SizedBox.expand(child: body),
      ),
    );
  }
}

/// Результат діалогу назви: [value] `null` — повернути «Ділянка N».
class _RenameResult {
  const _RenameResult(this.value);
  final String? value;
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial, required this.maxLength, required this.slot});

  final String initial;
  final int maxLength;
  final int slot;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final v = _text.text.trim();
    Navigator.pop(context, _RenameResult(v.isEmpty ? null : v));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Назва ділянки'),
        content: TextField(
          key: const ValueKey('area-label-field'),
          controller: _text,
          autofocus: true,
          maxLength: widget.maxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: 'Наприклад: Біля Броників', helperText: 'Порожньо — «Ділянка ${widget.slot}»'),
          onSubmitted: (_) => _save(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати')),
          FilledButton(
            key: const ValueKey('area-label-save'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen),
            onPressed: _save,
            child: const Text('Зберегти'),
          ),
        ],
      );
}

/// «Сповіщати, коли почнеться хвиля?» — лише якщо push налаштовано в збірці.
class _WaveAlertsCard extends StatelessWidget {
  const _WaveAlertsCard({required this.onEnable, required this.onClose});

  final VoidCallback onEnable;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('wave-alerts-card'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined, color: AppTheme.darkGreen, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Сповіщати, коли на ділянці почнеться хвиля?',
                    style: TextStyle(fontSize: 13, color: AppTheme.darkGreen)),
              ),
              TextButton(key: const ValueKey('wave-alerts-enable'), onPressed: onEnable, child: const Text('Увімкнути')),
              IconButton(
                tooltip: 'Не зараз',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 18, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      );
}
