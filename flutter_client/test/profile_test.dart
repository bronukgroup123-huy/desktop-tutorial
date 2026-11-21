import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/avatars.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/models/trophies.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/me_repository.dart';
import 'package:flutter_client/features/profile/avatar_picker_screen.dart';
import 'package:flutter_client/features/profile/profile_hero.dart';
import 'package:flutter_client/features/profile/profile_screen.dart';
import 'package:flutter_client/features/profile/settings_screen.dart';
import 'package:flutter_client/features/profile/profile_setup_screen.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthState;
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';
import 'data/models_test.dart' show meJson;
import 'safety_test.dart' show frames;

/// Вертикальна прокрутка вкладки «Профіль» (усередині є горизонтальний ряд трофеїв).
final profileScroll = find.descendant(of: find.byKey(const ValueKey('profile-list')), matching: find.byType(Scrollable)).first;

/// Прокрутка екрана «Налаштування».
final settingsScroll = find.descendant(of: find.byKey(const ValueKey('settings-list')), matching: find.byType(Scrollable)).first;

/// Відкрити «Налаштування» кнопкою внизу профілю.
Future<void> openSettings(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(const ValueKey('profile-settings')), 300, scrollable: profileScroll);
  await tester.ensureVisible(find.byKey(const ValueKey('profile-settings')));
  await frames(tester);
  await tester.tap(find.byKey(const ValueKey('profile-settings')));
  await frames(tester);
  expect(find.byType(ProfileSettingsScreen), findsOneWidget);
}

Map<String, dynamic> registered({String? handle = 'Олена_лісова', bool handleAllowed = true}) => {
      ...meJson(region: {'id': 1, 'slug': 'zhytomyrska', 'name': 'Житомирська область'}),
      'is_guest': false,
      'name': 'Олена Лісова',
      'handle': handle,
      'avatar': {'kind': 'preset', 'id': 'tracker_02'},
      'rating': 120,
      'total_verified_picks': 7,
      'level': {'id': 'tracker', 'label': 'Слідопит', 'from': 51, 'to': 200, 'next_label': 'Лісовик', 'progress_label': '120 балів · ще 81 бал до рівня «Лісовик»'},
      'handle_change': {'allowed': handleAllowed, 'reason_label': handleAllowed ? 'Нік можна змінити раз на 30 днів' : 'Нік можна буде змінити з 10.12.2026'},
    };

class FakeMe extends MeNotifier {
  FakeMe(this.me);
  final Me me;
  final calls = <String>[];

  @override
  Future<Me?> build() async => me;

  @override
  Future<void> updateIdentity({required String name, required String handle}) async => calls.add('identity:$name:$handle');

  @override
  Future<void> deleteAccount() async => calls.add('delete');

  @override
  Future<void> setAvatar(String id) async => calls.add('avatar:$id');
}

/// Вибір аватара, як віддає сервер (скорочено): «Слідопит» — два рівні відкриті.
Map<String, dynamic> avatarsJson({bool canChange = true}) {
  Map<String, dynamic> g(String level, String label, bool open, List<String> ids) => {
        'level': level, 'label': label, 'open': open,
        'lock_label': open ? null : 'Відкриється на рівні «$label»',
        'avatars': [for (final id in ids) {'id': id, 'title': 'Гриб $id', 'role': 'Роль $id', 'open': open}],
      };
  return {
    'current': {'kind': 'preset', 'id': 'tracker_02'},
    'can_change': canChange,
    'reason_label': canChange ? null : 'Змінити аватар можна після входу через Google або Apple',
    'groups': [
      g('traveler', 'Мандрівник', true, ['traveler_01', 'traveler_02']),
      g('tracker', 'Слідопит', true, ['tracker_01', 'tracker_02']),
      g('keeper', 'Хранитель лісу', false, ['keeper_01']),
    ],
  };
}

/// Трофеї, як віддає сервер (скорочено).
Map<String, dynamic> trophiesJson() => {
      'trophies': [
        {'id': 'first_find', 'title': 'Перша знахідка', 'tier': 'bronze', 'tier_label': 'Бронза', 'how_label': 'Перша підтверджена знахідка — тук-тук із фото, знятим на місці', 'earned': true, 'earned_at': '2026-09-10T08:00:00Z', 'progress_label': null, 'progress': 1, 'soon': false},
        {'id': 'basket', 'title': 'Грибний кошик', 'tier': 'silver', 'tier_label': 'Срібло', 'how_label': '10 підтверджених знахідок', 'earned': false, 'earned_at': null, 'progress_label': '7 з 10', 'progress': 0.7, 'soon': false},
        {'id': 'mycologist', 'title': 'Грибознавець', 'tier': 'gold', 'tier_label': 'Золото', 'how_label': 'Отримати сертифікат знань — скласти всі тести', 'earned': false, 'earned_at': null, 'progress_label': null, 'progress': 0, 'soon': true},
      ],
      'earned_count': 1,
      'total': 24,
      'new_labels': [],
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('Профіль із сервера: нік, аватар, рівень, крок «profile»', () {
    final me = Me.fromJson(registered());
    expect([me.handle, me.avatar.id, me.level!.label], ['Олена_лісова', 'tracker_02', 'Слідопит']);
    expect(me.level!.progress(120), closeTo((120 - 51) / 150, 1e-9));
    expect(Me.fromJson(meJson(nextStep: 'profile')).onboarding.nextStep, OnboardingStep.profile);
    expect(Me.fromJson(meJson()).avatar.id, 'traveler_01'); // старий сервер без аватара — перший «Мандрівник»
  });

  late FakeMe fake;
  late List<String> checked;
  var available = true;
  var canChangeAvatar = true;

  Widget app(Widget home, Map<String, dynamic> me, {Stream<AuthState>? auth}) {
    fake = FakeMe(Me.fromJson(me));
    checked = [];
    final (api, _) = makeClient((r) {
      checked.add(r.queryParameters['check_handle'] as String);
      return FakeResponse(200, {
        'data': {'handle': r.queryParameters['check_handle'], 'available': available, 'reason': available ? null : 'Нік @грибник уже зайнятий'},
      });
    });
    return ProviderScope(
      overrides: [
        meProvider.overrideWith(() => fake),
        meRepositoryProvider.overrideWithValue(MeRepository(api)),
        trophiesProvider.overrideWith((ref) async => TrophiesOverview.fromJson(trophiesJson())),
        avatarChoicesProvider.overrideWith((ref) async => AvatarChoices.fromJson(avatarsJson(canChange: canChangeAvatar))),
        if (auth != null) authStateProvider.overrideWith((ref) => auth),
      ],
      child: MaterialApp(home: home),
    );
  }

  testWidgets('Профіль: ім\'я, @нік, рівень із прогресом; аватар більший і відкриває вибір', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const ProfileScreen(), registered()));
    await frames(tester);
    expect(find.text('Олена Лісова'), findsOneWidget);
    expect(find.text('@Олена_лісова'), findsOneWidget);
    expect(find.text('Слідопит'), findsOneWidget);
    expect(find.text('120 балів · ще 81 бал до рівня «Лісовик»'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-guest')), findsNothing);
    // Знахідки й бали — коротко під ніком; на місці «Мого сезону» — трофеї й подарунки.
    expect(find.descendant(of: find.byKey(const ValueKey('profile-stats')), matching: find.text('7')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('profile-stats')), matching: find.text('знахідок')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('profile-stats')), matching: find.text('балів')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-season')), findsNothing);
    expect(find.byKey(const ValueKey('profile-trophies')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-gifts')), findsOneWidget);
    // Трофеї з сервера: «1 з 24», прогрес під закритим; дотик — за що й скільки.
    expect(find.text('1 з 24'), findsOneWidget);
    expect(find.text('7 з 10'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trophy-basket')));
    await frames(tester);
    expect(find.byKey(const ValueKey('trophy-sheet')), findsOneWidget);
    expect(find.text('10 підтверджених знахідок'), findsOneWidget);
    expect(find.text('Срібло'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await frames(tester);
    // Аватар — готова картинка з рамкою рівня, 208; дотик — вибір аватара.
    expect(tester.getSize(find.byType(UserAvatar).first).width, 208);
    // Область, дані без інтернету й акаунт — не на вкладці, а в «Налаштуваннях».
    expect(find.byKey(const ValueKey('profile-region')), findsNothing);
    expect(find.byKey(const ValueKey('profile-offline')), findsNothing);
    await openSettings(tester);
    // Область — лише мені, у налаштуваннях (у публічному профілі її немає).
    expect(find.text('Житомирська область'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-offline')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('profile-delete')), 200, scrollable: settingsScroll);
    expect(find.byKey(const ValueKey('profile-sign-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-identity')), findsOneWidget);
    await tester.pageBack();
    await frames(tester);

    await tester.drag(find.byKey(const ValueKey('profile-list')), const Offset(0, 5000));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('profile-avatar')));
    await frames(tester);
    expect(find.byType(AvatarPickerScreen), findsOneWidget);
  });

  testWidgets('Шапка профілю: фон і значок рівня — за рівнем (як рамки аватарів)', (tester) async {
    expect(heroPalette('master').top, isNot(heroPalette('traveler').top));
    expect({for (final l in ['traveler', 'tracker', 'expert', 'forester', 'keeper', 'master']) heroPalette(l).top}.length, 6);
    expect(heroPalette(null).top, heroPalette('traveler').top);
    await tester.pumpWidget(const MaterialApp(home: ProfileHeroBackground(levelId: 'keeper', child: SizedBox(width: 300, height: 300))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Гість: «Увійти через Google / Apple», без видалення акаунта; дані без інтернету — є', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const ProfileScreen(), meJson(region: {'id': 1, 'slug': 'zhytomyrska', 'name': 'Житомирська область'})));
    await frames(tester);
    expect(find.byKey(const ValueKey('profile-guest')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-google')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-header')), findsNothing);
    // Налаштування є й у гостя: офлайн дані згорнуті під кнопкою; натиснули — список. Акаунта немає.
    await openSettings(tester);
    expect(find.byKey(const ValueKey('data-map')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('profile-offline')));
    await frames(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('data-ai')), 200, scrollable: settingsScroll);
    expect(find.byKey(const ValueKey('data-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-delete')), findsNothing);
    expect(find.byKey(const ValueKey('profile-sign-out')), findsNothing);
  });

  testWidgets('Гість: Google уже має свій профіль — пропонуємо увійти в нього, а не мовчимо', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final auth = StreamController<AuthState>();
    addTearDown(auth.close);
    await tester.pumpWidget(app(const ProfileScreen(), meJson(region: {'id': 1, 'slug': 'zhytomyrska', 'name': 'Житомирська область'}), auth: auth.stream));
    await frames(tester);
    auth.addError(const AuthException('Identity is already linked to another user', statusCode: 'identity_already_exists', code: 'server_error'));
    await frames(tester);
    expect(find.byKey(const ValueKey('google-taken')), findsOneWidget);
    expect(find.textContaining('не перенесуться'), findsOneWidget);
    await tester.tap(find.text('Скасувати'));
    await frames(tester);
    expect(find.byKey(const ValueKey('google-taken')), findsNothing);
  });

  testWidgets('Видалити акаунт — лише після підтвердження', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const ProfileScreen(), registered()));
    await frames(tester);
    await openSettings(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('profile-delete')), 300, scrollable: settingsScroll);
    await tester.ensureVisible(find.byKey(const ValueKey('profile-delete')));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('profile-delete')));
    await frames(tester);
    expect(find.byKey(const ValueKey('delete-confirm')), findsOneWidget);
    await tester.tap(find.text('Скасувати'));
    await frames(tester);
    expect(fake.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('profile-delete')));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('delete-yes')));
    await frames(tester);
    expect(fake.calls, ['delete']);
  });

  testWidgets('Ім\'я й нік: латиниця — підказка одразу; зайнятий — не зберегти; вільний — зберегти', (tester) async {
    available = false;
    await tester.pumpWidget(app(const ProfileSetupScreen(), registered(handle: null)));
    await frames(tester);
    await tester.enterText(find.byKey(const ValueKey('identity-name')), 'Олена Лісова');
    await tester.enterText(find.byKey(const ValueKey('identity-handle')), 'olena');
    await tester.pump();
    expect(find.text('Нік — лише українськими літерами, без латиниці'), findsOneWidget);
    expect(checked, isEmpty); // латиницю на сервер не шлемо

    await tester.enterText(find.byKey(const ValueKey('identity-handle')), 'грибник');
    await tester.pump(const Duration(milliseconds: 500));
    await frames(tester);
    expect(checked, ['грибник']);
    expect(find.text('Нік @грибник уже зайнятий'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('identity-save'))).onPressed, isNull);

    available = true;
    await tester.enterText(find.byKey(const ValueKey('identity-handle')), 'грибник_2');
    await tester.pump(const Duration(milliseconds: 500));
    await frames(tester);
    expect(find.text('Нік вільний'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('identity-save')));
    await frames(tester);
    expect(fake.calls, ['identity:Олена Лісова:грибник_2']);
  });

  testWidgets('Нік змінено нещодавно — поле заблоковане з датою', (tester) async {
    await tester.pumpWidget(app(const EditIdentityScreen(), registered(handleAllowed: false)));
    await frames(tester);
    expect(find.text('Нік можна буде змінити з 10.12.2026'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('identity-handle'))).enabled, isFalse);
  });

  test('Аватар: готовий зі списку; старі наліпки, числові id і default — перший «Мандрівник»', () {
    expect(Avatar.fromJson({'kind': 'preset', 'id': 'keeper_03'}).toJson(), {'kind': 'preset', 'id': 'keeper_03'});
    expect(Avatar.fromJson({'kind': 'custom', 'sticker': 'dizzy'}).id, 'traveler_01');
    expect(Avatar.fromJson({'kind': 'standard', 'id': 3}).id, 'traveler_01');
    expect(Avatar.fromJson({'kind': 'preset', 'id': 'default'}).id, 'traveler_01');
    expect(const Avatar().asset, 'assets/avatars/traveler_01.webp');
  });

  testWidgets('Аватар: картинки, якої ще немає в застосунку, — перший «Мандрівник», без збою', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: UserAvatar(avatar: Avatar(id: 'not_shipped_yet'), size: 60))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('Вибір аватара: групи за рівнями, закритий — з причиною і не вибирається; «Зберегти»', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    canChangeAvatar = true;
    await tester.pumpWidget(app(const AvatarPickerScreen(), registered()));
    await frames(tester);
    expect(find.text('Гриб tracker_02'), findsOneWidget); // поточний — у великому перегляді
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('avatar-save'))).onPressed, isNull);
    final list = find.descendant(of: find.byKey(const ValueKey('avatar-list')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('avatar-keeper_01')), 200, scrollable: list);
    expect(find.text('Відкриється на рівні «Хранитель лісу»'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('avatar-keeper_01')));
    await frames(tester);
    expect(find.text('Гриб keeper_01'), findsNothing); // закритий не вибирається
    await tester.pump(const Duration(seconds: 5));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('avatar-traveler_02')), -200, scrollable: list);
    await tester.tap(find.byKey(const ValueKey('avatar-traveler_02')));
    await frames(tester);
    expect(find.text('Гриб traveler_02'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('avatar-save')));
    await frames(tester);
    expect(fake.calls, ['avatar:traveler_02']);
  });

  testWidgets('Вибір аватара: гість — лише перегляд і причина, без «Зберегти»', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    canChangeAvatar = false;
    await tester.pumpWidget(app(const AvatarPickerScreen(), registered()));
    await frames(tester);
    expect(find.byKey(const ValueKey('avatar-reason')), findsOneWidget);
    expect(find.byKey(const ValueKey('avatar-save')), findsNothing);
    canChangeAvatar = true;
  });
}
