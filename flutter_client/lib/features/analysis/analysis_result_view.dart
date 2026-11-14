import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';

/// Результат аналізу ділянки (ADR-015): ліси в квадраті, погода, Top-1 / Top-2.
/// Лише рівні з готовими підписами із сервера — без відсотків.
/// Показується повноцінним екраном у вкладці «Прогноз» (див. ForecastScreen).
///
/// Смужка днів (ADR-015 §15.7): усі дні вже у відповіді — перемикання без запитів і без
/// списання аналізів, працює й без інтернету.
class AnalysisResultView extends StatefulWidget {
  const AnalysisResultView({
    super.key,
    required this.result,
    this.scrollController,
    this.onRefineForest,
    this.refineHintLabel,
  });

  final AnalysisResult result;
  final ScrollController? scrollController;

  /// «Уточнити ліс» (ADR-015 §15.6); `null` — кнопки немає (ліміт, офлайн, лісів немає).
  final VoidCallback? onRefineForest;

  /// «Уточнити ліс сьогодні можна ще 1 раз» — із сервера.
  final String? refineHintLabel;

  @override
  State<AnalysisResultView> createState() => _AnalysisResultViewState();
}

class _AnalysisResultViewState extends State<AnalysisResultView> {
  late String _selected = widget.result.date;

  AnalysisDay? get _day {
    for (final d in widget.result.days) {
      if (d.date == _selected) return d;
    }
    return null;
  }

  @override
  void didUpdateWidget(AnalysisResultView old) {
    super.didUpdateWidget(old);
    // Новий аналіз — обраний день лишається, якщо він є серед нових днів.
    if (!widget.result.days.any((d) => d.date == _selected)) _selected = widget.result.date;
  }

  void _showLocked() {
    final label = widget.result.lockedLabel;
    if (label == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(label)));
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    final r = day == null ? widget.result : widget.result.forDay(day);
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          day == null ? 'Прогноз на ${r.date}' : 'Прогноз ділянки',
          style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
        ),
        Text('Ділянка ${r.area.sizeLabel}', style: TextStyle(color: muted)),
        if (widget.result.days.isNotEmpty) ...[
          const SizedBox(height: 12),
          AnalysisDayStrip(
            days: widget.result.days,
            lockedDays: widget.result.lockedDays,
            selected: _selected,
            onSelect: (date) => setState(() => _selected = date),
            onLocked: _showLocked,
          ),
          if (widget.result.bestDay case final best?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                key: const ValueKey('best-day'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _selected = best.date),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 18, color: AppTheme.accentOrange),
                    const SizedBox(width: 6),
                    Text(best.label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.darkGreen)),
                  ],
                ),
              ),
            ),
          if (day?.approximateLabel case final approx?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(approx, style: TextStyle(fontSize: 12, color: muted)),
            ),
        ],
        const SizedBox(height: 16),
        _ForestCard(result: r, onRefine: widget.onRefineForest, refineHintLabel: widget.refineHintLabel),
        if (r.weather != null) ...[const SizedBox(height: 12), _WeatherCard(weather: r.weather!)],
        const SizedBox(height: 16),
        if (r.top1 == null)
          ForecastInfoCard(
            icon: Icons.eco_outlined,
            text: r.noDataReason ?? 'Цього дня немає видів, для яких склалися умови.',
          )
        else ...[
          _SpeciesBlock(item: r.top1!, primary: true),
          if (r.alternative != null) ...[const SizedBox(height: 12), _SpeciesBlock(item: r.alternative!)],
        ],
        for (final w in r.warnings) ...[
          const SizedBox(height: 8),
          ForecastInfoCard(icon: Icons.warning_amber_rounded, text: w, color: AppTheme.accentOrange),
        ],
        const SizedBox(height: 16),
        Text(
          'Рівень показує, наскільки сприятливі умови для гриба цього дня, а не гарантію знахідки. '
          'Збирайте лише гриби, які точно знаєте.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }
}

/// Смужка днів: день, рівень кольором, погода. Дні під замком Pro — сірі з 🔒.
class AnalysisDayStrip extends StatelessWidget {
  const AnalysisDayStrip({
    super.key,
    required this.days,
    required this.lockedDays,
    required this.selected,
    required this.onSelect,
    required this.onLocked,
  });

  final List<AnalysisDay> days;
  final List<({String date, String dayLabel})> lockedDays;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onLocked;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 104,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final d in days)
              _DayTile(
                key: ValueKey('day-${d.date}'),
                label: d.dayLabel,
                selected: d.date == selected,
                onTap: () => onSelect(d.date),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: d.levelColor, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        d.levelShortLabel,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(weatherIcon(d.weather?.icon), size: 16, color: AppTheme.accentOrange),
                        if (d.approximate)
                          Text(' ≈', style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6))),
                      ],
                    ),
                  ],
                ),
              ),
            for (final l in lockedDays)
              _DayTile(
                key: ValueKey('locked-${l.date}'),
                label: l.dayLabel,
                selected: false,
                locked: true,
                onTap: onLocked,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 18, color: AppTheme.darkGreen.withValues(alpha: 0.45)),
                    Text('Pro', style: TextStyle(fontSize: 11, color: AppTheme.darkGreen.withValues(alpha: 0.45))),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
    this.locked = false,
  });

  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: locked ? Colors.white.withValues(alpha: 0.5) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? AppTheme.darkGreen : Colors.transparent, width: 2),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              width: 76,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: AppTheme.darkGreen.withValues(alpha: locked ? 0.45 : 1),
                    ),
                  ),
                  const SizedBox(height: 6),
                  child,
                ],
              ),
            ),
          ),
        ),
      );
}

IconData weatherIcon(String? icon) => switch (icon) {
      'rain' => Icons.water_drop_rounded,
      'cloud' => Icons.cloud_rounded,
      'sun' => Icons.wb_sunny_rounded,
      _ => Icons.thermostat_rounded,
    };

class _SpeciesBlock extends StatelessWidget {
  const _SpeciesBlock({required this.item, this.primary = false});

  final AnalysisSpecies item;
  final bool primary;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ForecastSpeciesCard(species: item.species, primary: primary),
          if (item.forestLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Text(
                'Шукати тут: ${item.forestLabel}',
                style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
              ),
            ),
        ],
      );
}

class _ForestCard extends StatelessWidget {
  const _ForestCard({required this.result, this.onRefine, this.refineHintLabel});

  final AnalysisResult result;
  final VoidCallback? onRefine;
  final String? refineHintLabel;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.forest_rounded, color: AppTheme.darkGreen),
                  const SizedBox(width: 10),
                  Expanded(child: Text(result.forestSummaryLabel, style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
              for (final t in result.forestTypes)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: t.typeColor, shape: BoxShape.circle),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.ageLabel == null ? t.typeLabel : '${t.typeLabel}, ${t.ageLabel}'),
                            if (t.speciesLabel != null)
                              Text(t.speciesLabel!, style: const TextStyle(fontSize: 13, color: AppTheme.darkGreen)),
                          ],
                        ),
                      ),
                      Text(t.areaLabel, style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              for (final e in result.forestExtra)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle_outline_rounded, size: 14, color: AppTheme.darkGreen),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.label)),
                      Text(e.presenceLabel, style: const TextStyle(fontSize: 13, color: AppTheme.darkGreen)),
                    ],
                  ),
                ),
              if (result.refineNoteLabel != null) ...[
                const SizedBox(height: 10),
                Text(
                  result.refineNoteLabel!,
                  style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
                ),
              ],
              if (onRefine != null || refineHintLabel != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (refineHintLabel != null)
                      Expanded(
                        child: Text(
                          refineHintLabel!,
                          style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
                        ),
                      )
                    else
                      const Spacer(),
                    TextButton.icon(
                      onPressed: onRefine,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Уточнити ліс'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.weather});

  final AnalysisWeather weather;

  IconData get _icon => weatherIcon(weather.icon);

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, size: 36, color: AppTheme.accentOrange),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (weather.dayLabel != null) ...[
                      Text(weather.dayLabel!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(weather.tempLabel),
                    ] else
                      Text(weather.tempLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(weather.rainLabel),
                    Text(weather.humidityLabel),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
