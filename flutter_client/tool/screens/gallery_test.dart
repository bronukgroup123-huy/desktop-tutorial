// ignore_for_file: invalid_use_of_visible_for_testing_member
// Знімки всіх основних екранів зі справжніми шрифтами — для перевірки цілісності вигляду (UI-004).
// Не частина CI: запускається вручну, PNG лягають у tool/screens/out/<SHOT_TAG>/ (у .gitignore).
//
//   SHOT_TAG=after SHOT_FONTS=assets/fonts flutter test --update-goldens tool/screens/gallery_test.dart
//
// SHOT_FONTS — тека з Inter-*.ttf і Merriweather-*.ttf (вбудовані шрифти застосунку).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/avatars.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/models/quiz.dart';
import 'package:flutter_client/data/models/trophies.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/me_repository.dart';
import 'package:flutter_client/features/analysis/analysis_result_view.dart';
import 'package:flutter_client/features/auth/auth_screen.dart';
import 'package:flutter_client/features/catalog/catalog_browser.dart';
import 'package:flutter_client/features/catalog/catalog_detail_screen.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/forecast/forecast_screen.dart';
import 'package:flutter_client/features/friends/friend_profile_screen.dart';
import 'package:flutter_client/features/friends/friends_screen.dart';
import 'package:flutter_client/features/learn/learn_screen.dart';
import 'package:flutter_client/features/learn/quiz_screen.dart';
import 'package:flutter_client/features/picks/new_pick_screen.dart';
import 'package:flutter_client/features/profile/avatar_picker_screen.dart';
import 'package:flutter_client/features/profile/licenses_screen.dart';
import 'package:flutter_client/features/profile/profile_screen.dart';
import 'package:flutter_client/features/profile/profile_setup_screen.dart';
import 'package:flutter_client/features/profile/settings_screen.dart';
import 'package:flutter_client/features/recognize/ai_model.dart';
import 'package:flutter_client/features/recognize/recognizer.dart' show recognizerProvider;
import 'package:flutter_client/features/safety/safety_content.dart';
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_client/features/safety/safety_guides.dart';
import 'package:flutter_client/features/safety/safety_screen.dart';
import 'package:flutter_client/features/safety/sos_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../test/a11y/more_stress_test.dart' show friendsRepo;
import '../../test/analysis_days_test.dart' show daysJson;
import '../../test/catalog_test.dart' show catalog;
import '../../test/data/fake_adapter.dart';
import '../../test/forecast_test.dart' show areaJson, overview;
import '../../test/friends_test.dart' show petroId;
import '../../test/profile_test.dart' show FakeMe, avatarsJson, registered, trophiesJson;
import '../../test/safety_content_test.dart' show FixedContent, bundled;
import '../../test/safety_test.dart' show FakeDevice;
import '../../test/support/memory_store.dart';

const _weights = {100: 'Thin', 200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black'};

/// Найближчий наявний файл ваги для сімейства.
File _fontFile(String dir, String family, int weight) {
  final have = {for (final e in _weights.entries) e.key: File('$dir/$family-${e.value}.ttf')}..removeWhere((_, f) => !f.existsSync());
  final best = have.keys.reduce((a, b) => (a - weight).abs() <= (b - weight).abs() ? a : b);
  return have[best]!;
}

/// Шрифти: вбудовані сімейства (Inter, Merriweather) і ті самі файли — для google_fonts під його іменами.
Future<void> _loadFonts(String dir) async {
  for (final family in ['Inter', 'Merriweather']) {
    final loader = FontLoader(family);
    for (final w in _weights.keys) {
      final f = File('$dir/$family-${_weights[w]}.ttf');
      if (f.existsSync()) loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }
  // Іконки Material — з Flutter SDK (у тестах інакше квадратики).
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
  const codec = StandardMessageCodec();
  const assets = 'build/unit_test_assets';
  final manifest = Map<Object?, Object?>.of(
      codec.decodeMessage(ByteData.sublistView(File('$assets/AssetManifest.bin').readAsBytesSync())) as Map<Object?, Object?>);
  final served = <String, File>{};
  for (final family in ['Inter', 'Merriweather']) {
    for (final w in _weights.keys) {
      for (final italic in [false, true]) {
        final name = italic ? '$family-${w == 400 ? '' : _weights[w]}Italic.ttf' : '$family-${_weights[w]}.ttf';
        served['shot_fonts/$name'] = _fontFile(dir, family, w);
        manifest['shot_fonts/$name'] = [
          {'asset': 'shot_fonts/$name'},
        ];
      }
    }
  }
  final manifestBytes = codec.encodeMessage(manifest)!;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
    final key = Uri.decodeFull(utf8.decode(message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes)));
    if (key == 'AssetManifest.bin') return manifestBytes;
    final font = served[key];
    if (font != null) return ByteData.sublistView(font.readAsBytesSync());
    final file = File('$assets/$key');
    return file.existsSync() ? ByteData.sublistView(file.readAsBytesSync()) : null;
  });
}

class _NotDownloadedAi extends AiModelController {
  @override
  AiModelState build() => const AiModelState(
        checked: true,
        remote: AiModelManifest(
          version: 'v1',
          files: [AiModelFile(name: 'model.onnx', size: 180 * 1024 * 1024, sha256: 'x')],
          imageSize: 224,
          mean: [0.5, 0.5, 0.5],
          std: [0.5, 0.5, 0.5],
          species: 120,
        ),
      );
}

void main() {
  final tag = Platform.environment['SHOT_TAG'] ?? 'current';
  final fonts = Platform.environment['SHOT_FONTS'] ?? 'assets/fonts';
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts(fonts);
  });
  setUp(() {
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => null;
    CatalogPhotoCache.directory = () async => null;
  });

  final species = catalog.species.firstWhere((s) => s.id == 'boletus_edulis');
  final photoDir = Directory.systemTemp.createTempSync('shot');
  final photo = File('${photoDir.path}/p.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
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

  List<Override> setup() {
    final (api, _) = makeClient((r) => const FakeResponse(200, {
          'data': {'handle': 'грибник', 'available': true, 'reason': null},
        }));
    return [
      meProvider.overrideWith(() => FakeMe(Me.fromJson(registered(handle: null)))),
      meRepositoryProvider.overrideWithValue(MeRepository(api)),
    ];
  }

  final screens = <(String, Widget Function(), List<Override> Function())>[
    ('01_auth', () => const AuthScreen(), () => []),
    ('02_forecast', () => const ForecastScreen(),
        () => [analysisOverviewProvider.overrideWith((ref) => overview(areas: [areaJson(withResult: true)]))]),
    ('03_catalog', () => const Scaffold(body: CatalogBrowser()),
        () => [catalogProvider.overrideWith((ref) => catalog), aiModelProvider.overrideWith(_NotDownloadedAi.new)]),
    ('04_species', () => CatalogDetailScreen(speciesId: species.id), () => [catalogProvider.overrideWith((ref) => catalog)]),
    ('05_safety', () => const SafetyScreen(), safety),
    ('06_sos', () => const SosScreen(sirenOnStart: false), safety),
    ('07_guide', () => SafetyGuideScreen(guide: bundled.guides.first), safety),
    ('08_checklist', () => const ChecklistScreen(), safety),
    ('09_rescue_card', () => const RescueCardScreen(), safety),
    ('10_profile', () => const ProfileScreen(), profile),
    ('11_settings', () => const ProfileSettingsScreen(), profile),
    ('12_avatar', () => const AvatarPickerScreen(), profile),
    ('13_friends', () => const FriendsScreen(), friends),
    ('14_friend_profile', () => const FriendProfileScreen(userId: petroId), friends),
    ('15_profile_setup', () => const ProfileSetupScreen(), setup),
    ('16_licenses', () => const LicensesScreen(), () => [catalogProvider.overrideWith((ref) => catalog)]),
    (
      '17_new_pick',
      () => NewPickScreen(photo: XFile(photo.path), point: const LatLng(50.4, 30.5), capturedAt: DateTime(2026, 11, 25)),
      () => [
            meProvider.overrideWith(() => FakeMe(Me.fromJson({
                  ...registered(),
                  'picks': {'public_allowed': false, 'public_hint_label': 'Публічні точки — з рівня «Лісовик».', 'private_allowed': true},
                }))),
            recognizerProvider.overrideWith((ref) async => null),
          ],
    ),
    ('18_analysis', () => Scaffold(body: AnalysisResultView(result: AnalysisResult.fromJson(daysJson()), miniMapBuilder: (_) => const SizedBox(height: 40))), () => []),
    ('19_learn', () => const LearnScreen(), () => [quizOverviewProvider.overrideWith((ref) async => QuizOverview.fromJson(_quizOverview))]),
    ('20_quiz', () => QuizScreen(module: QuizModule.fromJson(_quizOverview['modules'][0]), attempt: QuizAttempt.fromJson(_quizAttempt())), () => []),
    ('21_quiz_result', () => Scaffold(body: QuizResultView(result: QuizResult.fromJson(_quizResult()))), () => []),
  ];
  // Довгі екрани — висока «сторінка», щоб побачити все.
  const tall = {'04_species', '18_analysis', '21_quiz_result'};

  for (final (name, screen, overrides) in screens) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = Size(412, tall.contains(name) ? 4200 : 1500) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(),
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.lightTheme, home: screen()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 150));
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$tag/$name.png'));
    });
  }
}

// ─── Навчання (B3.10c): справжні питання модуля 1 з data/quiz/app.json ───────
final Map<String, dynamic> _quizOverview = {
  'modules': [
    for (final (i, m) in [
      ('app', 'Як працює Грибний Радар', 'Звідки прогноз і чому чесні відповіді роблять його точнішим саме для вас', 10, 'open'),
      ('forest', 'Ліс і гриб', 'Грибниця, союз грибів із деревами', 10, 'locked'),
      ('weather', 'Погода, сезони, хвилі', 'Дощ і тепло із запізненням', 15, 'soon'),
      ('ethics', 'Етика й закон', 'Червона книга, заповідники', 15, 'soon'),
      ('safety', 'Безпека в лісі', 'Заблукав, сідає телефон, темніє', 20, 'soon'),
      ('myths', 'Міфи, які вбивають', 'Народні «перевірки»', 25, 'soon'),
      ('twins', 'Отруйні двійники', 'Коли однієї ознаки замало', 25, 'soon'),
    ].indexed)
      {'id': m.$1, 'position': i + 1, 'title': m.$2, 'summary': m.$3, 'points': m.$4, 'status': m.$5, 'questions_per_attempt': 10, 'pass_percent': 80},
  ],
  'passed_count': 0,
  'total': 7,
  'disclaimer_label': 'Тест навчає, але не дає дозволу їсти знайдені гриби',
};

List<Map<String, dynamic>> _appQuestions() =>
    ((jsonDecode(File('../data/quiz/app.json').readAsStringSync()) as Map)['questions'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _quizAttempt() => {
      'attempt_id': '11111111-2222-4333-8444-555555555555',
      'practice': false,
      'questions': [for (final q in _appQuestions().take(10)) {'id': q['id'], 'kind': q['kind'], 'prompt': q['prompt'], 'options': q['options']}],
    };

Map<String, dynamic> _quizResult() {
  final qs = _appQuestions().take(4).toList();
  return {
    'correct': 3, 'total': 4, 'percent': 75, 'pass_percent': 80, 'passed': false, 'critical_failed': false,
    'points_awarded': 0, 'certified_now': false, 'practice': false,
    'result_label': 'Не зараховано: 3 з 4 (75 %), потрібно 80 %. Наступна спроба на бали — через добу',
    'review': [
      for (final (i, q) in qs.indexed)
        {
          ...q,
          'chosen': i == 0 ? ['a'] : q['correct'],
          'is_correct': i != 0,
          'critical': false,
        },
    ],
  };
}
