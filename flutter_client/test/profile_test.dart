import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/models/trophies.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/me_repository.dart';
import 'package:flutter_client/features/profile/avatar_picker_screen.dart';
import 'package:flutter_client/features/profile/custom_avatar.dart';
import 'package:flutter_client/features/profile/profile_screen.dart';
import 'package:flutter_client/features/profile/profile_setup_screen.dart';
import 'package:flutter_client/features/profile/sticker_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthState;
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';
import 'data/models_test.dart' show meJson;
import 'safety_test.dart' show frames;

/// Вертикальна прокрутка вкладки «Профіль» (усередині є горизонтальний ряд трофеїв).
final profileScroll = find.descendant(of: find.byKey(const ValueKey('profile-list')), matching: find.byType(Scrollable)).first;

Map<String, dynamic> registered({String? handle = 'Олена_лісова', bool handleAllowed = true}) => {
      ...meJson(region: {'id': 1, 'slug': 'zhytomyrska', 'name': 'Житомирська область'}),
      'is_guest': false,
      'name': 'Олена Лісова',
      'handle': handle,
      'avatar': {'kind': 'custom', 'sticker': 'wow', 'hat': null, 'item': null, 'fx': null},
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
  Future<void> setCustomAvatar(Map<String, String?> parts) async => calls.add('custom:${parts['sticker']}:${parts['hat']}:${parts['fx']}');
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

/// Каталог конструктора, як віддає сервер (скорочено).
Map<String, dynamic> catalogJson() => {
      'categories': [
        {
          'id': 'sticker', 'label': 'Персонаж', 'optional': false,
          'parts': [
            {'id': 'kind', 'label': 'Добряк', 'open': true, 'badge': null, 'lock_label': null},
            {'id': 'wow', 'label': 'Здивована', 'open': true, 'badge': null, 'lock_label': null},
            {'id': 'dizzy', 'label': 'Запаморочений', 'open': true, 'badge': null, 'lock_label': null},
            {'id': 'excited', 'label': 'Захоплений', 'open': true, 'badge': 'За рівень «Слідопит»', 'lock_label': null},
            {'id': 'cosmic', 'label': 'Космічний', 'open': false, 'badge': null, 'lock_label': 'У Pro'},
          ],
        },
        {
          'id': 'hat', 'label': 'Капелюх', 'optional': true,
          'parts': [
            {'id': 'cap', 'label': 'Кепка', 'open': true, 'badge': null, 'lock_label': null},
            {'id': 'ranger', 'label': 'Лісника', 'open': true, 'badge': 'За рівень «Лісовик»', 'lock_label': null},
            {'id': 'wizard', 'label': 'Чарівника', 'open': false, 'badge': null, 'lock_label': '80 спор — скоро'},
          ],
        },
        {
          'id': 'item', 'label': 'Річ', 'optional': true,
          'parts': [
            {'id': 'basket', 'label': 'Кошик', 'open': true, 'badge': null, 'lock_label': null},
          ],
        },
        {
          'id': 'fx', 'label': 'Ефект', 'optional': true,
          'parts': [
            {'id': 'hearts', 'label': 'Сердечка', 'open': true, 'badge': null, 'lock_label': null},
          ],
        },
      ],
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('Профіль із сервера: нік, аватар, рівень, крок «profile»', () {
    final me = Me.fromJson(registered());
    expect([me.handle, me.avatar.isCustom, me.avatar.parts['sticker'], me.level!.label], ['Олена_лісова', true, 'wow', 'Слідопит']);
    expect(me.level!.progress(120), closeTo((120 - 51) / 150, 1e-9));
    expect(Me.fromJson(meJson(nextStep: 'profile')).onboarding.nextStep, OnboardingStep.profile);
    expect(Me.fromJson(meJson()).avatar.kind, 'standard'); // старий сервер без аватара
  });

  late FakeMe fake;
  late List<String> checked;
  var available = true;

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
        avatarCatalogProvider.overrideWith((ref) async => AvatarCatalog.fromJson(catalogJson())),
        trophiesProvider.overrideWith((ref) async => TrophiesOverview.fromJson(trophiesJson())),
        if (auth != null) authStateProvider.overrideWith((ref) => auth),
      ],
      child: MaterialApp(home: home),
    );
  }

  testWidgets('Профіль: ім\'я, @нік, рівень із прогресом; аватар — до наліпок', (tester) async {
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
    expect(find.text('7 знахідок'), findsOneWidget);
    expect(find.text('120 балів'), findsOneWidget);
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
    // Область — лише мені, у налаштуваннях (у публічному профілі її немає).
    await tester.scrollUntilVisible(find.byKey(const ValueKey('profile-region')), 200, scrollable: profileScroll);
    expect(find.text('Житомирська область'), findsOneWidget);

    await tester.drag(find.byKey(const ValueKey('profile-list')), const Offset(0, 3000));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('profile-avatar')));
    await frames(tester);
    expect(find.byKey(const ValueKey('part-sticker-wow')), findsOneWidget);
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
    // Офлайн дані — згорнуті під кнопкою; натиснули — список.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('profile-offline')), 200, scrollable: profileScroll);
    expect(find.byKey(const ValueKey('data-map')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('profile-offline')));
    await frames(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('data-ai')), 200, scrollable: profileScroll);
    expect(find.byKey(const ValueKey('data-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-delete')), findsNothing);
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
    await tester.scrollUntilVisible(find.byKey(const ValueKey('profile-delete')), 300, scrollable: profileScroll);
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

  test('Аватар-наліпка: розбір і назад у JSON; кожен персонаж має малюнок', () {
    final a = Avatar.fromJson({'kind': 'custom', 'sticker': 'dizzy', 'hat': null, 'item': 'basket', 'fx': 'notes'});
    expect(a.isCustom, isTrue);
    expect(a.parts['sticker'], 'dizzy');
    expect(a.toJson(), {'kind': 'custom', 'sticker': 'dizzy', 'hat': null, 'item': 'basket', 'fx': 'notes'});
    expect(kStickers.length, inInclusiveRange(25, 30));
  });

  testWidgets('Наліпка малюється один раз і далі береться готовою (прокрутка не перемальовує)', (tester) async {
    const parts = {'sticker': 'dizzy', 'hat': 'cap', 'item': null, 'fx': 'notes'};
    final a = StickerCache.instance.image(parts, 120);
    expect(identical(StickerCache.instance.image(parts, 120), a), isTrue);
    expect(identical(StickerCache.instance.image(parts, 240), a), isFalse); // інший розмір — своя картинка
    expect([a.width, a.height], [120, 120]);
    await tester.pumpWidget(const MaterialApp(home: Center(child: StickerImage(parts, size: 60, opacity: 0.35))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Невідома деталь (новіша за застосунок) — малюється без неї, без збою', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CustomPaint(size: const Size(100, 100), painter: CustomAvatarPainter({...kDefaultAvatarParts, 'hat': 'unicorn_horn', 'sticker': 'new_one', 'fx': 'fireworks'})),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Конструктор: деталь змінює попередній перегляд; закрита — з причиною, не вибирається; «Зберегти»', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const AvatarPickerScreen(), registered()));
    await frames(tester);
    expect(find.byKey(const ValueKey('builder-preview')), findsOneWidget);
    expect(find.text('У Pro'), findsOneWidget);
    expect(find.text('За рівень «Слідопит»'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('part-sticker-cosmic')));
    await frames(tester);
    expect(find.textContaining('«Космічний» — У Pro'), findsOneWidget); // підказка, не вибір
    await tester.pump(const Duration(seconds: 5)); // підказка зникла — не закриває кнопку
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('part-sticker-dizzy')));
    await tester.tap(find.byKey(const ValueKey('cat-hat')));
    await frames(tester);
    expect(find.text('Без нічого'), findsOneWidget);
    expect(find.text('За рівень «Лісовик»'), findsOneWidget);
    expect(find.text('80 спор — скоро'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('part-hat-ranger')));
    await tester.tap(find.byKey(const ValueKey('cat-fx')));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('part-fx-hearts')));
    await tester.tap(find.byKey(const ValueKey('builder-save')));
    await frames(tester);
    expect(fake.calls, ['custom:dizzy:ranger:hearts']);
  });
}
