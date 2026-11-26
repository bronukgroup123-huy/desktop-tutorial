import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/me_repository.dart';
import 'package:flutter_client/features/profile/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';
import 'data/models_test.dart' show meJson;
import 'profile_test.dart' show FakeMe, registered;
import 'safety_test.dart' show frames;

/// B6.1: «Завантажити мої дані» в «Налаштуваннях» — і в акаунта, і в гостя.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late List<String> paths;
  late List<(String, String)> shared;

  Widget app(Map<String, dynamic> me, FakeResponse Function() respond) {
    paths = [];
    shared = [];
    final (api, _) = makeClient((r) {
      paths.add('${r.method} ${r.path}?${r.queryParameters.entries.map((e) => '${e.key}=${e.value}').join('&')}');
      return respond();
    });
    return ProviderScope(
      overrides: [
        meProvider.overrideWith(() => FakeMe(Me.fromJson(me))),
        meRepositoryProvider.overrideWithValue(MeRepository(api)),
        exportSharerProvider.overrideWithValue((name, content) async => shared.add((name, content))),
      ],
      child: const MaterialApp(home: ProfileSettingsScreen()),
    );
  }

  Future<void> tapExport(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.byKey(const ValueKey('settings-export')), 200,
        scrollable: find.descendant(of: find.byKey(const ValueKey('settings-list')), matching: find.byType(Scrollable)).first);
    await tester.tap(find.byKey(const ValueKey('settings-export')));
    await frames(tester);
  }

  testWidgets('Акаунт: файл із сервера віддається «Поділитися» з ім\'ям від сервера й читабельним JSON', (tester) async {
    await tester.pumpWidget(app(registered(), () => const FakeResponse(200, {
          'data': {
            'file_name': 'hrybnyi-radar-dani-2026-11-26.json',
            'export': {'format_version': 1, 'picks': [{'id': 'p1'}]},
          },
        })));
    await frames(tester);
    await tapExport(tester);
    expect(paths, ['GET /v1-me?export=1']);
    expect(shared, hasLength(1));
    expect(shared.single.$1, 'hrybnyi-radar-dani-2026-11-26.json');
    expect(jsonDecode(shared.single.$2), {'format_version': 1, 'picks': [{'id': 'p1'}]});
    expect(shared.single.$2, contains('\n  "format_version"')); // з відступами — людина може прочитати
  });

  testWidgets('Гість теж може завантажити свої дані', (tester) async {
    await tester.pumpWidget(app(meJson(region: {'id': 1, 'slug': 'zhytomyrska', 'name': 'Житомирська область'}),
        () => const FakeResponse(200, {'data': {'file_name': 'f.json', 'export': {'format_version': 1}}})));
    await frames(tester);
    expect(find.byKey(const ValueKey('profile-delete')), findsNothing);
    await tapExport(tester);
    expect(shared.single.$1, 'f.json');
  });

  testWidgets('Ліміт сервера — показуємо його текст, файл не ділимо', (tester) async {
    await tester.pumpWidget(app(registered(), () => const FakeResponse(429, {
          'error': 'rate_limited',
          'message': 'Забагато запитів. Спробуйте через 40 сек.',
        })));
    await frames(tester);
    await tapExport(tester);
    expect(shared, isEmpty);
    expect(find.textContaining('Спробуйте через 40 сек'), findsOneWidget);
  });
}
