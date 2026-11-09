import 'json.dart';

/// Наступний крок онбордингу — вирішує сервер (`GET /v1-me` → onboarding.next_step).
enum OnboardingStep {
  selectRegion('select_region'),
  acceptTerms('accept_terms'),
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
  final int rating;
  final int totalVerifiedPicks;
  final HomeRegion? homeRegion;
  final DateTime createdAt;

  /// Гість (ADR-001, Anonymous Sign-In).
  final bool isGuest;
  final Onboarding onboarding;
  final RegionChange regionChange;
}
