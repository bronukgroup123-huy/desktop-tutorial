import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/forecast.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/forecast/identify_view.dart';

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
          style: AppTheme.heading(20),
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
/// Картка виду. За замовчуванням — просто: рівень, «коли» (фаза хвилі) і «де шукати».
/// Причини рівня (що підходить і що заважає) — під кнопкою «Розширені дані»: розрахунки
/// лишаються всередині, грибнику не потрібно бути мікологом (рішення PO 2026-11-14).
class ForecastSpeciesCard extends StatefulWidget {
  const ForecastSpeciesCard({super.key, required this.species, this.primary = false, this.identify});

  final ForecastSpecies species;
  final bool primary;

  /// «Як відрізнити» з результату аналізу (один раз на вид); інакше — з самого виду.
  final IdentifyCard? identify;

  @override
  State<ForecastSpeciesCard> createState() => _ForecastSpeciesCardState();
}

class _ForecastSpeciesCardState extends State<ForecastSpeciesCard> {
  bool _advanced = false;
  bool _identify = false;

  @override
  Widget build(BuildContext context) {
    final species = widget.species;
    final primary = widget.primary;
    final hasDetails = species.whyLabels.isNotEmpty || species.limitLabels.isNotEmpty;
    final idCard = widget.identify ?? species.identify;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: species.levelColor.withValues(alpha: primary ? 0.8 : 0.35), width: primary ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_levelIcon(species.level), size: 14, color: species.levelColor),
                      const SizedBox(width: 3),
                      Text(
                        species.levelLabel,
                        style: TextStyle(color: species.levelColor, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Чому саме такий рівень — одним реченням, одразу під назвою (рішення PO 2026-11-15).
            if (species.reasonLabel != null) ...[
              const SizedBox(height: 10),
              _ReasonBox(text: species.reasonLabel!, color: species.levelColor),
            ],
            const SizedBox(height: 10),
            // Хвиля: смужка «підйом · розпал · спад» з позначкою дня; інакше — рядок «коли».
            if (species.wave?.isFlush ?? false)
              WaveStrip(wave: species.wave!)
            else
              _Line(icon: Icons.schedule_rounded, text: species.whenLabel),
            _Line(icon: Icons.place_outlined, text: species.whereLabel),
            if (_advanced) ...[
              if (species.whyLabels.isNotEmpty) ...[
                const _SectionTitle('Сприяє'),
                for (final why in species.whyLabels) _Line(icon: Icons.check_rounded, text: why, color: AppTheme.success),
              ],
              // Чому рівень не вищий — інакше «✓» суперечили б бейджу (напр. «Низька»).
              if (species.limitLabels.isNotEmpty) ...[
                const _SectionTitle('Не вистачає'),
                for (final limit in species.limitLabels)
                  _Line(icon: Icons.error_outline_rounded, text: limit, color: AppTheme.accentOrange),
              ],
            ],
            // «Як відрізнити» — ознаки, двійник і правило з довідника (рішення PO 2026-11-15).
            if (_identify && idCard != null) ...[
              const SizedBox(height: 6),
              IdentifyView(card: idCard, species: species),
            ],
            if (hasDetails || idCard != null)
              Wrap(
                spacing: 12,
                children: [
                  if (hasDetails)
                    TextButton.icon(
                      key: const ValueKey('species-advanced'),
                      onPressed: () => setState(() => _advanced = !_advanced),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppTheme.darkGreen),
                      icon: Icon(_advanced ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                      label: Text(_advanced ? 'Сховати подробиці' : 'Розширені дані'),
                    ),
                  if (idCard != null)
                    TextButton.icon(
                      key: const ValueKey('species-identify'),
                      onPressed: () => setState(() => _identify = !_identify),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppTheme.darkGreen),
                      icon: Icon(_identify ? Icons.expand_less_rounded : Icons.search_rounded, size: 20),
                      label: Text(_identify ? 'Сховати' : 'Як відрізнити'),
                    ),
                ],
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// «Чому середня: …» — підсвічено кольором рівня, префікс жирним.
class _ReasonBox extends StatelessWidget {
  const _ReasonBox({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final i = text.indexOf(': ');
    final dark = Color.lerp(color, Colors.black, 0.35)!;
    return Container(
      key: const ValueKey('species-reason'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text.rich(
        TextSpan(children: [
          if (i > 0) TextSpan(text: '${text.substring(0, i + 1)} ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: i > 0 ? text.substring(i + 2) : text),
        ]),
        style: TextStyle(color: dark, height: 1.3),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
        ),
      );
}

/// Смужка хвилі плодоношення: дні хвилі клітинками, стадії (підйом / розпал / спад) кольором,
/// пройдені дні — насиченіше, сьогоднішній — з позначкою. Лише дні й підписи із сервера.
class WaveStrip extends StatelessWidget {
  const WaveStrip({super.key, required this.wave});

  final SpeciesWave wave;

  static const stageColors = [Color(0xff9ccc65), AppTheme.success, Color(0xffc9a227)];

  @override
  Widget build(BuildContext context) {
    final days = wave.days!, day = wave.day!.clamp(1, wave.days!);
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    final cells = <Color>[];
    for (var g = 0; g < wave.segments.length; g++) {
      for (var k = 0; k < wave.segments[g].days; k++) {
        cells.add(stageColors[math.min(g, stageColors.length - 1)]);
      }
    }
    while (cells.length < days) {
      cells.add(stageColors.last);
    }
    return Padding(
      key: const ValueKey('wave-strip'),
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.waves_rounded, size: 18, color: AppTheme.darkGreen.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Expanded(child: Text(wave.label ?? '', style: const TextStyle(color: AppTheme.darkGreen))),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / days;
            return SizedBox(
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    top: 8,
                    child: Row(
                      children: [
                        for (var i = 0; i < days; i++)
                          Container(
                            width: w,
                            padding: const EdgeInsets.symmetric(horizontal: 0.75),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cells[i].withValues(alpha: i < day ? 1 : 0.28),
                                borderRadius: BorderRadius.horizontal(
                                  left: Radius.circular(i == 0 ? 6 : 1.5),
                                  right: Radius.circular(i == days - 1 ? 6 : 1.5),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Позначка сьогоднішнього дня хвилі.
                  Positioned(
                    left: (day - 0.5) * w - 7,
                    top: -2,
                    child: Container(
                      key: const ValueKey('wave-today'),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: cells[day - 1], width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var g = 0; g < wave.segments.length; g++)
                Expanded(
                  flex: wave.segments[g].days,
                  child: Text(
                    wave.segments[g].label,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: muted,
                      fontWeight: _stageIndex == g ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  int get _stageIndex => switch (wave.stage) { 'rise' => 0, 'peak' => 1, 'decline' => 2, _ => -1 };
}

/// Значок рівня — щоб рівень було видно не лише кольором.
IconData _levelIcon(String level) => switch (level) {
      'peak' => Icons.keyboard_double_arrow_up_rounded,
      'high' => Icons.keyboard_arrow_up_rounded,
      'medium' => Icons.remove_rounded,
      'low' => Icons.keyboard_arrow_down_rounded,
      _ => Icons.help_outline_rounded,
    };

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;

  /// Колір іконки (напр. помаранчевий для обмежувальних факторів).
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color ?? AppTheme.darkGreen.withValues(alpha: 0.8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: const TextStyle(color: AppTheme.darkGreen)),
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
