import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_app/core/app.dart';

// Tap a destination in the bottom bar (the label also appears in the AppBar).
Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts on Chores', (tester) async {
    await tester.pumpWidget(const HouseholdApp());

    expect(find.textContaining('card 2.1'), findsOneWidget);
  });

  testWidgets('tapping each tab shows that screen', (tester) async {
    await tester.pumpWidget(const HouseholdApp());

    await _tapTab(tester, 'Groceries');
    expect(find.textContaining('card 3.1'), findsOneWidget);

    await _tapTab(tester, 'Fairness');
    expect(find.textContaining('card 3.8'), findsOneWidget);

    await _tapTab(tester, 'Household');
    expect(find.textContaining('cards 1.5'), findsOneWidget);
  });

  testWidgets('400x800 surface has no overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const HouseholdApp());
    // An overflow is reported as a framework exception; none may be pending.
    expect(tester.takeException(), isNull);

    for (final tab in ['Groceries', 'Fairness', 'Household', 'Chores']) {
      await _tapTab(tester, tab);
      expect(tester.takeException(), isNull);
    }
  });
}
