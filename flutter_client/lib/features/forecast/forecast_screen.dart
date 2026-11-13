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
import 'package:flutter_client/features/analysis/analysis_square.dart';
import 'package:flutter_client/features/analysis/forest_area.dart';
import 'package:flutter_client/features/analysis/forest_refine_sheet.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart' show ForecastInfoCard;

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
          IconButton(
            tooltip: 'Оновити',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(analysisOverviewProvider),
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

  AnalysisArea get _area => widget.area;

  /// Ліс у квадраті — з полігонів, які видно на карті (сервер має не всі області).
  Map<String, dynamic>? _forestHint() {
    final slug = ref.read(meProvider).valueOrNull?.homeRegion?.slug;
    if (slug == null) return null;
    final zones = ref.read(regionForestsProvider(slug)).valueOrNull?.zones;
    if (zones == null || zones.isEmpty) return null;
    return forestInSquare(zones, squareAround(_area.center, _area.sizeKm)).toJson();
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

    return Column(
      children: [
        if (o.areas.length > 1 || o.canCreate)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                for (final a in o.areas)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(a.title),
                      selected: a.id == _area.id,
                      onSelected: (_) => ref.read(selectedAreaIdProvider.notifier).state = a.id,
                    ),
                  ),
                if (o.canCreate)
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Нова ділянка'),
                    onPressed: () => context.go('/map'),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_area.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (_area.usage != null) Text(_area.usage!.label, style: TextStyle(fontSize: 12, color: muted)),
                  ],
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
        if (offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: ForecastInfoCard(
              icon: Icons.cloud_off_rounded,
              color: AppTheme.accentOrange,
              text: 'Немає інтернету — показано збережений результат.',
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: FilledButton.icon(
            onPressed: _busy || offline ? null : _reanalyze,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.darkGreen,
              minimumSize: const Size.fromHeight(46),
            ),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.insights_rounded),
            label: Text(_busy ? 'Аналізуємо…' : (result == null ? 'Аналізувати ділянку' : 'Оновити аналіз')),
          ),
        ),
        Expanded(
          child: result == null
              ? _Message(
                  icon: Icons.insights_rounded,
                  title: 'Аналізу ще немає',
                  text: 'Натисніть «Аналізувати ділянку», щоб отримати прогноз.',
                )
              : AnalysisResultView(
                  result: result,
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
      ],
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
                style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
              ),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}
