import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'api/api_client.dart';
import 'local/local_store.dart';
import 'local/offline_result.dart';
import 'models/forecast.dart';
import 'models/me.dart';
import 'models/region.dart';
import 'repositories/auth_repository.dart';
import 'repositories/forecast_repository.dart';
import 'repositories/forest_zones_repository.dart';
export 'repositories/forest_zones_repository.dart' show ForestLoad;
import 'repositories/me_repository.dart';
import 'repositories/regions_repository.dart';

// ─── Інфраструктура ─────────────────────────────────────────────────────────

/// Supabase Auth. У тестах перевизначається.
final goTrueClientProvider = Provider<GoTrueClient>((ref) => Supabase.instance.client.auth);

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(goTrueClientProvider)));

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return ApiClient(
    dio: Dio(BaseOptions(
      baseUrl: SupabaseConfig.functionsUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    )),
    publishableKey: SupabaseConfig.publishableKey,
    accessToken: () => auth.accessToken,
  );
});

/// Сховище на телефоні (офлайн-режим). Створюється в main() і перевизначається.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider must be overridden in main()'),
);

final meRepositoryProvider = Provider((ref) => MeRepository(ref.watch(apiClientProvider)));
final regionsRepositoryProvider = Provider(
  (ref) => RegionsRepository(ref.watch(apiClientProvider), ref.watch(localStoreProvider)),
);
final forestZonesRepositoryProvider = Provider(
  (ref) => ForestZonesRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStoreProvider),
    files: Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))),
  ),
);
final forecastRepositoryProvider = Provider(
  (ref) => ForecastRepository(ref.watch(apiClientProvider), ref.watch(localStoreProvider)),
);

// ─── Стан ───────────────────────────────────────────────────────────────────

/// Зміни сесії Supabase (вхід, вихід, оновлення токена).
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges,
);

/// Профіль поточного користувача; `null` — немає сесії.
/// Перезавантажується при вході/виході.
final meProvider = AsyncNotifierProvider<MeNotifier, Me?>(MeNotifier.new);

class MeNotifier extends AsyncNotifier<Me?> {
  @override
  Future<Me?> build() async {
    ref.watch(authStateProvider.select((s) => s.valueOrNull?.session?.user.id));
    if (!ref.read(authRepositoryProvider).isSignedIn) return null;
    return ref.read(meRepositoryProvider).fetchMe();
  }

  /// Область + згода з умовами одним запитом. Помилку сервера передаємо в UI.
  Future<void> completeOnboarding(String regionSlug) async {
    final current = state.valueOrNull;
    if (current == null) throw StateError('No profile loaded');
    final updated = await ref.read(meRepositoryProvider).completeOnboarding(
          regionSlug: regionSlug,
          termsVersion: current.onboarding.termsVersion,
        );
    state = AsyncData(updated);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<Me?>().copyWithPrevious(state);
    state = await AsyncValue.guard(build);
  }
}

/// Довідник областей для онбордингу.
final regionsProvider = FutureProvider<List<RegionSummary>>(
  (ref) => ref.watch(regionsRepositoryProvider).fetchRegions(),
);

/// Кордон області (маска «острова»).
final regionGeometryProvider = FutureProvider.family<RegionGeometry, String>(
  (ref, slug) => ref.watch(regionsRepositoryProvider).fetchGeometry(slug),
);

/// Ліси всієї Home Region — файлом області (один раз, далі з телефону), а якщо
/// файлу ще немає — плитками з сервера. Кожна подія — усі ліси, що вже є.
final regionForestsProvider = StreamProvider.family<ForestLoad, String>((ref, slug) async* {
  final geometry = await ref.watch(regionGeometryProvider(slug).future);
  yield* ref.watch(forestZonesRepositoryProvider).loadRegion(slug, geometry.bounds, files: geometry.forests);
});

// ─── Прогноз ────────────────────────────────────────────────────────────────

/// Точка, обрана на карті (тап по лісу). Прогноз з'являється ТІЛЬКИ після вибору
/// точки (план v8.2 §3.1).
class ForecastPoint {
  const ForecastPoint({
    required this.lat,
    required this.lng,
    this.forestType,
    this.title,
  });

  final double lat;
  final double lng;

  /// Тип лісу полігону, по якому тапнули (сервер уточнює прогноз).
  final String? forestType;

  /// Підпис місця для заголовка (наприклад, «Сосновий ліс»).
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is ForecastPoint && other.lat == lat && other.lng == lng && other.forestType == forestType;

  @override
  int get hashCode => Object.hash(lat, lng, forestType);
}

/// Остання обрана точка — її показує вкладка «Прогноз».
final selectedPointProvider = StateProvider<ForecastPoint?>((ref) => null);

/// Прогноз для точки на сьогодні; без інтернету — останній збережений.
final forecastProvider = FutureProvider.autoDispose.family<OfflineResult<Forecast>, ForecastPoint>(
  (ref, p) => ref.watch(forecastRepositoryProvider).fetchForecast(
        lat: p.lat,
        lng: p.lng,
        date: DateTime.now(),
        forestType: p.forestType,
      ),
);
