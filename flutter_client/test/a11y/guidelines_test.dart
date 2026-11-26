// UI-003: правила доступності Flutter на основних екранах — у кожного елемента, який можна натиснути,
// є підпис для екранної читалки (TalkBack), і зона натискання не менша за 48×48 (вимога Android).
// Контраст тексту тут не перевіряється: це зміна вигляду, рішення власника (docs/agent/BACKLOG.md, UI-003).
import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/avatars.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/models/trophies.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/auth/auth_screen.dart';
import 'package:flutter_client/features/catalog/catalog_browser.dart';
import 'package:flutter_client/features/catalog/catalog_detail_screen.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/forecast/forecast_screen.dart';
import 'package:flutter_client/features/friends/friend_profile_screen.dart';
import 'package:flutter_client/features/friends/friends_screen.dart';
import 'package:flutter_client/features/profile/avatar_picker_screen.dart';
import 'package:flutter_client/features/profile/profile_screen.dart';
import 'package:flutter_client/features/profile/settings_screen.dart';
import 'package:flutter_client/features/safety/safety_content.dart';
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_client/features/safety/safety_guides.dart';
import 'package:flutter_client/features/safety/safety_screen.dart';
import 'package:flutter_client/features/safety/sos_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../catalog_test.dart' show catalog;
import '../forecast_test.dart' show areaJson, overview;
import '../friends_test.dart' show petroId;
import '../profile_test.dart' show FakeMe, avatarsJson, registered, trophiesJson;
import '../safety_content_test.dart' show FixedContent, bundled;
import '../safety_test.dart' show FakeDevice;
import '../support/memory_store.dart';
import 'more_stress_test.dart' show friendsRepo;
import 'tabs_stress_test.dart' show pumpStress;

/// Свідомі винятки: що саме й чому.
const _exempt = {
  // Олівець у куті плитки ділянки (40×40): 48 px перекривав би назву, і дотик до назви відкривав би
  // перейменування. Те саме доступне довгим натисканням на плитку — TalkBack його озвучує.
  'tooltip: "Назва ділянки"',
};

/// Порушення правила, крім винятків.
Future<List<String>> violations(WidgetTester tester, AccessibilityGuideline g) async {
  final r = await g.evaluate(tester);
  if (r.passed) return const [];
  return (r.reason ?? '')
      .split('SemanticsNode#')
      .where((e) => e.trim().isNotEmpty && !_exempt.any(e.contains))
      .map((e) => e.split('\n').first)
      .toList();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => null;
    CatalogPhotoCache.directory = () async => null;
  });

  const phone = (name: 'телефон 412×915', size: Size(412, 915), text: 1.0);
  final species = catalog.species.firstWhere((s) => s.id == 'boletus_edulis');
  List<Override> profile() => [
        meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
        trophiesProvider.overrideWith((ref) async => TrophiesOverview.fromJson(trophiesJson())),
        avatarChoicesProvider.overrideWith((ref) async => AvatarChoices.fromJson(avatarsJson())),
      ];
  List<Override> safety() => [
        localStoreProvider.overrideWithValue(MemoryStore()),
        safetyContentProvider.overrideWith(() => FixedContent(bundled)),
        safetyDeviceProvider.overrideWithValue(FakeDevice()),
      ];
  List<Override> friends() {
    final r = friendsRepo();
    return [friendsRepositoryProvider.overrideWithValue(r), friendsProvider.overrideWith((ref) => r.overview())];
  }

  final screens = <(String, Widget, List<Override> Function())>[
    ('Вхід', const AuthScreen(), () => []),
    ('Безпека', const SafetyScreen(), safety),
    ('SOS', const SosScreen(sirenOnStart: false), safety),
    ('Довідка', SafetyGuideScreen(guide: bundled.guides.first), safety),
    ('Прогноз', const ForecastScreen(),
        () => [analysisOverviewProvider.overrideWith((ref) => overview(areas: [areaJson(withResult: true)]))]),
    ('Довідник', const Scaffold(body: CatalogBrowser()), () => [catalogProvider.overrideWith((ref) => catalog)]),
    ('Картка виду', CatalogDetailScreen(speciesId: species.id), () => [catalogProvider.overrideWith((ref) => catalog)]),
    ('Профіль', const ProfileScreen(), profile),
    ('Налаштування', const ProfileSettingsScreen(), profile),
    ('Вибір аватара', const AvatarPickerScreen(), profile),
    ('Друзі', const FriendsScreen(), friends),
    ('Профіль друга', const FriendProfileScreen(userId: petroId), friends),
  ];

  for (final (name, screen, overrides) in screens) {
    testWidgets('$name: підписи й зони натискання ≥ 48 px', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpStress(tester, screen, phone, overrides: overrides());
      expect(await violations(tester, labeledTapTargetGuideline), isEmpty, reason: 'без підпису');
      expect(await violations(tester, androidTapTargetGuideline), isEmpty, reason: 'менше 48×48');
      semantics.dispose();
    });
  }
}
