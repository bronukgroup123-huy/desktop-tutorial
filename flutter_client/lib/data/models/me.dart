import 'json.dart';

/// Наступний крок онбордингу — вирішує сервер (`GET /v1-me` → onboarding.next_step).
enum OnboardingStep {
  selectRegion('select_region'),
  acceptTerms('accept_terms'),

  /// Після входу через Google / Apple — ім'я й нік (ADR-021 §21.2.1).
  profile('profile'),
  done('done'),

  /// Невідомий новий крок із сервера — клієнт показує онбординг, а не пропускає його.
  unknown('');

  const OnboardingStep(this.wire);
  final String wire;

  static OnboardingStep parse(String value) =>
      values.firstWhere((s) => s.wire == value && s != unknown, orElse: () => unknown);
}

class HomeRegion {
  const HomeRegion({required this.id, required this.slug, required this.name});

  factory HomeRegion.fromJson(Map<String, dynamic> json) => HomeRegion(
        id: req<int>(json, 'id'),
        slug: req<String>(json, 'slug'),
        name: req<String>(json, 'name'),
      );

  /// Лише для локального кешу. На сервер завжди відправляємо [slug].
  final int id;
  final String slug;
  final String name;
}

class Onboarding {
  const Onboarding({
    required this.regionDone,
    required this.termsDone,
    required this.termsVersion,
    required this.nextStep,
    required this.nextStepLabel,
  });

  factory Onboarding.fromJson(Map<String, dynamic> json) => Onboarding(
        regionDone: req<bool>(json, 'region_done'),
        termsDone: req<bool>(json, 'terms_done'),
        termsVersion: req<String>(json, 'terms_version'),
        nextStep: OnboardingStep.parse(req<String>(json, 'next_step')),
        nextStepLabel: req<String>(json, 'next_step_label'),
      );

  final bool regionDone;
  final bool termsDone;

  /// Версію умов відправляємо назад у `PATCH /v1-me { accept_terms_version }`.
  final String termsVersion;
  final OnboardingStep nextStep;
  final String nextStepLabel;

  bool get isComplete => nextStep == OnboardingStep.done;
}

/// Аватар (ADR-021 §21.7): один із 20 стандартних грибів (`kind: standard`, [id]) або з
/// конструктора (`kind: custom`, [parts]: shape, color, face, arms, hat, item).
class Avatar {
  const Avatar({required this.kind, this.id = 1, this.parts = const {}});

  factory Avatar.fromJson(Map<String, dynamic> json) => Avatar(
        kind: req<String>(json, 'kind'),
        id: (opt<num>(json, 'id') ?? 1).toInt(),
        parts: {
          for (final e in json.entries)
            if (e.key != 'kind' && e.key != 'id' && (e.value == null || e.value is String)) e.key: e.value as String?,
        },
      );

  final String kind;
  final int id;
  final Map<String, String?> parts;

  bool get isCustom => kind == 'custom';

  Map<String, dynamic> toJson() => isCustom ? {'kind': kind, ...parts} : {'kind': kind, 'id': id};
}

/// Деталі конструктора з сервера: що відкрито, а що під замком і чому.
class AvatarCatalog {
  const AvatarCatalog(this.categories);

  factory AvatarCatalog.fromJson(Map<String, dynamic> json) => AvatarCatalog([
        for (final c in (json['categories'] as List).cast<Map<String, dynamic>>())
          (
            id: c['id'] as String,
            label: c['label'] as String,
            optional: c['optional'] == true,
            parts: [
              for (final p in (c['parts'] as List).cast<Map<String, dynamic>>())
                (
                  id: p['id'] as String,
                  label: p['label'] as String,
                  open: p['open'] == true,
                  badge: p['badge'] as String?,
                  lockLabel: p['lock_label'] as String?,
                ),
            ],
          ),
      ]);

  final List<({String id, String label, bool optional, List<({String id, String label, bool open, String? badge, String? lockLabel})> parts})> categories;
}

/// Рівень за рейтингом (ADR-013) — підписи з сервера.
class Level {
  const Level({required this.id, required this.label, required this.from, required this.to, required this.nextLabel, required this.progressLabel});

  factory Level.fromJson(Map<String, dynamic> json) => Level(
        id: req<String>(json, 'id'),
        label: req<String>(json, 'label'),
        from: req<num>(json, 'from').toInt(),
        to: opt<num>(json, 'to')?.toInt(),
        nextLabel: opt<String>(json, 'next_label'),
        progressLabel: req<String>(json, 'progress_label'),
      );

  final String id;
  final String label;
  final int from;
  final int? to;
  final String? nextLabel;
  final String progressLabel;

  /// Частка шляху до наступного рівня, 0…1.
  double progress(int rating) => to == null ? 1 : ((rating - from) / (to! + 1 - from)).clamp(0.0, 1.0);
}

class RegionChange {
  const RegionChange({required this.allowed, required this.reasonLabel});

  factory RegionChange.fromJson(Map<String, dynamic> json) => RegionChange(
        allowed: req<bool>(json, 'allowed'),
        reasonLabel: req<String>(json, 'reason_label'),
      );

  final bool allowed;
  final String reasonLabel;
}

/// Профіль із `GET/PATCH /v1-me`.
class Me {
  const Me({
    required this.id,
    required this.name,
    this.handle,
    this.avatar = const Avatar(kind: 'standard', id: 1),
    this.level,
    this.handleChange,
    required this.rating,
    required this.totalVerifiedPicks,
    required this.homeRegion,
    required this.createdAt,
    required this.isGuest,
    required this.onboarding,
    required this.regionChange,
  });

  factory Me.fromJson(Map<String, dynamic> json) {
    final region = opt<Map<String, dynamic>>(json, 'home_region');
    return Me(
      id: req<String>(json, 'id'),
      name: opt<String>(json, 'name'),
      handle: opt<String>(json, 'handle'),
      avatar: opt<Map<String, dynamic>>(json, 'avatar') == null ? const Avatar(kind: 'standard', id: 1) : Avatar.fromJson(opt<Map<String, dynamic>>(json, 'avatar')!),
      level: opt<Map<String, dynamic>>(json, 'level') == null ? null : Level.fromJson(opt<Map<String, dynamic>>(json, 'level')!),
      handleChange: opt<Map<String, dynamic>>(json, 'handle_change') == null ? null : RegionChange.fromJson(opt<Map<String, dynamic>>(json, 'handle_change')!),
      rating: req<num>(json, 'rating').toInt(),
      totalVerifiedPicks: req<num>(json, 'total_verified_picks').toInt(),
      homeRegion: region == null ? null : HomeRegion.fromJson(region),
      createdAt: DateTime.parse(req<String>(json, 'created_at')),
      isGuest: req<bool>(json, 'is_guest'),
      onboarding: Onboarding.fromJson(req<Map<String, dynamic>>(json, 'onboarding')),
      regionChange: RegionChange.fromJson(req<Map<String, dynamic>>(json, 'region_change')),
    );
  }

  final String id;
  final String? name;

  /// Нік без «@» (`Олена_лісова`); у гостя — немає.
  final String? handle;
  final Avatar avatar;
  final Level? level;

  /// Чи можна змінити нік зараз (раз на 30 днів).
  final RegionChange? handleChange;
  final int rating;
  final int totalVerifiedPicks;
  final HomeRegion? homeRegion;
  final DateTime createdAt;

  /// Гість (ADR-001, Anonymous Sign-In).
  final bool isGuest;
  final Onboarding onboarding;
  final RegionChange regionChange;
}
