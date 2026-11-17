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
    this.label,
    this.serverTitle,
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
      label: opt<String>(json, 'label'),
      serverTitle: opt<String>(json, 'title'),
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

  /// Власна назва від грибника («Біля Броників»); `null` — «Ділянка N».
  final String? label;

  /// Готовий підпис клітинки із сервера.
  final String? serverTitle;

  /// «Біля Броників» або «Ділянка 1».
  String get title => serverTitle ?? ((label?.trim().isNotEmpty ?? false) ? label!.trim() : 'Ділянка $slot');
}

/// Клітинка ділянки у «Прогнозі» (ADR-015 §15.9): зайнята, вільна (Pro) або під замком.
enum AnalysisSlotState { area, empty, locked }

class AnalysisSlot {
  const AnalysisSlot({
    required this.slot,
    required this.state,
    required this.title,
    this.areaId,
    this.subtitle,
    this.lockedLabel,
  });

  factory AnalysisSlot.fromJson(Map<String, dynamic> json) => AnalysisSlot(
        slot: req<num>(json, 'slot').toInt(),
        state: switch (opt<String>(json, 'state')) {
          'area' => AnalysisSlotState.area,
          'empty' => AnalysisSlotState.empty,
          _ => AnalysisSlotState.locked,
        },
        title: req<String>(json, 'title'),
        areaId: opt<String>(json, 'area_id'),
        subtitle: opt<String>(json, 'subtitle'),
        lockedLabel: opt<String>(json, 'locked_label'),
      );

  final int slot;
  final AnalysisSlotState state;

  /// «Ділянка 1» / «Біля Броників» / «Нова ділянка».
  final String title;
  final String? areaId;

  /// «5×5 км».
  final String? subtitle;

  /// «Ще 2 ділянки — у Pro».
  final String? lockedLabel;
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
    List<AnalysisSlot>? slots,
    this.labelMax = 24,
  }) : _slots = slots;

  factory AnalysisOverview.fromJson(Map<String, dynamic> json, {DateTime? offlineSince}) => AnalysisOverview(
        slots: switch (opt<List<dynamic>>(json, 'slots')) {
          final list? => [for (final s in list.cast<Map<String, dynamic>>()) AnalysisSlot.fromJson(s)],
          null => null,
        },
        labelMax: opt<num>(json, 'label_max')?.toInt() ?? 24,
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

  /// Найдовша назва ділянки (символів) — каже сервер.
  final int labelMax;

  final List<AnalysisSlot>? _slots;

  /// Три клітинки ділянок. Старий збережений офлайн-знімок без `slots` — збираємо з ділянок.
  List<AnalysisSlot> get slots {
    if (_slots case final s? when s.isNotEmpty) return s;
    return [
      for (var slot = 1; slot <= 3; slot++)
        switch (areas.where((a) => a.slot == slot).firstOrNull) {
          final a? => AnalysisSlot(
              slot: slot, state: AnalysisSlotState.area, areaId: a.id, title: a.title, subtitle: a.sizeLabel),
          null when canCreate => AnalysisSlot(slot: slot, state: AnalysisSlotState.empty, title: 'Нова ділянка'),
          null => AnalysisSlot(
              slot: slot,
              state: AnalysisSlotState.locked,
              title: 'Ділянка $slot',
              lockedLabel: 'Ще 2 ділянки — у Pro',
            ),
        },
    ];
  }

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
    this.verdictLabel,
    this.verdictTone,
    this.scene,
    this.sceneLabel,
    this.sprouts,
    this.rangeLabel,
    this.sunLabel,
    this.takeLabel,
    this.parts = const [],
    this.rainSpans = const [],
    this.dryRestLabel,
  });

  factory AnalysisWeather.fromJson(Map<String, dynamic> json) => AnalysisWeather(
        icon: req<String>(json, 'icon'),
        tempLabel: req<String>(json, 'temp_label'),
        humidityLabel: req<String>(json, 'humidity_label'),
        rainLabel: req<String>(json, 'rain_label'),
        dayLabel: opt<String>(json, 'day_label'),
        verdictLabel: opt<String>(json, 'verdict_label'),
        verdictTone: opt<String>(json, 'verdict_tone'),
        scene: opt<String>(json, 'scene'),
        sceneLabel: opt<String>(json, 'scene_label'),
        sprouts: opt<String>(json, 'sprouts'),
        rangeLabel: opt<String>(json, 'range_label'),
        sunLabel: opt<String>(json, 'sun_label'),
        takeLabel: opt<String>(json, 'take_label'),
        parts: [
          for (final p in (opt<List<dynamic>>(json, 'parts') ?? const []).cast<Map<String, dynamic>>())
            WeatherPart.fromJson(p),
        ],
        rainSpans: [
          for (final p in (opt<List<dynamic>>(json, 'rain_spans') ?? const []).cast<Map<String, dynamic>>())
            (
              fromHour: req<num>(p, 'from_hour').toInt(),
              toHour: req<num>(p, 'to_hour').toInt(),
              label: req<String>(p, 'label'),
            ),
        ],
        dryRestLabel: opt<String>(json, 'dry_rest_label'),
      );

  /// Ніч / ранок / день / вечір зі своєю сценою; порожньо — старий результат.
  final List<WeatherPart> parts;

  /// Проміжки опадів доби: «Дощ 18:00–21:00, ~5 мм».
  final List<({int fromHour, int toHour, String label})> rainSpans;

  /// «Далі сьогодні без опадів» — коли всі проміжки вже минули.
  final String? dryRestLabel;

  /// Частина доби, що триває о [hour]; немає годин — `null`.
  WeatherPart? partAt(int hour) {
    for (final p in parts) {
      if (hour >= p.fromHour && hour < p.toHour) return p;
    }
    return null;
  }

  /// Що з опадів ще попереду (для сьогодні — від [hour]; для інших днів — усе): підписи сервера.
  String? rainAhead(int? hour) {
    final left = [for (final s in rainSpans) if (hour == null || s.toHour > hour) s.label];
    if (left.isNotEmpty) return left.join(' · ');
    return rainSpans.isNotEmpty && hour != null ? dryRestLabel : null;
  }

  /// «Схід 07:12 · захід 16:08 · світла 8 год 56 хв».
  final String? sunLabel;

  /// «Візьміть: дощовик, гумові чоботи…».
  final String? takeLabel;

  /// Дні 5–7: «Різні моделі: опади 2–11 мм, 3…10°».
  final String? rangeLabel;

  /// Сцена з грибом-маскотом: `sunny | partly_cloudy | cloudy | rain | heavy_rain | fog | frost | snow | heat`.
  final String? scene;

  /// «Мінлива хмарність».
  final String? sceneLabel;

  /// Молоді гриби в сцені: `none | few | many`.
  final String? sprouts;

  /// Що погода означає для грибів: «Ґрунт вологий після дощів — добре для грибів».
  final String? verdictLabel;

  /// `good | neutral | bad`
  final String? verdictTone;

  /// Погода самого дня: «4…11°, опади 8 мм».
  final String? dayLabel;
  final String icon;
  final String tempLabel;
  final String humidityLabel;
  final String rainLabel;
}

/// Частина доби (рішення PO 2026-11-17): сцена й температура з погодинного прогнозу.
class WeatherPart {
  const WeatherPart({
    required this.key,
    required this.label,
    required this.fromHour,
    required this.toHour,
    required this.scene,
    required this.sceneLabel,
    required this.tempLabel,
  });

  factory WeatherPart.fromJson(Map<String, dynamic> json) => WeatherPart(
        key: req<String>(json, 'key'),
        label: req<String>(json, 'label'),
        fromHour: req<num>(json, 'from_hour').toInt(),
        toHour: req<num>(json, 'to_hour').toInt(),
        scene: req<String>(json, 'scene'),
        sceneLabel: req<String>(json, 'scene_label'),
        tempLabel: req<String>(json, 'temp_label'),
      );

  /// `night | morning | day | evening`
  final String key;

  /// «Ранок»
  final String label;
  final int fromHour, toHour;
  final String scene;

  /// «Сонячно»
  final String sceneLabel;

  /// «5…11°»
  final String tempLabel;
}

/// «Розширені дані погоди» (рішення PO 2026-11-15): дощ → гриби, що сталося, шкали, що далі.
/// Усі підписи — із сервера; числа — лише мм опадів і частки шкал.
class WeatherInsight {
  const WeatherInsight({
    required this.days,
    required this.events,
    required this.gauges,
    this.stripTitle,
    this.wave,
    this.legend = const {},
    this.eventsTitle,
    this.outlookTitle,
    this.outlookLabel,
  });

  factory WeatherInsight.fromJson(Map<String, dynamic> json) => WeatherInsight(
        stripTitle: opt<String>(json, 'strip_title'),
        days: [
          for (final d in (opt<List<dynamic>>(json, 'days') ?? const []).cast<Map<String, dynamic>>())
            InsightDay(
              date: req<String>(d, 'date'),
              label: req<String>(d, 'label'),
              dateLabel: opt<String>(d, 'date_label') ?? '',
              rain: toDouble(d['rain'], 'rain'),
              soaking: opt<bool>(d, 'soaking') ?? false,
              temp: opt<String>(d, 'temp') ?? 'ok',
              forecast: opt<bool>(d, 'forecast') ?? false,
              today: opt<bool>(d, 'today') ?? false,
            ),
        ],
        wave: switch (opt<Map<String, dynamic>>(json, 'wave')) {
          final w? => (from: req<String>(w, 'from'), to: opt<String>(w, 'to'), label: req<String>(w, 'label')),
          null => null,
        },
        legend: {
          for (final e in (opt<Map<String, dynamic>>(json, 'legend_labels') ?? const {}).entries)
            if (e.value is String) e.key: e.value as String,
        },
        eventsTitle: opt<String>(json, 'events_title'),
        events: [
          for (final e in (opt<List<dynamic>>(json, 'events') ?? const []).cast<Map<String, dynamic>>())
            (icon: opt<String>(e, 'icon') ?? '', label: req<String>(e, 'label')),
        ],
        gauges: [
          for (final g in (opt<List<dynamic>>(json, 'gauges') ?? const []).cast<Map<String, dynamic>>())
            InsightGauge(
              key: req<String>(g, 'key'),
              title: req<String>(g, 'title'),
              steps: g['steps'] == null ? const [] : stringList(g, 'steps'),
              index: opt<num>(g, 'index')?.toInt(),
              hint: opt<String>(g, 'hint'),
              valueLabel: opt<String>(g, 'value_label'),
              fill: opt<num>(g, 'fill')?.toDouble(),
              mark: opt<num>(g, 'mark')?.toDouble(),
              markLabel: opt<String>(g, 'mark_label'),
              tone: opt<String>(g, 'tone') ?? 'neutral',
            ),
        ],
        outlookTitle: opt<String>(json, 'outlook_title'),
        outlookLabel: opt<String>(json, 'outlook_label'),
      );

  final String? stripTitle;
  final List<InsightDay> days;

  /// Вікно хвилі найкращого виду: «Зимовий опеньок: гриби 13.11–02.12».
  final ({String from, String? to, String label})? wave;

  /// Підписи легенди: `soaking`, `frost`, `cold`, `ok`, `hot`.
  final Map<String, String> legend;
  final String? eventsTitle;
  final List<({String icon, String label})> events;
  final List<InsightGauge> gauges;
  final String? outlookTitle;
  final String? outlookLabel;
}

class InsightDay {
  const InsightDay({
    required this.date,
    required this.label,
    required this.dateLabel,
    required this.rain,
    required this.soaking,
    required this.temp,
    required this.forecast,
    required this.today,
  });

  final String date;
  final String label;
  final String dateLabel;

  /// Опади за добу, мм.
  final double rain;

  /// Дощ промочив ґрунт (поштовх для грибів).
  final bool soaking;

  /// `frost | cold | ok | hot`
  final String temp;
  final bool forecast;
  final bool today;
}

/// Шкала: кроки (сухо · норма · волого…) з позначкою [index] або смужка [fill] з межею [mark].
class InsightGauge {
  const InsightGauge({
    required this.key,
    required this.title,
    required this.tone,
    this.steps = const [],
    this.index,
    this.hint,
    this.valueLabel,
    this.fill,
    this.mark,
    this.markLabel,
  });

  final String key;
  final String title;
  final List<String> steps;
  final int? index;
  final String? hint;
  final String? valueLabel;
  final double? fill;
  final double? mark;
  final String? markLabel;

  /// `good | neutral | bad`
  final String tone;
}

/// Гриб у кошику мінікарти: вид зі шансом на день (ADR-015 §15.9). Лише підписи із сервера.
class AnalysisBasketSpecies {
  const AnalysisBasketSpecies({
    required this.type,
    required this.name,
    required this.level,
    required this.levelLabel,
    required this.levelColor,
    required this.whenLabel,
  });

  factory AnalysisBasketSpecies.fromJson(Map<String, dynamic> json) => AnalysisBasketSpecies(
        type: req<String>(json, 'mushroom_type'),
        name: req<String>(json, 'name_ua'),
        level: req<String>(json, 'level'),
        levelLabel: req<String>(json, 'level_label'),
        levelColor: parseHexColor(req<String>(json, 'level_color')),
        whenLabel: opt<String>(json, 'when_label') ?? '',
      );

  final String type;
  final String name;
  final String level;
  final String levelLabel;
  final Color levelColor;
  final String whenLabel;
}

/// «Інші гриби сезону»: вид без шансу цього дня і чому (рішення PO 2026-11-15).
/// [group]: `today` — у сезоні, але сьогодні без шансу; `season` — сезон минув / ще не почався.
typedef OtherSpecies = ({String type, String name, String reason, String group});

List<OtherSpecies> _others(Map<String, dynamic> json) => [
      for (final o in (opt<List<dynamic>>(json, 'others') ?? const []).cast<Map<String, dynamic>>())
        (
          type: req<String>(o, 'mushroom_type'),
          name: req<String>(o, 'name_ua'),
          reason: opt<String>(o, 'reason_label') ?? '',
          group: opt<String>(o, 'group') ?? 'today',
        ),
    ];

/// Знахідки в ділянці: звірка ваших тук-туків із прогнозом і ваші знахідки торік у ці тижні.
class AreaFinds {
  const AreaFinds({this.verificationLabel, this.lastYear = const [], this.lastYearLabel});

  factory AreaFinds.fromJson(Map<String, dynamic> json) => AreaFinds(
        verificationLabel: opt<String>(json, 'verification_label'),
        lastYearLabel: opt<String>(json, 'last_year_label'),
        lastYear: [
          for (final f in (opt<List<dynamic>>(json, 'last_year') ?? const []).cast<Map<String, dynamic>>())
            (
              point: LatLng(toDouble(f['lat'], 'lat'), toDouble(f['lng'], 'lng')),
              type: opt<String>(f, 'mushroom_type') ?? '',
              name: opt<String>(f, 'name') ?? 'Гриб',
              dateLabel: opt<String>(f, 'date_label') ?? '',
            ),
        ],
      );

  /// «Ваші знахідки тут збіглися з прогнозом: 2 з 3».
  final String? verificationLabel;
  final List<PastFind> lastYear;

  /// «Торік у ці тижні: 3 знахідки».
  final String? lastYearLabel;
}

typedef PastFind = ({LatLng point, String type, String name, String dateLabel});

/// Версія результату, яку очікує застосунок: старіший результат оновлюється безкоштовно.
const kExpectedResultVersion = 5;

List<AnalysisBasketSpecies>? _basket(Map<String, dynamic> json) => switch (opt<List<dynamic>>(json, 'basket')) {
      final list? => [for (final b in list.cast<Map<String, dynamic>>()) AnalysisBasketSpecies.fromJson(b)],
      null => null,
    };

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
    this.basket,
    this.others = const [],
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
      basket: _basket(json),
      others: _others(json),
    );
  }

  /// «Інші гриби сезону» цього дня.
  final List<OtherSpecies> others;

  /// Усі гриби зі шансом цього дня; `null` — старий збережений результат.
  final List<AnalysisBasketSpecies>? basket;

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
    this.terrainLabel,
    this.days = const [],
    this.bestDay,
    this.lockedDays = const [],
    this.lockedLabel,
    this.basket,
    this.weekAnimation,
    this.weatherInsight,
    this.others = const [],
    this.identify = const {},
    this.resultVersion = 0,
    this.finds,
    this.weatherFreshUntil,
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
      terrainLabel: opt<String>(forest, 'terrain_label'),
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
      basket: _basket(json),
      weekAnimation: switch (opt<Map<String, dynamic>>(json, 'week_animation')) {
        final w? => (allowed: opt<bool>(w, 'allowed') ?? false, lockedLabel: opt<String>(w, 'locked_label')),
        null => null,
      },
      others: _others(json),
      identify: {
        for (final e in (opt<Map<String, dynamic>>(json, 'identify') ?? const {}).entries)
          if (e.value is Map<String, dynamic>) e.key: IdentifyCard.fromJson(e.value as Map<String, dynamic>),
      },
      resultVersion: opt<num>(json, 'result_version')?.toInt() ?? 0,
      weatherFreshUntil: DateTime.tryParse(opt<String>(json, 'weather_fresh_until') ?? ''),
      finds: switch (opt<Map<String, dynamic>>(json, 'finds')) {
        final f? => AreaFinds.fromJson(f),
        null => null,
      },
      weatherInsight: switch (opt<Map<String, dynamic>>(json, 'weather_insight')) {
        final c? => WeatherInsight.fromJson(c),
        null => null,
      },
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
        terrainLabel: terrainLabel,
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
        basket: day.basket,
        weekAnimation: weekAnimation,
        weatherInsight: weatherInsight,
        others: day.others,
        identify: identify,
        resultVersion: resultVersion,
        finds: finds,
        weatherFreshUntil: weatherFreshUntil,
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

  /// «Рельєф: низина — … · Ґрунт: піщаний — …»; `null` — невідомо.
  final String? terrainLabel;
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

  /// Гриби зі шансом обраного дня — кошик мінікарти; `null` — старий результат.
  final List<AnalysisBasketSpecies>? basket;

  /// ▶ «Хвиля по днях»: Pro або «Слідопит»; інакше — пояснення при натисканні.
  final ({bool allowed, String? lockedLabel})? weekAnimation;

  /// «Розширені дані погоди»; `null` — старий результат.
  final WeatherInsight? weatherInsight;

  /// «Інші гриби сезону» обраного дня — після натискання кнопки.
  final List<OtherSpecies> others;

  /// «Як відрізнити» — один раз на вид.
  final Map<String, IdentifyCard> identify;

  /// Версія результату із сервера; менша за [kExpectedResultVersion] — оновлюється безкоштовно.
  final int resultVersion;

  /// Знахідки в ділянці (звірка з прогнозом, торішні); `null` — старий результат.
  final AreaFinds? finds;

  /// Аналіз не на сьогодні або зроблений до оновлення застосунку.
  bool isStale(String today) => date.compareTo(today) < 0 || resultVersion < kExpectedResultVersion;

  /// Відколи погоду можна оновити безкоштовно (`refresh: "weather"`, раз на 3 год); `null` — старий результат.
  final DateTime? weatherFreshUntil;

  /// Погоді понад 3 години — оновити (гриби лишаються).
  bool weatherStale(DateTime now) => weatherFreshUntil != null && !now.isBefore(weatherFreshUntil!);
}
