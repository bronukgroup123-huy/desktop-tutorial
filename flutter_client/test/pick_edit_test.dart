// B3.4: картка своєї точки — дії з сервера (опублікувати / сховати / змінити опис / видалити).
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/picks_repository.dart';
import 'package:flutter_client/features/picks/pick_card_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';
import 'profile_test.dart' show FakeMe, registered;

const pickId = '99999999-9999-4999-8999-999999999999';

Map<String, dynamic> card({List<String> actions = const [], String visibility = 'private', String? description}) => {
      'id': pickId,
      'lat': 50.45,
      'lng': 30.52,
      'is_exact': true,
      'is_mine': actions.isNotEmpty,
      'visibility': visibility,
      'species_id': 'boletus_edulis',
      'name_label': 'Білий гриб',
      'status_label': visibility == 'private' ? 'Приватна точка' : 'Перевіряється',
      'marker_color': '#9e9e9e',
      'description': description,
      'date_label': '10 листопада 2026 р.',
      'captured_at': null,
      'photo_url': null,
      'disclaimer_label': null,
      'actions': actions,
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late List<RequestOptions> sent;

  Widget app(Map<String, dynamic> cardJson, {FakeResponse Function(RequestOptions r)? onWrite}) {
    final (api, adapter) = makeClient((r) {
      if (r.method == 'GET') return FakeResponse(200, {'data': cardJson});
      return onWrite?.call(r) ??
          FakeResponse(200, {
            'data': r.method == 'DELETE'
                ? {'deleted': true}
                : {'id': pickId, 'visibility': 'public', 'status_label': 'Перевіряється', 'marker_color': '#9e9e9e', 'description': null},
          });
    });
    sent = adapter.requests;
    return ProviderScope(
      overrides: [
        picksRepositoryProvider.overrideWithValue(PicksRepository(api, uploads: Dio())),
        meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => showPickCard(context, pickId), child: const Text('open')),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.tap(find.text('open'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  List<RequestOptions> writes() => sent.where((r) => r.method != 'GET').toList();

  testWidgets('чужа точка — без кнопок дій', (tester) async {
    await tester.pumpWidget(app(card()));
    await open(tester);
    expect(find.text('Білий гриб'), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-delete')), findsNothing);
    expect(find.byKey(const ValueKey('pick-make-public')), findsNothing);
  });

  testWidgets('своя приватна: «Зробити публічною» — підтвердження і PATCH visibility=public', (tester) async {
    await tester.pumpWidget(app(card(actions: ['make_public', 'edit_description', 'delete'])));
    await open(tester);
    expect(find.byKey(const ValueKey('pick-make-private')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pick-make-public')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Місце покажемо приблизно'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick-confirm')));
    await tester.pumpAndSettle();
    final w = writes().single;
    expect([w.method, w.path], ['PATCH', '/v1-picks/$pickId']);
    expect(jsonDecode(w.data is String ? w.data as String : jsonEncode(w.data)), {'visibility': 'public'});
    expect(find.text('Точку опубліковано'), findsOneWidget);
  });

  testWidgets('відмова сервера (ліміт) — показуємо його текст', (tester) async {
    await tester.pumpWidget(app(
      card(actions: ['make_public', 'edit_description', 'delete']),
      onWrite: (_) => const FakeResponse(429, {'error': 'weekly_limit_reached', 'message': 'Ліміт — 7 публічних точок за 7 днів.'}),
    ));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('pick-make-public')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ліміт — 7 публічних точок'), findsOneWidget);
  });

  testWidgets('змінити опис: діалог із поточним текстом → PATCH description; порожній — null', (tester) async {
    await tester.pumpWidget(app(card(actions: ['make_private', 'edit_description', 'delete'], visibility: 'public', description: 'Під сосною')));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('pick-edit-description')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Під сосною'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pick-description-field')), '   ');
    await tester.tap(find.byKey(const ValueKey('pick-description-save')));
    await tester.pumpAndSettle();
    final w = writes().single;
    expect(jsonDecode(w.data is String ? w.data as String : jsonEncode(w.data)), {'description': null});
  });

  testWidgets('видалити: підтвердження → DELETE, картка закривається', (tester) async {
    await tester.pumpWidget(app(card(actions: ['make_public', 'edit_description', 'delete'])));
    await open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('pick-delete')));
    await tester.tap(find.byKey(const ValueKey('pick-delete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Вона зникне з карти'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick-confirm')));
    await tester.pumpAndSettle();
    expect(writes().single.method, 'DELETE');
    expect(find.text('Білий гриб'), findsNothing); // аркуш закрито
    expect(find.text('Точку видалено'), findsOneWidget);
  });
}
