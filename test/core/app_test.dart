import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_app/core/app.dart';
import 'package:household_app/data/household_store.dart';

import '../data/household_store_test.dart' show MemoryStorage;

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  late HouseholdStore store;
  late MemoryStorage storage;
  setUp(() async {
    storage = MemoryStorage();
    store = HouseholdStore(storage, clock: () => DateTime(2026, 11, 4));
    await store.load();
    await store.loadDemo();
  });
  testWidgets('dashboard, personal filter, completion, and history work', (
    tester,
  ) async {
    await tester.pumpWidget(HouseholdApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Clean the kitchen'), findsOneWidget);
    await tester.tap(find.text('My Responsibilities'));
    await tester.pumpAndSettle();
    expect(find.text('Clean the kitchen'), findsNothing);
    expect(find.text('Take out the trash'), findsOneWidget);
    await tester.tap(find.text('Mark complete').first);
    await tester.pumpAndSettle();
    expect(store.history.length, 1);
    await tester.tap(find.byTooltip('Completion history'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Originally due'), findsOneWidget);
  });
  testWidgets('add and edit chore form persists changes', (tester) async {
    await tester.pumpWidget(HouseholdApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add chore'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Sweep hallway');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save chore'));
    await tester.pumpAndSettle();
    expect(store.chores.any((c) => c.title == 'Sweep hallway'), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty household explains setup', (tester) async {
    final empty = HouseholdStore(MemoryStorage());
    await tester.pumpWidget(HouseholdApp(store: empty));
    await tester.pumpAndSettle();
    expect(find.textContaining('Welcome home'), findsOneWidget);
    await tapTab(tester, 'Household');
    expect(find.text('Add roommate'), findsOneWidget);
  });
  testWidgets('load error offers retry and preserves stored data', (
    tester,
  ) async {
    storage.failRead = true;
    await tester.pumpWidget(HouseholdApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    storage.failRead = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Take out the trash'), findsOneWidget);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('360px screen with text scale $scale has no overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(HouseholdApp(store: store));
      await tester.pumpAndSettle();
      for (final tab in ['Chores', 'Fairness', 'Household', 'Groceries']) {
        await tapTab(tester, tab);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('dashboard meets labeled tap target and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(HouseholdApp(store: store));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });
}
