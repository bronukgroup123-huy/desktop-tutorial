import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/forecast.dart' show IdentifyCard;
import 'package:flutter_client/features/analysis/mushroom_stickers.dart';
import 'package:flutter_client/features/analysis/weather_insight_view.dart';
import 'package:flutter_client/features/analysis/weather_scene.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';

/// ▶ «Хвиля по днях» ззовні: значок стоїть у верхньому рядку «Прогнозу» поруч з
/// оновленням, картою й видаленням (ADR-015 §15.9).
class WeekPlayController extends ChangeNotifier {
  bool _playing = false;
  VoidCallback? _onPress;

  /// Зараз прокручуються дні.
  bool get playing => _playing;

  /// Натиснули ▶ / ⏸.
  void press() => _onPress?.call();

  void _set(bool v) {
    if (_playing == v) return;
    _playing = v;
    notifyListeners();
  }
}

/// Аналіз зроблено до появи анімації тижня — підказати оновити.
const kWeekAnimationStaleLabel = 'Анімація тижня з\'явиться після оновлення аналізу — натисніть ⟳ угорі.';

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
    this.miniMapBuilder,
    this.playController,
  });

  final AnalysisResult result;

  /// ▶ у верхньому рядку екрана; `null` — значок стоїть над мінікартою.
  final WeekPlayController? playController;

  /// Мінікарта ділянки з грибами обраного дня (ADR-015 §15.9); `null` — без мінікарти.
  final Widget Function(List<StickerSpecies> species)? miniMapBuilder;
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

  /// ▶ — прокрутити дні: на мінікарті видно, як росте й спадає хвиля.
  Timer? _play;

  @override
  void initState() {
    super.initState();
    widget.playController?._onPress = _onPlayPressed;
  }

  @override
  void dispose() {
    _play?.cancel();
    final c = widget.playController;
    if (c != null && c._onPress == _onPlayPressed) {
      c._onPress = null;
      c._playing = false; // без notify: екран теж може саме розбиратися
    }
    super.dispose();
  }

  void _stopPlay() {
    _play?.cancel();
    _play = null;
    widget.playController?._set(false);
  }

  void _togglePlay() {
    if (_play != null) {
      setState(_stopPlay);
      return;
    }
    final days = widget.result.days;
    if (days.length < 2) return;
    var i = 0;
    setState(() => _selected = days.first.date);
    _play = Timer.periodic(const Duration(milliseconds: 1300), (t) {
      i++;
      if (!mounted || i >= days.length) {
        t.cancel();
        if (mounted) setState(_stopPlay);
        return;
      }
      setState(() => _selected = days[i].date);
    });
    widget.playController?._set(true);
    setState(() {});
  }

  /// Гриби обраного дня для кошика мінікарти: усі зі шансом (старий результат — найкращий
  /// і альтернатива).
  List<StickerSpecies> _stickers(AnalysisResult r) {
    final basket = r.basket;
    if (basket != null) {
      return [
        for (final b in basket)
          StickerSpecies(
            type: b.type,
            name: b.name,
            level: b.level,
            levelLabel: b.levelLabel,
            color: b.levelColor,
            whenLabel: b.whenLabel,
          ),
      ];
    }
    return [
      for (final s in [r.top1, r.alternative])
        if (s != null)
          StickerSpecies(
            type: s.species.mushroomType,
            name: s.species.nameUa,
            level: s.species.level,
            levelLabel: s.species.levelLabel,
            color: s.species.levelColor,
            whenLabel: s.species.whenLabel,
          ),
    ];
  }

  /// ▶ натиснуто: є доступ (Pro / «Слідопит») — прокрутити дні; немає — пояснення.
  void _onPlayPressed() {
    final w = widget.result.weekAnimation;
    final String? message = w == null || widget.result.days.length < 2
        ? kWeekAnimationStaleLabel
        : (!w.allowed ? (w.lockedLabel ?? 'Анімація тижня недоступна') : null);
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    _togglePlay();
  }

  AnalysisDay? get _day {
    for (final d in widget.result.days) {
      if (d.date == _selected) return d;
    }
    return null;
  }

  @override
  void didUpdateWidget(AnalysisResultView old) {
    super.didUpdateWidget(old);
    if (old.playController != widget.playController) {
      if (old.playController?._onPress == _onPlayPressed) old.playController!._onPress = null;
      widget.playController?._onPress = _onPlayPressed;
      widget.playController?._set(_play != null);
    }
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
        if (widget.miniMapBuilder != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ваші місця в ділянці',
                  style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                ),
              ),
              // День, який зараз на мінікарті (видно під час «хвилі по днях»).
              if (day != null)
                Text(day.dayLabel, key: const ValueKey('minimap-day'), style: TextStyle(fontSize: 13, color: muted)),
              // «Хвиля по днях» — один значок; доступ (Pro / «Слідопит») каже сервер.
              // Зазвичай значок у верхньому рядку екрана ([playController]).
              if (widget.playController == null)
                IconButton(
                  key: const ValueKey('play-days'),
                  tooltip: _play == null ? 'Хвиля по днях' : 'Пауза',
                  onPressed: _onPlayPressed,
                  icon: Icon(
                    _play == null ? Icons.play_circle_outline_rounded : Icons.pause_circle_outline_rounded,
                    color: AppTheme.darkGreen,
                    size: 28,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          widget.miniMapBuilder!(_stickers(r)),
          // Звірка з вашими знахідками і торішні знахідки (рішення PO 2026-11-15).
          for (final label in [r.finds?.verificationLabel, r.finds?.lastYearLabel])
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      label == r.finds?.verificationLabel ? Icons.verified_outlined : Icons.history_rounded,
                      size: 16,
                      color: AppTheme.darkGreen.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: AppTheme.darkGreen.withValues(alpha: 0.8)))),
                  ],
                ),
              ),
        ],
        const SizedBox(height: 14),
        _ForestCard(result: r, onRefine: widget.onRefineForest, refineHintLabel: widget.refineHintLabel),
        if (widget.result.days.isNotEmpty) ...[
          const SizedBox(height: 12),
          AnalysisDayStrip(
            days: widget.result.days,
            lockedDays: widget.result.lockedDays,
            selected: _selected,
            onSelect: (date) => setState(() {
              _stopPlay();
              _selected = date;
            }),
            onLocked: _showLocked,
          ),
          if (widget.result.bestDay case final best?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                key: const ValueKey('best-day'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() {
                  _stopPlay();
                  _selected = best.date;
                }),
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
        // Старий результат без днів — лише дата прогнозу.
        if (widget.result.days.isEmpty) ...[
          const SizedBox(height: 12),
          Text('Прогноз на ${r.date}', style: TextStyle(fontSize: 13, color: muted)),
        ],
        if (r.weather != null) ...[
          const SizedBox(height: 10),
          _WeatherCard(
            weather: r.weather!,
            nowHour: _nowHourIfToday(r.date),
            insight: widget.result.weatherInsight,
            selected: _selected,
            selectable: {for (final d in widget.result.days) d.date},
            onSelect: (date) => setState(() {
              _stopPlay();
              _selected = date;
            }),
          ),
        ],
        const SizedBox(height: 16),
        if (r.top1 == null)
          ForecastInfoCard(
            icon: Icons.eco_outlined,
            text: r.noDataReason ?? 'Цього дня немає видів, для яких склалися умови.',
          )
        else ...[
          _SpeciesBlock(item: r.top1!, primary: true, identify: r.identify[r.top1!.species.mushroomType]),
          if (r.alternative != null) ...[
            const SizedBox(height: 12),
            _SpeciesBlock(item: r.alternative!, identify: r.identify[r.alternative!.species.mushroomType]),
          ],
        ],
        // «Інші гриби сезону» — лише після натискання (рішення PO 2026-11-15).
        if (r.others.isNotEmpty) ...[const SizedBox(height: 8), OtherSpeciesBlock(others: r.others)],
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
                      // Рівень — не лише кольором, а й значком (для тих, хто погано розрізняє кольори).
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(levelIcon(d.level), size: 11, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              d.levelShortLabel,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
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

/// Значок рівня — щоб рівень було видно не лише кольором.
IconData levelIcon(String? level) => switch (level) {
      'peak' => Icons.keyboard_double_arrow_up_rounded,
      'high' => Icons.keyboard_arrow_up_rounded,
      'medium' => Icons.remove_rounded,
      'low' => Icons.keyboard_arrow_down_rounded,
      _ => Icons.help_outline_rounded,
    };

IconData weatherIcon(String? icon) => switch (icon) {
      'rain' => Icons.water_drop_rounded,
      'cloud' => Icons.cloud_rounded,
      'sun' => Icons.wb_sunny_rounded,
      'snow' => Icons.ac_unit_rounded,
      'fog' => Icons.foggy,
      _ => Icons.thermostat_rounded,
    };

/// «Інші гриби сезону»: кнопка, під нею — види в сезоні без шансу цього дня і чому.
class OtherSpeciesBlock extends StatefulWidget {
  const OtherSpeciesBlock({super.key, required this.others});

  final List<OtherSpecies> others;

  @override
  State<OtherSpeciesBlock> createState() => _OtherSpeciesBlockState();
}

class _OtherSpeciesBlockState extends State<OtherSpeciesBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          key: const ValueKey('other-species'),
          onPressed: () => setState(() => _open = !_open),
          style: TextButton.styleFrom(foregroundColor: AppTheme.darkGreen),
          icon: Icon(_open ? Icons.expand_less_rounded : Icons.spa_outlined, size: 20),
          label: Text(_open ? 'Сховати інші гриби' : 'Інші гриби (${widget.others.length})'),
        ),
        if (_open)
          Container(
            key: const ValueKey('other-species-list'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (group, title) in const [
                  ('today', 'У сезоні, але сьогодні без шансу'),
                  ('season', 'Дерева для них є, але сезон минув або ще не почався'),
                ])
                  if (widget.others.any((o) => o.group == group)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 2),
                      child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted)),
                    ),
                    for (final o in widget.others.where((o) => o.group == group)) _OtherRow(other: o),
                  ],
              ],
            ),
          ),
      ],
    );
  }
}

class _OtherRow extends StatelessWidget {
  const _OtherRow({required this.other});

  final OtherSpecies other;

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Сірий стікер — шансу цього дня немає.
          ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0, 0, 0, 1, 0,
            ]),
            child: SpeciesIcon(type: other.type, fallbackColor: const Color(0xff94a3b8), size: 30),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(other.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.darkGreen)),
                Text(other.reason, style: TextStyle(fontSize: 13, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeciesBlock extends StatelessWidget {
  const _SpeciesBlock({required this.item, this.primary = false, this.identify});

  final AnalysisSpecies item;
  final bool primary;
  final IdentifyCard? identify;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ForecastSpeciesCard(species: item.species, primary: primary, identify: identify),
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
              // Рельєф і ґрунт ділянки — коротко, дрібно.
              if (result.terrainLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.terrain_rounded, size: 16, color: AppTheme.darkGreen.withValues(alpha: 0.55)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          result.terrainLabel!,
                          key: const ValueKey('terrain-label'),
                          style: TextStyle(fontSize: 12.5, color: AppTheme.darkGreen.withValues(alpha: 0.7)),
                        ),
                      ),
                    ],
                  ),
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
              // Пояснення про уточнення й ліміт — у вікні «Уточнити ліс», не на головному екрані.
              if (onRefine != null || refineHintLabel != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('refine-forest'),
                    onPressed: onRefine ??
                        () => ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(refineHintLabel!))),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Уточнити ліс'),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Година зараз, якщо [date] — сьогодні (за годинником телефона); інакше `null`.
int? _nowHourIfToday(String date) {
  final n = DateTime.now();
  final today = '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  return date == today ? n.hour : null;
}

IconData _sceneIcon(String scene) => switch (scene) {
      'rain' || 'heavy_rain' => Icons.water_drop_rounded,
      'snow' || 'frost' => Icons.ac_unit_rounded,
      'fog' => Icons.foggy,
      'sunny' || 'heat' => Icons.wb_sunny_rounded,
      'partly_cloudy' => Icons.wb_cloudy_outlined,
      _ => Icons.cloud_rounded,
    };

/// Ніч · ранок · день · вечір (рішення PO 2026-11-17): сьогодні частина, що триває, — виділена,
/// минулі — бліді.
class _DayParts extends StatelessWidget {
  const _DayParts({required this.parts, this.nowHour});

  final List<WeatherPart> parts;
  final int? nowHour;

  @override
  Widget build(BuildContext context) => Row(
        key: const ValueKey('weather-parts'),
        children: [
          for (final p in parts)
            Expanded(
              child: Builder(builder: (context) {
                final current = nowHour != null && nowHour! >= p.fromHour && nowHour! < p.toHour;
                final past = nowHour != null && nowHour! >= p.toHour;
                final color = AppTheme.darkGreen.withValues(alpha: past ? 0.4 : 1);
                return Tooltip(
                  message: '${p.label}: ${p.sceneLabel}',
                  child: Container(
                    key: ValueKey('weather-part-${p.key}'),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: current ? AppTheme.darkGreen.withValues(alpha: 0.1) : null,
                      borderRadius: BorderRadius.circular(10),
                      border: current ? Border.all(color: AppTheme.darkGreen.withValues(alpha: 0.35)) : null,
                    ),
                    child: Column(
                      children: [
                        Text(current ? 'Зараз' : p.label,
                            style: TextStyle(fontSize: 11, fontWeight: current ? FontWeight.w800 : FontWeight.w500, color: color)),
                        const SizedBox(height: 2),
                        Icon(_sceneIcon(p.scene), size: 18, color: past ? color : AppTheme.accentOrange),
                        const SizedBox(height: 2),
                        Text(p.tempLabel, style: TextStyle(fontSize: 11.5, color: color)),
                      ],
                    ),
                  ),
                );
              }),
            ),
        ],
      );
}

/// Погода дня (рішення PO 2026-11-15): просто — анімована сцена з грибом-маскотом,
/// температура й одне речення для грибів; графік і цифри тижня — у «Розширені дані погоди».
class _WeatherCard extends StatefulWidget {
  const _WeatherCard({
    required this.weather,
    required this.selected,
    required this.onSelect,
    this.insight,
    this.selectable = const {},
    this.nowHour,
  });

  final AnalysisWeather weather;

  /// Година зараз, якщо показано сьогоднішній день (сцена — за частиною доби); інакше `null`.
  final int? nowHour;
  final WeatherInsight? insight;
  final String selected;
  final Set<String> selectable;
  final ValueChanged<String> onSelect;

  @override
  State<_WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<_WeatherCard> {
  bool _advanced = false;

  static const _tone = {
    'good': (Color(0xff2e7d32), Icons.check_circle_rounded),
    'bad': (Color(0xffd9480f), Icons.warning_amber_rounded),
    'neutral': (Color(0xff5f6b62), Icons.info_outline_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final weather = widget.weather;
    final insight = widget.insight;
    final tone = _tone[weather.verdictTone] ?? _tone['neutral']!;
    // Сьогодні — сцена частини доби, що триває (а не найгірша погода за всю добу).
    final now = widget.nowHour == null ? null : weather.partAt(widget.nowHour!);
    final scene = parseWeatherScene(now?.scene ?? weather.scene);
    final subtitle = now != null ? 'Зараз: ${now.sceneLabel.toLowerCase()}, ${now.tempLabel}' : weather.sceneLabel;
    final rainAhead = weather.rainAhead(widget.nowHour);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          weather.dayLabel ?? weather.tempLabel,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.darkGreen),
        ),
        if (subtitle != null)
          Text(subtitle,
              key: const ValueKey('weather-now'),
              style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.75))),
      ],
    );
    return Card(
      key: const ValueKey('weather-card'),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (scene != null)
              WeatherScene(
                kind: scene,
                sprouts: sproutCount(weather.sprouts),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: title,
                ),
              )
            else
              // Старий результат без сцени — іконка й температура.
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration:
                        BoxDecoration(color: AppTheme.accentOrange.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(weatherIcon(weather.icon), size: 28, color: AppTheme.accentOrange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: title),
                ],
              ),
            if (weather.parts.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DayParts(parts: weather.parts, nowHour: widget.nowHour),
            ],
            if (rainAhead != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Row(
                  children: [
                    Icon(Icons.water_drop_outlined, size: 16, color: AppTheme.darkGreen.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(rainAhead,
                          key: const ValueKey('weather-rain-ahead'),
                          style: TextStyle(fontSize: 12.5, color: AppTheme.darkGreen.withValues(alpha: 0.8))),
                    ),
                  ],
                ),
              ),
            if (weather.verdictLabel != null) ...[
              const SizedBox(height: 10),
              Container(
                key: const ValueKey('weather-verdict'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration:
                    BoxDecoration(color: tone.$1.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(tone.$2, size: 20, color: tone.$1),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(weather.verdictLabel!, style: TextStyle(color: tone.$1, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
            // Дні 5–7 — діапазон за кількома моделями погоди.
            if (weather.rangeLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Row(
                  children: [
                    Icon(Icons.stacked_line_chart_rounded, size: 16, color: AppTheme.darkGreen.withValues(alpha: 0.55)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        weather.rangeLabel!,
                        key: const ValueKey('weather-range'),
                        style: TextStyle(fontSize: 12.5, color: AppTheme.darkGreen.withValues(alpha: 0.75)),
                      ),
                    ),
                  ],
                ),
              ),
            if (_advanced) ...[
              // «Коли їхати»: світловий день і що взяти (рішення PO 2026-11-15).
              if (weather.sunLabel != null || weather.takeLabel != null) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    key: const ValueKey('weather-when'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Коли їхати',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.darkGreen.withValues(alpha: 0.85))),
                      if (weather.sunLabel != null) _WeatherDetail(icon: Icons.wb_twilight_rounded, text: weather.sunLabel!),
                      if (weather.takeLabel != null) _WeatherDetail(icon: Icons.backpack_outlined, text: weather.takeLabel!),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (insight != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: WeatherInsightView(
                    insight: insight,
                    selected: widget.selected,
                    selectable: widget.selectable,
                    onSelect: widget.onSelect,
                  ),
                )
              else ...[
                // Старий результат — цифри тижня, як раніше.
                _WeatherDetail(icon: Icons.thermostat_rounded, text: weather.tempLabel),
                _WeatherDetail(icon: Icons.water_drop_outlined, text: weather.rainLabel),
                _WeatherDetail(icon: Icons.opacity_rounded, text: weather.humidityLabel),
              ],
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('weather-advanced'),
                onPressed: () => setState(() => _advanced = !_advanced),
                style: TextButton.styleFrom(foregroundColor: AppTheme.darkGreen),
                icon: Icon(_advanced ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                label: Text(_advanced ? 'Сховати подробиці' : 'Розширені дані погоди'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherDetail extends StatelessWidget {
  const _WeatherDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: AppTheme.darkGreen.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text, style: TextStyle(fontSize: 13, color: AppTheme.darkGreen.withValues(alpha: 0.7)))),
          ],
        ),
      );
}
