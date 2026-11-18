import 'package:flutter/material.dart';
import 'package:flutter_client/features/auth/auth_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Екран входу: Google, Apple і без реєстрації (вхід за телефоном прибрано, ADR-021 §21.2.1)', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AuthScreen())));
    expect(find.text('Грибний Радар'), findsOneWidget);
    expect(find.text('Увійти через Google'), findsOneWidget);
    expect(find.text('Увійти через Apple'), findsOneWidget);
    expect(find.text('Увійти за номером телефону'), findsNothing);
    expect(find.text('Продовжити без реєстрації'), findsOneWidget);
  });
}
