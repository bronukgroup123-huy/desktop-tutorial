import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/features/analysis/forest_refine_sheet.dart';

import 'data/analysis_test.dart' show resultJson;

const options = ForestEditOptions(
  species: [
    (code: 'pine', label: 'Сосна'),
    (code: 'spruce', label: 'Ялина'),
    (code: 'oak', label: 'Дуб'),
  ],
  presence: [
    (code: 'dominant', label: 'переважає'),
    (code: 'present', label: 'є місцями'),
  ],
);

/// Відкриває аркуш; результат потрапляє в [onResult], коли аркуш закрито.
Future<void> pumpSheet(WidgetTester tester, {ForestOverride? current, required void Function(ForestRefineChoice?) onResult}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => onResult(await showForestRefineSheet(
            context,
            result: AnalysisResult.fromJson(resultJson()),
            options: options,
            current: current,
            usageLabel: 'Уточнити ліс сьогодні можна ще 2 рази',
          )),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Уточнити ліс: до 2 порід на ліс, «ще є» з присутністю, зберегти', (tester) async {
    ForestRefineChoice? choice;
    await pumpSheet(tester, onResult: (c) => choice = c);

    expect(find.text('Сосновий ліс'), findsOneWidget);
    expect(find.text('Уточнити ліс сьогодні можна ще 2 рази'), findsOneWidget);
    // нічого не обрано — зберегти не можна; «скинути» немає (уточнення ще не було)
    final save = find.widgetWithText(FilledButton, 'Зберегти й переаналізувати');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(find.text('Скинути до карти'), findsNothing);

    // сосновому лісу — сосна + ялина; третя порода недоступна
    await tester.tap(find.byKey(const ValueKey('type-pine-pine')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('type-pine-spruce')));
    await tester.pump();
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('type-pine-oak'))).onSelected, isNull);

    // «ще є: дуб» — за замовчуванням «є місцями», змінюємо на «переважає»
    await tester.ensureVisible(find.byKey(const ValueKey('extra-oak')));
    await tester.tap(find.byKey(const ValueKey('extra-oak')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'переважає'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'переважає'));
    await tester.pump();

    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(choice!.override!.toJson(), {
      'types': [
        {
          'forest_type': 'pine',
          'species': ['pine', 'spruce'],
        },
      ],
      'extra': [
        {'species': 'oak', 'presence': 'dominant'},
      ],
    });
  });

  testWidgets('Уточнити ліс: є уточнення — «Скинути до карти» повертає override: null', (tester) async {
    ForestRefineChoice? choice;
    var closed = false;
    await pumpSheet(
      tester,
      current: const ForestOverride(types: {
        'pine': ['pine'],
      }),
      onResult: (c) {
        choice = c;
        closed = true;
      },
    );
    // наявне уточнення підставлене
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('type-pine-pine'))).selected, isTrue);
    await tester.ensureVisible(find.text('Скинути до карти'));
    await tester.tap(find.text('Скинути до карти'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(choice, isNotNull);
    expect(choice!.override, isNull);
  });
}
