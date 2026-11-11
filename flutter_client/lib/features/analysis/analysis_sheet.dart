import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';

/// Результат аналізу ділянки (ADR-015): ліси в квадраті, погода, Top-1 / Top-2.
/// Лише рівні з готовими підписами із сервера — без відсотків.
Future<void> showAnalysisResult(BuildContext context, AnalysisResult result) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.backgroundColor,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, controller) => AnalysisResultView(result: result, scrollController: controller),
      ),
    );

class AnalysisResultView extends StatelessWidget {
  const AnalysisResultView({super.key, required this.result, this.scrollController});

  final AnalysisResult result;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Аналіз ділянки ${r.area.sizeLabel}',
          style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
        ),
        Text('${r.date} · ${r.usage.label}', style: TextStyle(color: muted)),
        const SizedBox(height: 16),
        _ForestCard(summary: r.forestSummaryLabel, types: r.forestTypes),
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
  const _ForestCard({required this.summary, required this.types});

  final String summary;
  final List<AnalysisForestType> types;

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
                  Expanded(child: Text(summary, style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
              for (final t in types)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: t.typeColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t.ageLabel == null ? t.typeLabel : '${t.typeLabel}, ${t.ageLabel}')),
                      Text(t.areaLabel, style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
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
