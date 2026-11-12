import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/forecast.dart';
import 'package:flutter_client/data/providers.dart';

/// Прогноз для обраної точки: погода, Top-1 / Top-2, «коли / де / чому».
/// Усі тексти й кольори — із сервера (Thin Client); чисел-ймовірностей немає.
/// Використовується і в Bottom Sheet карти, і на вкладці «Прогноз».
class ForecastView extends ConsumerWidget {
  const ForecastView({super.key, required this.point, this.scrollController});

  final ForecastPoint point;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(forecastProvider(point));
    return forecast.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _ErrorState(
        message: e is ApiException ? e.userMessage : 'Не вдалося отримати прогноз.',
        onRetry: () => ref.invalidate(forecastProvider(point)),
      ),
      data: (r) => _ForecastContent(
        forecast: r.value,
        point: point,
        scrollController: scrollController,
        offlineSince: r.offline ? r.savedAt : null,
      ),
    );
  }
}

class _ForecastContent extends StatelessWidget {
  const _ForecastContent({
    required this.forecast,
    required this.point,
    this.scrollController,
    this.offlineSince,
  });

  final Forecast forecast;
  final ForecastPoint point;
  final ScrollController? scrollController;

  /// Немає інтернету — показано збережений прогноз від цього часу.
  final DateTime? offlineSince;

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    final title = f.forestLabel.isNotEmpty ? f.forestLabel : (point.title ?? 'Обрана точка');
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          title,
          style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
        ),
        if (f.regionName != null)
          Text('${f.regionName} · ${f.date}', style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.6))),
        if (offlineSince != null) ...[
          const SizedBox(height: 12),
          ForecastInfoCard(
            icon: Icons.cloud_off_rounded,
            color: AppTheme.accentOrange,
            text: 'Немає інтернету. Показано прогноз від ${_formatTime(offlineSince!)}.',
          ),
        ],
        const SizedBox(height: 16),
        if (f.weather != null) ...[_WeatherCard(weather: f.weather!), const SizedBox(height: 16)],
        if (f.top1 == null)
          ForecastInfoCard(
            icon: Icons.eco_outlined,
            text: f.noDataReason ?? 'Зараз немає видів, для яких склалися умови.',
          )
        else ...[
          ForecastSpeciesCard(species: f.top1!, primary: true),
          if (f.alternative != null) ...[const SizedBox(height: 12), ForecastSpeciesCard(species: f.alternative!)],
        ],
        if (f.top1 != null && f.noDataReason != null) ...[
          const SizedBox(height: 12),
          ForecastInfoCard(icon: Icons.info_outline_rounded, text: f.noDataReason!),
        ],
        for (final w in f.warnings) ...[
          const SizedBox(height: 8),
          ForecastInfoCard(icon: Icons.warning_amber_rounded, text: w, color: AppTheme.accentOrange),
        ],
        const SizedBox(height: 16),
        Text(
          'Прогноз — це ймовірність, а не гарантія. Збирайте лише гриби, які точно знаєте.',
          style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.55)),
        ),
      ],
    );
  }
}

String _formatTime(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}, ${two(l.hour)}:${two(l.minute)}';
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.weather});

  final ForecastWeather weather;

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
                    Text(weather.rainRecentLabel),
                    Text('${weather.humidityLabel} · ${weather.pressureLabel}',
                        style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// Картка виду: рівень, «коли / де / чому». Використовується і в аналізі ділянки.
class ForecastSpeciesCard extends StatelessWidget {
  const ForecastSpeciesCard({super.key, required this.species, this.primary = false});

  final ForecastSpecies species;
  final bool primary;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: species.levelColor.withValues(alpha: primary ? 0.8 : 0.35), width: primary ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      species.nameUa,
                      style: GoogleFonts.merriweather(fontSize: primary ? 18 : 16, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: species.levelColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      species.levelLabel,
                      style: TextStyle(color: species.levelColor, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Line(icon: Icons.schedule_rounded, text: species.whenLabel),
              _Line(icon: Icons.place_outlined, text: species.whereLabel),
              if (species.whyLabels.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final why in species.whyLabels) _Line(icon: Icons.check_rounded, text: why, muted: true),
              ],
              // Чому рівень не вищий — інакше «✓» суперечили б бейджу (напр. «Низька»).
              if (species.limitLabels.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final limit in species.limitLabels)
                  _Line(icon: Icons.error_outline_rounded, text: limit, color: AppTheme.accentOrange),
              ],
            ],
          ),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.muted = false, this.color});

  final IconData icon;
  final String text;
  final bool muted;

  /// Колір іконки (напр. помаранчевий для обмежувальних факторів).
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color ?? AppTheme.darkGreen.withValues(alpha: muted ? 0.5 : 0.8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: muted ? 0.75 : 1))),
            ),
          ],
        ),
      );
}

/// Рядок-підказка з іконкою (попередження, пояснення).
class ForecastInfoCard extends StatelessWidget {
  const ForecastInfoCard({super.key, required this.icon, required this.text, this.color = AppTheme.darkGreen});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Повторити')),
          ],
        ),
      );
}
