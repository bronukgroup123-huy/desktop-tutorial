import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';

/// Результат аналізу ділянки (ADR-015): ліси в квадраті, погода, Top-1 / Top-2.
/// Лише рівні з готовими підписами із сервера — без відсотків.
/// Показується повноцінним екраном у вкладці «Прогноз» (див. ForecastScreen).
class AnalysisResultView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final r = result;
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Прогноз на ${r.date}',
          style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
        ),
        Text('Ділянка ${r.area.sizeLabel}', style: TextStyle(color: muted)),
        const SizedBox(height: 16),
        _ForestCard(result: r, onRefine: onRefineForest, refineHintLabel: refineHintLabel),
        if (r.weather != null) ...[const SizedBox(height: 12), _WeatherCard(weather: r.weather!)],
        const SizedBox(height: 16),
        if (r.top1 == null)
          ForecastInfoCard(
            icon: Icons.eco_outlined,
            text: r.noDataReason ?? 'Зараз немає видів, для яких склалися умови.',
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
          'Прогноз — це ймовірність, а не гарантія. Збирайте лише гриби, які точно знаєте.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }
}

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

  IconData get _icon => switch (weather.icon) {
        'rain' => Icons.water_drop_rounded,
        'cloud' => Icons.cloud_rounded,
        'sun' => Icons.wb_sunny_rounded,
        _ => Icons.thermostat_rounded,
      };

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
