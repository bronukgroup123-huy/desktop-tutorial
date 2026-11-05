import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/region_data.dart';
import 'package:flutter_client/core/supabase_config.dart';
import 'package:flutter_client/features/auth/auth_screen.dart';
import 'package:flutter_client/features/auth/region_selection_screen.dart';
import 'package:flutter_client/features/map/map_screen.dart';
import 'package:flutter_client/features/navigation/main_navigation_screen.dart';
import 'package:flutter_client/features/forecast/forecast_screen.dart';
import 'package:flutter_client/features/recognize/recognize_screen.dart';
import 'package:flutter_client/features/safety/safety_screen.dart';
import 'package:flutter_client/features/community/community_screen.dart';
import 'package:flutter_client/features/profile/profile_screen.dart';

// Auth state stream provider for GoRouter refresh
final authStateStreamProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// SharedPreferences provider for redirect access
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialize in main()');
});

// GoRouter provider with proper refreshListenable
final goRouterProvider = Provider<GoRouter>((ref) {
  final authStream = ref.watch(authStateStreamProvider.stream);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    refreshListenable: GoRouterRefreshStream(authStream),
    redirect: (context, state) {
      final authState = ref.read(authStateStreamProvider);

      // Якщо стан ще завантажується (Supabase відновлює сесію), нічого не робимо — чекаємо
      if (authState.isLoading) {
        return null;
      }

      final isLoggedIn = authState.value?.session != null;
      final location = state.matchedLocation;
      final isAuthRoute = location == '/';
      final isRegionRoute = location == '/region-selection';
      final isInShell = location.startsWith('/forecast') ||
          location.startsWith('/map') ||
          location.startsWith('/recognize') ||
          location.startsWith('/safety') ||
          location.startsWith('/community') ||
          location.startsWith('/profile');

      // Guest mode logic
      if (!isLoggedIn) {
        final prefs = ref.read(sharedPreferencesProvider);
        final hasRegion = prefs.containsKey(regionKey);

        // Якщо гість обрав область, пускаємо його в додаток
        if (hasRegion && !isInShell) {
          return '/map';
        }
        // Якщо гість без області, відправляємо на вибір області
        if (!hasRegion && !isRegionRoute) {
          return '/region-selection';
        }
        // Якщо гість намагається зайти на екран логіну, але вже має область
        if (isAuthRoute && hasRegion) {
          return '/map';
        }
        return null;
      }

      // Authenticated user logic
      if (isLoggedIn && isAuthRoute) {
        final prefs = ref.read(sharedPreferencesProvider);
        final hasRegion = prefs.containsKey(regionKey);
        return hasRegion ? '/map' : '/region-selection';
      }

      if (isLoggedIn && isRegionRoute) {
        final prefs = ref.read(sharedPreferencesProvider);
        if (prefs.containsKey(regionKey)) {
          return '/map';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthScreen()),
      GoRoute(path: '/region-selection', builder: (context, state) => const RegionSelectionScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainNavigationScreen(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/forecast', builder: (c, s) => const ForecastScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (c, s) => const MapScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/recognize', builder: (c, s) => const RecognizeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/safety', builder: (c, s) => const SafetyScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/community', builder: (c, s) => const CommunityScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen())]),
        ],
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final prefs = await SharedPreferences.getInstance();

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final authState = ref.watch(authStateStreamProvider);

    // Показуємо Splash Screen, поки Supabase відновлює сесію
    if (authState.isLoading) {
      return MaterialApp(
        title: 'Грибний Радар',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.darkGreen),
            ),
          ),
        ),
      );
    }

    return MaterialApp.router(
      title: 'Грибний Радар',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}