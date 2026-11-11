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

/// Збережена ділянка користувача.
class AnalysisArea {
  const AnalysisArea({
    required this.id,
    required this.center,
    required this.sizeKm,
    required this.sizeLabel,
    this.bounds,
  });

  factory AnalysisArea.fromJson(Map<String, dynamic> json) {
    final bbox = opt<List<dynamic>>(json, 'bbox');
    return AnalysisArea(
      id: req<String>(json, 'id'),
      center: LatLng(toDouble(json['lat'], 'lat'), toDouble(json['lng'], 'lng')),
      sizeKm: req<num>(json, 'size_km').toInt(),
      sizeLabel: req<String>(json, 'size_label'),
      bounds: bbox == null ? null : GeoBounds.fromBbox(bbox),
    );
  }

  final String id;
  final LatLng center;
  final int sizeKm;
  final String sizeLabel;

  /// Точні межі квадрата, який проаналізував сервер (є у відповіді аналізу).
  final GeoBounds? bounds;
}

/// Відповідь `GET /v1-analysis`: що доступно і що вже збережено.
class AnalysisOverview {
  const AnalysisOverview({
    required this.sizes,
    required this.areas,
    required this.usage,
    required this.hintLabel,
  });

  factory AnalysisOverview.fromJson(Map<String, dynamic> json) => AnalysisOverview(
        sizes: (opt<List<dynamic>>(json, 'sizes') ?? const [])
            .map((s) => AnalysisSizeOption.fromJson(s as Map<String, dynamic>))
            .toList(growable: false),
        areas: (opt<List<dynamic>>(json, 'areas') ?? const [])
            .map((a) => AnalysisArea.fromJson(a as Map<String, dynamic>))
            .toList(growable: false),
        usage: AnalysisUsage.fromJson(req<Map<String, dynamic>>(json, 'usage')),
        hintLabel: req<String>(json, 'hint_label'),
      );

  final List<AnalysisSizeOption> sizes;
  final List<AnalysisArea> areas;
  final AnalysisUsage usage;
  final String hintLabel;
}

/// Тип лісу в ділянці: підпис, колір і площа — із сервера.
class AnalysisForestType {
  const AnalysisForestType({
    required this.typeLabel,
    required this.typeColor,
    required this.areaLabel,
    required this.ageLabel,
  });

  factory AnalysisForestType.fromJson(Map<String, dynamic> json) => AnalysisForestType(
        typeLabel: req<String>(json, 'type_label'),
        typeColor: parseHexColor(req<String>(json, 'type_color')),
        areaLabel: req<String>(json, 'area_label'),
        ageLabel: opt<String>(json, 'age_label'),
      );

  final String typeLabel;
  final Color typeColor;
  final String areaLabel;
  final String? ageLabel;
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
  });

  factory AnalysisWeather.fromJson(Map<String, dynamic> json) => AnalysisWeather(
        icon: req<String>(json, 'icon'),
        tempLabel: req<String>(json, 'temp_label'),
        humidityLabel: req<String>(json, 'humidity_label'),
        rainLabel: req<String>(json, 'rain_label'),
      );

  final String icon;
  final String tempLabel;
  final String humidityLabel;
  final String rainLabel;
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
      top1: top1 == null ? null : AnalysisSpecies.fromJson(top1),
      alternative: alt == null ? null : AnalysisSpecies.fromJson(alt),
      weather: weather == null ? null : AnalysisWeather.fromJson(weather),
      warnings: stringList(json, 'warnings'),
      usage: AnalysisUsage.fromJson(req<Map<String, dynamic>>(json, 'usage')),
      noDataReason: opt<String>(json, 'no_data_reason'),
    );
  }

  final AnalysisArea area;
  final String date;
  final String forestSummaryLabel;
  final List<AnalysisForestType> forestTypes;
  final AnalysisSpecies? top1;
  final AnalysisSpecies? alternative;
  final AnalysisWeather? weather;
  final List<String> warnings;
  final AnalysisUsage usage;
  final String? noDataReason;
}
