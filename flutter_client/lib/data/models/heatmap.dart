import 'json.dart';

/// Клітинка теплової карти (`GET /v1-heatmap`): центр і рівень 1–3 (5–9 / 10–19 / 20+ знахідок).
/// Кількість і точні місця сервер не віддає (ADR-018 §18.5).
class HeatCell {
  const HeatCell({required this.lat, required this.lng, required this.level});

  factory HeatCell.fromJson(Map<String, dynamic> json) => HeatCell(
        lat: toDouble(json['lat'], 'lat'),
        lng: toDouble(json['lng'], 'lng'),
        level: (json['level'] as num?)?.toInt().clamp(1, 3) ?? 1,
      );

  final double lat;
  final double lng;
  final int level;
}

/// Теплова карта знахідок (B3.5, ADR-010): лише підтверджені публічні точки, клітинки ≈ 1 км.
class Heatmap {
  const Heatmap({
    required this.cells,
    required this.cellLat,
    required this.cellLng,
    required this.periodDays,
    required this.scope,
    required this.canChangePeriod,
    required this.legendLabel,
    this.scopeLabel,
  });

  factory Heatmap.fromJson(Map<String, dynamic> json) => Heatmap(
        cells: [
          for (final e in (opt<List<dynamic>>(json, 'cells') ?? const []).cast<Map<String, dynamic>>()) HeatCell.fromJson(e),
        ],
        cellLat: toDouble(json['cell_lat'], 'cell_lat'),
        cellLng: toDouble(json['cell_lng'], 'cell_lng'),
        periodDays: (json['period_days'] as num?)?.toInt() ?? 3,
        scope: opt<String>(json, 'scope') ?? 'home',
        scopeLabel: opt<String>(json, 'scope_label'),
        canChangePeriod: json['can_change_period'] == true,
        legendLabel: opt<String>(json, 'legend_label') ?? '',
      );

  final List<HeatCell> cells;
  final double cellLat;
  final double cellLng;
  final int periodDays;

  /// `home` · `neighbours` · `ukraine`.
  final String scope;
  final String? scopeLabel;

  /// Чи доступні 7 і 30 днів («Майстер» або Pro).
  final bool canChangePeriod;
  final String legendLabel;

  /// «Ваша область · за 3 дні».
  String get summaryLabel => [
        if (scopeLabel != null) scopeLabel!,
        'за $periodDays ${periodDays == 3 ? 'дні' : 'днів'}',
      ].join(' · ');

  /// Клітинки як прямокутники GeoJSON (рівень — властивість для кольору шару).
  Map<String, dynamic> toGeoJson() => {
        'type': 'FeatureCollection',
        'features': [
          for (final c in cells)
            {
              'type': 'Feature',
              'properties': {'level': c.level},
              'geometry': {
                'type': 'Polygon',
                'coordinates': [
                  [
                    [c.lng - cellLng / 2, c.lat - cellLat / 2],
                    [c.lng + cellLng / 2, c.lat - cellLat / 2],
                    [c.lng + cellLng / 2, c.lat + cellLat / 2],
                    [c.lng - cellLng / 2, c.lat + cellLat / 2],
                    [c.lng - cellLng / 2, c.lat - cellLat / 2],
                  ],
                ],
              },
            },
        ],
      };
}
