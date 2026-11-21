import 'json.dart';

/// Трофей-медальйон (ADR-021 §21.10): за що й скільки — із сервера; картинка — у застосунку
/// (`assets/trophies/{large,small}/<id>.webp`).
class Trophy {
  const Trophy({
    required this.id,
    required this.title,
    required this.tier,
    required this.tierLabel,
    required this.howLabel,
    required this.earned,
    this.earnedAt,
    this.progressLabel,
    this.progress = 0,
    this.soon = false,
  });

  factory Trophy.fromJson(Map<String, dynamic> j) => Trophy(
        id: req<String>(j, 'id'),
        title: req<String>(j, 'title'),
        tier: opt<String>(j, 'tier') ?? 'bronze',
        tierLabel: opt<String>(j, 'tier_label') ?? '',
        howLabel: opt<String>(j, 'how_label') ?? '',
        earned: opt<bool>(j, 'earned') ?? false,
        earnedAt: DateTime.tryParse(opt<String>(j, 'earned_at') ?? '')?.toLocal(),
        progressLabel: opt<String>(j, 'progress_label'),
        progress: (opt<num>(j, 'progress') ?? 0).toDouble().clamp(0, 1),
        soon: opt<bool>(j, 'soon') ?? false,
      );

  final String id;
  final String title;

  /// bronze | silver | gold
  final String tier;
  final String tierLabel;

  /// За що (і скільки) — текст із сервера.
  final String howLabel;
  final bool earned;
  final DateTime? earnedAt;

  /// «3 з 10» — поки не отримано.
  final String? progressLabel;
  final double progress;

  /// Функції ще немає (запрошення, тести знань) — закритий «скоро».
  final bool soon;

  String get smallAsset => 'assets/trophies/small/$id.webp';
  String get largeAsset => 'assets/trophies/large/$id.webp';
}

/// `GET /v1-me?trophies=1`.
class TrophiesOverview {
  const TrophiesOverview({required this.trophies, required this.earnedCount, required this.total, this.newLabels = const []});

  factory TrophiesOverview.fromJson(Map<String, dynamic> j) => TrophiesOverview(
        trophies: [for (final t in (opt<List<dynamic>>(j, 'trophies') ?? const []).cast<Map<String, dynamic>>()) Trophy.fromJson(t)],
        earnedCount: (opt<num>(j, 'earned_count') ?? 0).toInt(),
        total: (opt<num>(j, 'total') ?? 0).toInt(),
        newLabels: [for (final s in opt<List<dynamic>>(j, 'new_labels') ?? const []) s as String],
      );

  final List<Trophy> trophies;
  final int earnedCount;
  final int total;

  /// «Новий трофей: «…»» — щойно отримані (показати підказкою).
  final List<String> newLabels;
}
