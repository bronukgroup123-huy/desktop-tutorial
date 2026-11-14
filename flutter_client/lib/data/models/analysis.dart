import 'dart:ui' show Color;

import 'package:latlong2/latlong.dart';

import 'forecast.dart';
import 'forest_zone.dart' show parseHexColor;
import 'geo.dart';
import 'json.dart';

/// Розмір ділянки аналізу. Чи доступний він користувачу — вирішує сервер.
class AnalysisSizeOption {
  const AnalysisSizeOption({
    required this.sizeKm,
    required this.label,
    required this.available,
    required this.lockLabel,
  });

  factory AnalysisSizeOption.fromJson(Map<String, dynamic> json) => AnalysisSizeOption(
        sizeKm: req<num>(json, 'size_km').toInt(),
        label: req<String>(json, 'label'),
        available: req<bool>(json, 'available'),
        lockLabel: opt<String>(json, 'lock_label'),
      );

  final int sizeKm;

  /// «5×5 км»
  final String label;
  final bool available;

  /// «Доступно в Pro» — коли розмір недоступний.
  final String? lockLabel;
}

/// Скільки аналізів використано сьогодні.
class AnalysisUsage {
  const AnalysisUsage({required this.used, required this.limit, required this.label});

  factory AnalysisUsage.fromJson(Map<String, dynamic> json) => AnalysisUsage(
        used: req<num>(json, 'used').toInt(),
        limit: req<num>(json, 'limit').toInt(),
        label: req<String>(json, 'label'),
      );

  final int used;
  final int limit;

  /// «Сьогодні: 2 з 5 аналізів»
  final String label;
}

/// Збережена ділянка користувача (ADR-015 §15.4): після створення незмінна —
/// центр і розмір не пересуваються; її можна лише повторно аналізувати або видалити.
class AnalysisArea {
  const AnalysisArea({
    required this.id,
    required this.center,
    required this.sizeKm,
    required this.sizeLabel,
    this.slot = 1,
    this.bounds,
    this.usage,
    this.lastResult,
    this.lastAnalyzedAt,
    this.forestOverride,
    this.forestEdit,
  });

  factory AnalysisArea.fromJson(Map<String, dynamic> json) {
    final override = opt<Map<String, dynamic>>(json, 'forest_override');
    final edit = opt<Map<String, dynamic>>(json, 'forest_edit');
    final bbox = opt<List<dynamic>>(json, 'bbox');
    final usage = opt<Map<String, dynamic>>(json, 'usage');
    final last = opt<Map<String, dynamic>>(json, 'last_result');
    final lastAt = opt<String>(json, 'last_analyzed_at');
    return AnalysisArea(
      id: req<String>(json, 'id'),
      slot: opt<num>(json, 'slot')?.toInt() ?? 1,
      center: LatLng(toDouble(json['lat'], 'lat'), toDouble(json['lng'], 'lng')),
      sizeKm: req<num>(json, 'size_km').toInt(),
      sizeLabel: req<String>(json, 'size_label'),
      bounds: bbox == null ? null : GeoBounds.fromBbox(bbox),
      usage: usage == null ? null : AnalysisUsage.fromJson(usage),
      lastResult: last == null ? null : AnalysisResult.fromJson(last),
      lastAnalyzedAt: lastAt == null ? null : DateTime.tryParse(lastAt),
      forestOverride: override == null ? null : ForestOverride.fromJson(override),
      forestEdit: edit == null ? null : ForestEditUsage.fromJson(edit),
    );
  }

  final String id;
  final int slot;
  final LatLng center;
  final int sizeKm;
  final String sizeLabel;

  /// Точні межі квадрата, який проаналізував сервер (є у відповіді аналізу).
  final GeoBounds? bounds;

  /// Аналізи цієї ділянки сьогодні.
  final AnalysisUsage? usage;

  /// Останній результат — показується без повторного списання аналізу.
  final AnalysisResult? lastResult;
  final DateTime? lastAnalyzedAt;

  /// Уточнення лісу вручну (ADR-015 §15.6); `null` — ліс як на карті.
  final ForestOverride? forestOverride;

  /// Скільки уточнень лісу ще можна сьогодні — вирішує сервер.
  final ForestEditUsage? forestEdit;

  /// «Ділянка 1 · 5×5 км»
  String get title => 'Ділянка $slot · $sizeLabel';
}

/// Відповідь `GET /v1-analysis`: що доступно і що вже збережено.
class AnalysisOverview {
  const AnalysisOverview({
    required this.sizes,
    required this.areas,
    required this.usage,
    required this.hintLabel,
    this.canCreate = true,
    this.createHintLabel,
    this.offlineSince,
    this.forestEditOptions,
  });

  factory AnalysisOverview.fromJson(Map<String, dynamic> json, {DateTime? offlineSince}) => AnalysisOverview(
        sizes: (opt<List<dynamic>>(json, 'sizes') ?? const [])
            .map((s) => AnalysisSizeOption.fromJson(s as Map<String, dynamic>))
            .toList(growable: false),
        areas: (opt<List<dynamic>>(json, 'areas') ?? const [])
            .map((a) => AnalysisArea.fromJson(a as Map<String, dynamic>))
            .toList(growable: false),
        usage: AnalysisUsage.fromJson(req<Map<String, dynamic>>(json, 'usage')),
        hintLabel: req<String>(json, 'hint_label'),
        canCreate: opt<bool>(json, 'can_create') ?? true,
        createHintLabel: opt<String>(json, 'create_hint_label'),
        offlineSince: offlineSince,
        forestEditOptions: switch (opt<Map<String, dynamic>>(json, 'forest_edit_options')) {
          final o? => ForestEditOptions.fromJson(o),
          null => null,
        },
      );

  final List<AnalysisSizeOption> sizes;
  final List<AnalysisArea> areas;
  final AnalysisUsage usage;
  final String hintLabel;

  /// Чи є вільне місце для нової ділянки (вирішує сервер).
  final bool canCreate;

  /// Що робити, щоб створити нову: «Видаліть стару у вкладці «Прогноз»…».
  final String? createHintLabel;

  /// Немає інтернету — показано збережену копію від цього часу.
  final DateTime? offlineSince;

  /// Породи для «Уточнити ліс» — лише зі списку сервера.
  final ForestEditOptions? forestEditOptions;

  AnalysisArea? areaById(String? id) {
    for (final a in areas) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// Тип лісу в ділянці: підпис, колір і площа — із сервера.
class AnalysisForestType {
  const AnalysisForestType({
    required this.typeLabel,
    required this.typeColor,
    required this.areaLabel,
    required this.ageLabel,
    this.forestType,
    this.species = const [],
    this.speciesLabel,
  });

  factory AnalysisForestType.fromJson(Map<String, dynamic> json) => AnalysisForestType(
        forestType: opt<String>(json, 'forest_type'),
        typeLabel: req<String>(json, 'type_label'),
        typeColor: parseHexColor(req<String>(json, 'type_color')),
        areaLabel: req<String>(json, 'area_label'),
        ageLabel: opt<String>(json, 'age_label'),
        species: stringList(json, 'species'),
        speciesLabel: opt<String>(json, 'species_label'),
      );

  /// Код типу з карти (`coniferous`, `pine`…); `null` — тип невідомий.
  final String? forestType;
  final String typeLabel;
  final Color typeColor;
  final String areaLabel;
  final String? ageLabel;

  /// Породи, обрані вручну для цього типу.
  final List<String> species;

  /// «сосна, ялина · уточнено вами»
  final String? speciesLabel;
}

/// Порода, якої карта не бачить, додана вручну: «Дуб — є місцями».
class AnalysisForestExtra {
  const AnalysisForestExtra({required this.species, required this.label, required this.presence, required this.presenceLabel});

  factory AnalysisForestExtra.fromJson(Map<String, dynamic> json) => AnalysisForestExtra(
        species: req<String>(json, 'species'),
        label: req<String>(json, 'label'),
        presence: req<String>(json, 'presence'),
        presenceLabel: req<String>(json, 'presence_label'),
      );

  final String species;
  final String label;
  final String presence;
  final String presenceLabel;
}

/// Уточнення лісу ділянки (тіло `PUT v1-analysis/areas/{id}/forest`).
class ForestOverride {
  const ForestOverride({this.types = const {}, this.extra = const {}});

  factory ForestOverride.fromJson(Map<String, dynamic> json) => ForestOverride(
        types: {
          for (final t in (opt<List<dynamic>>(json, 'types') ?? const []).cast<Map<String, dynamic>>())
            opt<String>(t, 'forest_type'): stringList(t, 'species'),
        },
        extra: {
          for (final e in (opt<List<dynamic>>(json, 'extra') ?? const []).cast<Map<String, dynamic>>())
            req<String>(e, 'species'): req<String>(e, 'presence'),
        },
      );

  /// Тип лісу з карти (`null` — невідомий) → 1–2 породи.
  final Map<String?, List<String>> types;

  /// Порода → `dominant` | `present`.
  final Map<String, String> extra;

  bool get isEmpty => types.values.every((s) => s.isEmpty) && extra.isEmpty;

  Map<String, dynamic> toJson() => {
        'types': [
          for (final e in types.entries)
            if (e.value.isNotEmpty) {'forest_type': e.key, 'species': e.value},
        ],
        'extra': [
          for (final e in extra.entries) {'species': e.key, 'presence': e.value},
        ],
      };
}

/// Скільки разів сьогодні ще можна уточнити ліс ділянки.
class ForestEditUsage {
  const ForestEditUsage({required this.used, required this.limit, required this.canEdit, required this.label});

  factory ForestEditUsage.fromJson(Map<String, dynamic> json) => ForestEditUsage(
        used: req<num>(json, 'used').toInt(),
        limit: req<num>(json, 'limit').toInt(),
        canEdit: req<bool>(json, 'can_edit'),
        label: req<String>(json, 'label'),
      );

  final int used;
  final int limit;
  final bool canEdit;
  final String label;
}

/// Варіанти для «Уточнити ліс» — із сервера.
class ForestEditOptions {
  const ForestEditOptions({required this.species, required this.presence});

  factory ForestEditOptions.fromJson(Map<String, dynamic> json) {
    List<({String code, String label})> list(String key) => [
          for (final o in (opt<List<dynamic>>(json, key) ?? const []).cast<Map<String, dynamic>>())
            (code: req<String>(o, 'code'), label: req<String>(o, 'label')),
        ];
    return ForestEditOptions(species: list('species'), presence: list('presence'));
  }

  final List<({String code, String label})> species;
  final List<({String code, String label})> presence;
}

/// Вид у результаті аналізу + у якому лісі ділянки його шукати.
class AnalysisSpecies {
  const AnalysisSpecies({required this.species, required this.forestLabel});

  factory AnalysisSpecies.fromJson(Map<String, dynamic> json) => AnalysisSpecies(
        species: ForecastSpecies.fromJson(json),
        forestLabel: opt<String>(json, 'forest_label'),
      );

  final ForecastSpecies species;
  final String? forestLabel;
}

/// Базова погода ділянки: температура, вологість, опади.
class AnalysisWeather {
  const AnalysisWeather({
    required this.icon,
    required this.tempLabel,
    required this.humidityLabel,
    required this.rainLabel,
    this.dayLabel,
  });

  factory AnalysisWeather.fromJson(Map<String, dynamic> json) => AnalysisWeather(
        icon: req<String>(json, 'icon'),
        tempLabel: req<String>(json, 'temp_label'),
        humidityLabel: req<String>(json, 'humidity_label'),
        rainLabel: req<String>(json, 'rain_label'),
        dayLabel: opt<String>(json, 'day_label'),
      );

  /// Погода самого дня: «4…11°, опади 8 мм».
  final String? dayLabel;
  final String icon;
  final String tempLabel;
  final String humidityLabel;
  final String rainLabel;
}

/// Один день смужки прогнозу ділянки (ADR-015 §15.7).
class AnalysisDay {
  const AnalysisDay({
    required this.date,
    required this.dayLabel,
    required this.approximate,
    required this.approximateLabel,
    required this.level,
    required this.levelLabel,
    required this.levelShortLabel,
    required this.levelColor,
    required this.top1,
    required this.alternative,
    required this.weather,
    required this.warnings,
    required this.noDataReason,
  });

  factory AnalysisDay.fromJson(Map<String, dynamic> json) {
    final top1 = opt<Map<String, dynamic>>(json, 'top1');
    final alt = opt<Map<String, dynamic>>(json, 'alternative');
    final weather = opt<Map<String, dynamic>>(json, 'weather');
    return AnalysisDay(
      date: req<String>(json, 'date'),
      dayLabel: req<String>(json, 'day_label'),
      approximate: opt<bool>(json, 'approximate') ?? false,
      approximateLabel: opt<String>(json, 'approximate_label'),
      level: req<String>(json, 'level'),
      levelLabel: req<String>(json, 'level_label'),
      levelShortLabel: opt<String>(json, 'level_short_label') ?? req<String>(json, 'level_label'),
      levelColor: parseHexColor(req<String>(json, 'level_color')),
      top1: top1 == null ? null : AnalysisSpecies.fromJson(top1),
      alternative: alt == null ? null : AnalysisSpecies.fromJson(alt),
      weather: weather == null ? null : AnalysisWeather.fromJson(weather),
      warnings: stringList(json, 'warnings'),
      noDataReason: opt<String>(json, 'no_data_reason'),
    );
  }

  final String date;

  /// «Сьогодні», «Завтра», «Сб 16».
  final String dayLabel;

  /// Дні 5–7: прогноз погоди менш точний.
  final bool approximate;
  final String? approximateLabel;
  final String level;
  final String levelLabel;

  /// «Висока» — для смужки днів.
  final String levelShortLabel;
  final Color levelColor;
  final AnalysisSpecies? top1;
  final AnalysisSpecies? alternative;
  final AnalysisWeather? weather;
  final List<String> warnings;
  final String? noDataReason;
}

/// Відповідь `POST /v1-analysis`. Лише рівні з готовими підписами — без відсотків.
class AnalysisResult {
  const AnalysisResult({
    required this.area,
    required this.date,
    required this.forestSummaryLabel,
    required this.forestTypes,
    required this.top1,
    required this.alternative,
    required this.weather,
    required this.warnings,
    required this.usage,
    required this.noDataReason,
    this.forestExtra = const [],
    this.forestRefined = false,
    this.refineNoteLabel,
    this.days = const [],
    this.bestDay,
    this.lockedDays = const [],
    this.lockedLabel,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final forest = req<Map<String, dynamic>>(json, 'forest');
    final top1 = opt<Map<String, dynamic>>(json, 'top1');
    final alt = opt<Map<String, dynamic>>(json, 'alternative');
    final weather = opt<Map<String, dynamic>>(json, 'weather');
    return AnalysisResult(
      area: AnalysisArea.fromJson(req<Map<String, dynamic>>(json, 'area')),
      date: req<String>(json, 'date'),
      forestSummaryLabel: req<String>(forest, 'summary_label'),
      forestTypes: (opt<List<dynamic>>(forest, 'types') ?? const [])
          .map((t) => AnalysisForestType.fromJson(t as Map<String, dynamic>))
          .toList(growable: false),
      forestExtra: (opt<List<dynamic>>(forest, 'extra') ?? const [])
          .map((e) => AnalysisForestExtra.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      forestRefined: opt<bool>(forest, 'refined') ?? false,
      refineNoteLabel: opt<String>(forest, 'refine_note_label'),
      top1: top1 == null ? null : AnalysisSpecies.fromJson(top1),
      alternative: alt == null ? null : AnalysisSpecies.fromJson(alt),
      weather: weather == null ? null : AnalysisWeather.fromJson(weather),
      warnings: stringList(json, 'warnings'),
      usage: AnalysisUsage.fromJson(req<Map<String, dynamic>>(json, 'usage')),
      noDataReason: opt<String>(json, 'no_data_reason'),
      days: (opt<List<dynamic>>(json, 'days') ?? const [])
          .map((d) => AnalysisDay.fromJson(d as Map<String, dynamic>))
          .toList(growable: false),
      bestDay: switch (opt<Map<String, dynamic>>(json, 'best_day')) {
        final b? => (date: req<String>(b, 'date'), label: req<String>(b, 'label')),
        null => null,
      },
      lockedDays: [
        for (final d in (opt<List<dynamic>>(json, 'locked_days') ?? const []).cast<Map<String, dynamic>>())
          (date: req<String>(d, 'date'), dayLabel: req<String>(d, 'day_label')),
      ],
      lockedLabel: opt<String>(json, 'locked_label'),
    );
  }

  /// Результат для іншого дня смужки — ліс і ділянка ті самі, змінюються вид, погода,
  /// застереження. Без запитів: усі дні вже у відповіді.
  AnalysisResult forDay(AnalysisDay day) => AnalysisResult(
        area: area,
        date: day.date,
        forestSummaryLabel: forestSummaryLabel,
        forestTypes: forestTypes,
        forestExtra: forestExtra,
        forestRefined: forestRefined,
        refineNoteLabel: refineNoteLabel,
        top1: day.top1,
        alternative: day.alternative,
        weather: day.weather,
        warnings: day.warnings,
        usage: usage,
        noDataReason: day.noDataReason,
        days: days,
        bestDay: bestDay,
        lockedDays: lockedDays,
        lockedLabel: lockedLabel,
      );

  final AnalysisArea area;
  final String date;
  final String forestSummaryLabel;
  final List<AnalysisForestType> forestTypes;

  /// Породи, додані вручну («Дуб — є місцями»).
  final List<AnalysisForestExtra> forestExtra;

  /// Ліс уточнено вручну (ADR-015 §15.6).
  final bool forestRefined;

  /// «Уточнення діє лише для вашої ділянки…»
  final String? refineNoteLabel;
  final AnalysisSpecies? top1;
  final AnalysisSpecies? alternative;
  final AnalysisWeather? weather;
  final List<String> warnings;
  final AnalysisUsage usage;
  final String? noDataReason;

  /// Дні горизонту (безкоштовно 3, Pro 7); порожньо — старий збережений результат.
  final List<AnalysisDay> days;

  /// «Найкращий день: субота».
  final ({String date, String label})? bestDay;

  /// Дні 4–7 без Pro — лише підписи під замком.
  final List<({String date, String dayLabel})> lockedDays;

  /// «Ще 4 дні прогнозу — у Pro».
  final String? lockedLabel;
}
