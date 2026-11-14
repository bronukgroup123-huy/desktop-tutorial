import 'dart:async';
import 'dart:io';

import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/auth_repository.dart';
import 'package:flutter_client/data/repositories/me_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_adapter.dart';
import 'models_test.dart' show meJson;

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.userId);

  @override
  final String? userId;

  @override
  bool get isSignedIn => userId != null;

  @override
  String? get accessToken => userId == null ? null : 'token';

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _me(String slug) => meJson(region: {'id': 10, 'slug': slug, 'name': slug});

void main() {
  late Directory dir;
  late LocalStore store;
  var online = true;
  var slug = 'kyivska';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mr_me_');
    store = LocalStore(dir);
    online = true;
    slug = 'kyivska';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FakeResponse server(_) => online ? FakeResponse(200, {'data': _me(slug)}) : const FakeResponse.offline();

  MeRepository repo(String? uid) => MeRepository(makeClient(server).$1, store: store, userId: () => uid);

  group('MeRepository: профіль на телефоні', () {
    test('відповідь сервера зберігається і є без інтернету', () async {
      expect((await repo('u1').fetchMe()).homeRegion!.slug, 'kyivska');
      online = false;
      expect((await repo('u1').cached())!.homeRegion!.slug, 'kyivska');
      expect((await repo('u1').fetchMeOrCached()).homeRegion!.slug, 'kyivska');
    });

    test('профіль іншого користувача не віддається', () async {
      await repo('u1').fetchMe();
      expect(await repo('u2').cached(), isNull);
      online = false;
      await expectLater(repo('u2').fetchMeOrCached(), throwsA(anything));
    });

    test('зміна профілю (PATCH) теж оновлює збережену копію', () async {
      await repo('u1').fetchMe();
      slug = 'lvivska';
      await repo('u1').changeRegion('lvivska');
      expect((await repo('u1').cached())!.homeRegion!.slug, 'lvivska');
    });
  });

  group('meProvider: вхід без інтернету', () {
    ProviderContainer container(String uid) => ProviderContainer(overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuth(uid)),
          meRepositoryProvider.overrideWithValue(repo(uid)),
        ]);

    test('офлайн — застосунок відкривається зі збереженим профілем', () async {
      await repo('u1').fetchMe();
      online = false;
      final c = container('u1');
      addTearDown(c.dispose);
      final me = await c.read(meProvider.future);
      expect(me!.homeRegion!.slug, 'kyivska');
    });

    test('онлайн — збережений одразу, свіжий із сервера підміняє його у фоні', () async {
      await repo('u1').fetchMe();
      slug = 'lvivska';
      final c = container('u1');
      addTearDown(c.dispose);
      final sub = c.listen(meProvider, (_, __) {});
      addTearDown(sub.close);
      expect((await c.read(meProvider.future))!.homeRegion!.slug, 'kyivska');
      for (var i = 0; i < 50 && c.read(meProvider).valueOrNull?.homeRegion?.slug != 'lvivska'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.read(meProvider).value!.homeRegion!.slug, 'lvivska');
    });

    test('перший запуск без інтернету і без збереженого профілю — помилка й «Повторити»', () async {
      online = false;
      final c = container('u1');
      addTearDown(c.dispose);
      await expectLater(c.read(meProvider.future), throwsA(anything));
    });
  });
}
