// UI-001c: решта екранів (друзі, безпека, профіль, ліцензії) — ті самі умови, що layout_stress_test.dart:
// малий екран, шрифт ×2, альбомна орієнтація. Падає на переповненні в коді lib/.
import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/friends_repository.dart';
import 'package:flutter_client/data/repositories/me_repository.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/friends/friend_profile_screen.dart';
import 'package:flutter_client/features/friends/friends_screen.dart';
import 'package:flutter_client/features/profile/licenses_screen.dart';
import 'package:flutter_client/features/profile/profile_setup_screen.dart';
import 'package:flutter_client/features/safety/safety_content.dart';
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_client/features/safety/safety_guides.dart';
import 'package:flutter_client/features/safety/sos_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../catalog_test.dart' show catalog;
import '../data/fake_adapter.dart';
import '../friends_test.dart' show act, card, irynaId, petroId;
import '../profile_test.dart' show FakeMe, registered;
import '../safety_content_test.dart' show FixedContent, bundled;
import '../safety_test.dart' show FakeDevice;
import '../support/memory_store.dart';
import 'layout_stress_test.dart' show stressCases;
import 'tabs_stress_test.dart' show pumpStress, scrollAll;

/// Відповіді v1-friends: список із запитом і профіль друга з трофеями.
FriendsRepository friendsRepo() {
  final report = act('report', 'Поскаржитися', 'menu');
  final block = act('block', 'Заблокувати', 'danger', 'Заблокувати?');
  final (api, _) = makeClient((r) {
    if (r.queryParameters['user'] != null) {
      return FakeResponse(200, {
        'data': {
          'profile': {
            ...card(petroId, 'Петро_Лісовий_Грибник', 'friends', [act('remove', 'Видалити з друзів', 'menu', 'Видалити?'), report, block],
                label: 'У друзях'),
            'is_me': false,
            'trophies': [
              {'id': 'first_find', 'title': 'Перша знахідка', 'earned_at': '2026-09-10T08:00:00Z'},
            ],
          },
        },
      });
    }
    return FakeResponse(200, {
      'data': {
        'friends': [
          card(petroId, 'Петро_Лісовий_Грибник', 'friends', [act('remove', 'Видалити з друзів', 'menu', 'Видалити?'), report, block],
              label: 'У друзях'),
        ],
        'incoming': [
          card(irynaId, 'Ірина', 'incoming', [act('accept', 'Прийняти', 'primary'), act('decline', 'Відхилити', 'secondary'), report, block],
              label: 'Хоче додати вас у друзі'),
        ],
        'outgoing': [],
        'blocked': [],
        'counts': {'friends': 1, 'incoming': 1},
        'limits': {'max_friends': 200, 'label': 'До 200 друзів'},
      },
    });
  });
  return FriendsRepository(api);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => null;
    CatalogPhotoCache.directory = () async => null;
  });

  List<Override> safety() => [
        localStoreProvider.overrideWithValue(MemoryStore()),
        safetyContentProvider.overrideWith(() => FixedContent(bundled)),
        safetyDeviceProvider.overrideWithValue(FakeDevice()),
      ];

  List<Override> friends() {
    final repo = friendsRepo();
    return [
      friendsRepositoryProvider.overrideWithValue(repo),
      friendsProvider.overrideWith((ref) => ref.watch(friendsRepositoryProvider).overview()),
    ];
  }

  List<Override> profileSetup() {
    final (api, _) = makeClient((r) => const FakeResponse(200, {
          'data': {'handle': 'грибник', 'available': true, 'reason': null},
        }));
    return [
      meProvider.overrideWith(() => FakeMe(Me.fromJson(registered(handle: null)))),
      meRepositoryProvider.overrideWithValue(MeRepository(api)),
    ];
  }

  final screens = <(String, Widget Function(), List<Override> Function())>[
    ('Друзі', () => const FriendsScreen(), friends),
    ('Профіль друга', () => const FriendProfileScreen(userId: petroId), friends),
    for (final g in bundled.guides) ('Довідка «${g.title}»', () => SafetyGuideScreen(guide: g), safety),
    ('Чек-лист', () => const ChecklistScreen(), safety),
    ('Картка рятувальника', () => const RescueCardScreen(), safety),
    ('SOS', () => const SosScreen(sirenOnStart: false), safety),
    ('Ім\'я й нік', () => const ProfileSetupScreen(), profileSetup),
    ('Ліцензії', () => const LicensesScreen(), () => [catalogProvider.overrideWith((ref) => catalog)]),
  ];

  for (final c in stressCases) {
    for (final (name, screen, overrides) in screens) {
      testWidgets('$name: ${c.name} — без переповнення', (tester) async {
        final overflows = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          final text = details.toString();
          if (!text.contains('overflowed')) return original?.call(details);
          final where = text.split('\n').firstWhere((l) => l.contains('/lib/'), orElse: () => '');
          overflows.add('${details.exceptionAsString().split('\n').first} ${where.trim()}');
        };
        addTearDown(() => FlutterError.onError = original);
        await pumpStress(tester, screen(), c, overrides: overrides());
        await scrollAll(tester);
        FlutterError.onError = original;
        expect(overflows, isEmpty);
      });
    }
  }
}
