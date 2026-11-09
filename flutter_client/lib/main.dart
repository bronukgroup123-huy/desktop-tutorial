import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/supabase_config.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/auth/auth_screen.dart';
import 'package:flutter_client/features/auth/region_selection_screen.dart';
import 'package:flutter_client/features/community/community_screen.dart';
import 'package:flutter_client/features/forecast/forecast_screen.dart';
import 'package:flutter_client/features/map/map_screen.dart';
import 'package:flutter_client/features/navigation/main_navigation_screen.dart';
import 'package:flutter_client/features/profile/profile_screen.dart';
import 'package:flutter_client/features/recognize/recognize_screen.dart';
import 'package:flutter_client/features/safety/safety_screen.dart';
import 'package:flutter_client/features/splash/splash_screen.dart';

// ─── Маршрути ───────────────────────────────────────────────────────────────

abstract final class Routes {
  static const auth = '/';
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const map = '/map';
}

const _shellPrefixes = ['/forecast', '/map', '/recognize', '/safety', '/community', '/profile'];

/// Куди вести користувача. Чиста функція — тестується без UI.
///
/// Рішення про онбординг приймає сервер (`onboarding.next_step`), клієнт лише
/// виконує його (Thin Client). Без області карта не відкривається (Правило №1).
String? resolveRedirect({
  required bool authLoading,
  required bool signedIn,
  required AsyncValue<Me?> me,
  required String location,
}) {
  if (authLoading) return location == Routes.splash ? null : Routes.splash;
  if (!signedIn) return location == Routes.auth ? null : Routes.auth;

  // Профіль ще вантажиться або впав із помилкою — splash показує стан і «Повторити».
  final profile = me.valueOrNull;
  if (profile == null) return location == Routes.splash ? null : Routes.splash;

  if (!profile.onboarding.isComplete) {
    return location == Routes.onboarding ? null : Routes.onboarding;
  }

  final inShell = _shellPrefixes.any(location.startsWith);
  return inShell ? null : Routes.map;
}

/// Перебудовує редірект GoRouter при зміні сесії або профілю.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(meProvider, (_, __) => notifyListeners());
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      return resolveRedirect(
        authLoading: auth.isLoading && !auth.hasValue,
        signedIn: ref.read(authRepositoryProvider).isSignedIn,
        me: ref.read(meProvider),
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(path: Routes.auth, builder: (c, s) => const AuthScreen()),
      GoRoute(path: Routes.splash, builder: (c, s) => const SplashScreen()),
      GoRoute(path: Routes.onboarding, builder: (c, s) => const RegionSelectionScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainNavigationScreen(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/forecast', builder: (c, s) => const ForecastScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.map, builder: (c, s) => const MapScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/recognize', builder: (c, s) => const RecognizeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/safety', builder: (c, s) => const SafetyScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/community', builder: (c, s) => const CommunityScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen())]),
        ],
      ),
    ],
  );
});

// ─── Запуск ─────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Грибний Радар',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: ref.watch(goRouterProvider),
    );
  }
}

/// Збірка без `--dart-define-from-file=.env` — підказка розробнику замість падіння.
class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Не задано SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY.\n'
              'Запустіть: flutter run --dart-define-from-file=.env',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
