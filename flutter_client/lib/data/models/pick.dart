import 'dart:ui' show Color;

import 'package:latlong2/latlong.dart';

import 'forest_zone.dart' show parseHexColor;
import 'json.dart';

/// Видимість тук-тука (ADR-018): лише приватна або публічна.
enum PickVisibility {
  private('private'),
  public('public');

  const PickVisibility(this.wire);
  final String wire;

  static PickVisibility parse(String value) =>
      value == 'public' ? PickVisibility.public : PickVisibility.private;
}

/// Точка на карті (`GET /v1-picks/map`). Підпис і колір — із сервера.
///
/// Для чужих точок [point] — зсунуте місце (300–500 м), для власних — точне
/// ([isExact]). Точні координати чужих точок сервер не віддає ніколи.
class MapPick {
  const MapPick({
    required this.id,
    required this.point,
    required this.isExact,
    required this.isMine,
    required this.visibility,
    required this.speciesId,
    required this.nameLabel,
    required this.statusLabel,
    required this.markerColor,
  });

  factory MapPick.fromJson(Map<String, dynamic> json) => MapPick(
        id: req<String>(json, 'id'),
        point: LatLng(toDouble(json['lat'], 'lat'), toDouble(json['lng'], 'lng')),
        isExact: req<bool>(json, 'is_exact'),
        isMine: req<bool>(json, 'is_mine'),
        visibility: PickVisibility.parse(req<String>(json, 'visibility')),
        speciesId: opt<String>(json, 'species_id'),
        nameLabel: req<String>(json, 'name_label'),
        statusLabel: req<String>(json, 'status_label'),
        markerColor: parseHexColor(req<String>(json, 'marker_color')),
      );

  final String id;
  final LatLng point;
  final bool isExact;
  final bool isMine;
  final PickVisibility visibility;
  final String? speciesId;
  final String nameLabel;
  final String statusLabel;
  final Color markerColor;
}

/// Відповідь `GET /v1-picks/map`.
class PicksMap {
  const PicksMap({required this.points, required this.truncated});

  factory PicksMap.fromJson(Map<String, dynamic> json) => PicksMap(
        points: (opt<List<dynamic>>(json, 'points') ?? const [])
            .map((p) => MapPick.fromJson(p as Map<String, dynamic>))
            .toList(growable: false),
        truncated: opt<bool>(json, 'truncated') ?? false,
      );

  static const empty = PicksMap(points: [], truncated: false);

  final List<MapPick> points;

  /// Точок більше, ніж вмістила відповідь — показано найновіші.
  final bool truncated;
}

/// Картка точки (`GET /v1-picks/{id}`): фото, назва, опис, дата, статус.
class PickCard {
  const PickCard({
    required this.pick,
    required this.description,
    required this.dateLabel,
    required this.photoUrl,
    required this.disclaimerLabel,
    required this.actions,
  });

  factory PickCard.fromJson(Map<String, dynamic> json) => PickCard(
        pick: MapPick.fromJson(json),
        description: opt<String>(json, 'description'),
        dateLabel: opt<String>(json, 'date_label'),
        photoUrl: opt<String>(json, 'photo_url'),
        disclaimerLabel: opt<String>(json, 'disclaimer_label'),
        actions: stringList(json, 'actions'),
      );

  final MapPick pick;
  final String? description;
  final String? dateLabel;

  /// Тимчасове посилання на фото (діє кілька хвилин).
  final String? photoUrl;

  /// «Фото користувача — не порада їсти гриб» — для публічних точок.
  final String? disclaimerLabel;

  /// Дозволені дії — клієнт показує лише їх.
  final List<String> actions;
}

/// Вид із довідника для вибору назви тук-тука.
class PickSpecies {
  const PickSpecies({required this.id, required this.nameLabel, required this.latinLabel});

  factory PickSpecies.fromJson(Map<String, dynamic> json) => PickSpecies(
        id: req<String>(json, 'id'),
        nameLabel: req<String>(json, 'name_label'),
        latinLabel: opt<String>(json, 'latin_label'),
      );

  final String id;
  final String nameLabel;
  final String? latinLabel;

  /// Пошук за українською або латинською назвою (без урахування регістру).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return nameLabel.toLowerCase().contains(q) || (latinLabel?.toLowerCase().contains(q) ?? false);
  }
}

/// Відповідь `GET /v1-picks/species`.
class SpeciesList {
  const SpeciesList({required this.species, required this.unknownLabel});

  factory SpeciesList.fromJson(Map<String, dynamic> json) => SpeciesList(
        species: (opt<List<dynamic>>(json, 'species') ?? const [])
            .map((s) => PickSpecies.fromJson(s as Map<String, dynamic>))
            .toList(growable: false),
        unknownLabel: req<String>(json, 'unknown_label'),
      );

  final List<PickSpecies> species;

  /// «Не знаю, що це» — така точка може бути лише приватною.
  final String unknownLabel;
}

/// Фото для завантаження: читається потоком з диска, без копії в пам'яті.
class PickPhoto {
  const PickPhoto({required this.openRead, required this.sizeBytes, required this.contentType});

  final Stream<List<int>> Function() openRead;
  final int sizeBytes;

  /// `image/jpeg`, `image/png` або `image/webp`.
  final String contentType;

  /// Тип за розширенням файлу; невідоме розширення вважаємо JPEG (камера знімає в JPEG).
  static String contentTypeForPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

/// Дані нового тук-тука (`POST /v1-picks`).
class NewPick {
  const NewPick({
    required this.clientId,
    required this.point,
    required this.capturedAt,
    required this.visibility,
    required this.speciesId,
    this.description,
  });

  /// UUID від клієнта: повтор із тим самим id повертає ту саму точку.
  final String clientId;
  final LatLng point;
  final DateTime capturedAt;
  final PickVisibility visibility;

  /// `null` — «Не знаю, що це» (лише для приватної точки).
  final String? speciesId;
  final String? description;
}

/// Відповідь `POST /v1-picks`.
class CreatedPick {
  const CreatedPick({
    required this.id,
    required this.visibility,
    required this.statusLabel,
    required this.markerColor,
  });

  factory CreatedPick.fromJson(Map<String, dynamic> json) => CreatedPick(
        id: req<String>(json, 'id'),
        visibility: PickVisibility.parse(req<String>(json, 'visibility')),
        statusLabel: req<String>(json, 'status_label'),
        markerColor: parseHexColor(req<String>(json, 'marker_color')),
      );

  final String id;
  final PickVisibility visibility;
  final String statusLabel;
  final Color markerColor;
}
