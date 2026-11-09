import 'dart:ui' show Color;

import 'forest_zone.dart' show parseHexColor;
import 'json.dart';

/// Вид у прогнозі. Лише рівень і готові підписи — без числових ймовірностей (маніфест).
class ForecastSpecies {
  const ForecastSpecies({
    required this.mushroomType,
    required this.nameUa,
    required this.level,
    required this.levelLabel,
    required this.levelColor,
    required this.whenLabel,
    required this.whereLabel,
    required this.whyLabels,
  });

  factory ForecastSpecies.fromJson(Map<String, dynamic> json) => ForecastSpecies(
        mushroomType: req<String>(json, 'mushroom_type'),
        nameUa: req<String>(json, 'name_ua'),
        level: req<String>(json, 'level'),
        levelLabel: req<String>(json, 'level_label'),
        levelColor: parseHexColor(req<String>(json, 'level_color')),
        whenLabel: req<String>(json, 'when_label'),
        whereLabel: req<String>(json, 'where_label'),
        whyLabels: stringList(json, 'why_labels'),
      );

  final String mushroomType;
  final String nameUa;

  /// `peak | high | medium | low | no_data` — для іконок/тестів; текст — [levelLabel].
  final String level;
  final String levelLabel;
  final Color levelColor;
  final String whenLabel;
  final String whereLabel;
  final List<String> whyLabels;
}

/// Відповідь `POST /v1-forecast`.
class Forecast {
  const Forecast({
    required this.regionName,
    required this.date,
    required this.forest,
    required this.top1,
    required this.alternative,
    required this.warnings,
    required this.noDataReason,
  });

  factory Forecast.fromJson(Map<String, dynamic> json) {
    final top1 = opt<Map<String, dynamic>>(json, 'top1');
    final alt = opt<Map<String, dynamic>>(json, 'alternative');
    return Forecast(
      regionName: opt<String>(json, 'regionName'),
      date: req<String>(json, 'date'),
      forest: req<String>(json, 'forest'),
      top1: top1 == null ? null : ForecastSpecies.fromJson(top1),
      alternative: alt == null ? null : ForecastSpecies.fromJson(alt),
      warnings: stringList(json, 'warnings'),
      noDataReason: opt<String>(json, 'noDataReason'),
    );
  }

  final String? regionName;
  final String date;
  final String forest;
  final ForecastSpecies? top1;
  final ForecastSpecies? alternative;
  final List<String> warnings;
  final String? noDataReason;
}
