import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_app/core/app.dart';
import 'package:household_app/data/household_store.dart';

import '../data/household_store_test.dart' show MemoryStorage;

Future<void> openHomeTile(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
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
    await openHomeTile(tester, 'Chores');
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
    await openHomeTile(tester, 'Chores');
    await tester.tap(find.text('Add chore'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Sweep hallway');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save chore'));
    await tester.pumpAndSettle();
    expect(store.chores.any((c) => c.title == 'Sweep hallway'), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('local onboarding creates a household and opens home', (
    tester,
  ) async {
    final empty = HouseholdStore(MemoryStorage());
    await tester.pumpWidget(HouseholdApp(store: empty));
    await tester.pumpAndSettle();
    expect(find.textContaining('Daily Improvement'), findsOneWidget);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Taylor');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create household'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Oak House');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('Oak House'), findsOneWidget);
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
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('Chores'), findsOneWidget);
  });
  testWidgets('grocery workflow records buyer and updates fairness', (
    tester,
  ) async {
    await tester.pumpWidget(HouseholdApp(store: store));
    await tester.pumpAndSettle();
    await openHomeTile(tester, 'Groceries');
    expect(find.text('Milk'), findsOneWidget);

    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Dish soap');
    await tester.enterText(fields.at(1), '3');
    await tester.tap(find.widgetWithText(FilledButton, 'Add item'));
    await tester.pumpAndSettle();
    expect(store.groceries.any((g) => g.name == 'Dish soap'), isTrue);
    await tester.scrollUntilVisible(find.text('Dish soap'), 300);

    final dishSoapCard = find.ancestor(
      of: find.text('Dish soap'),
      matching: find.byType(Card),
    );
    final purchaseButton = find.descendant(
      of: dishSoapCard,
      matching: find.widgetWithText(FilledButton, 'Mark purchased'),
    );
    await tester.ensureVisible(purchaseButton);
    await tester.pumpAndSettle();
    await tester.tap(purchaseButton);
    await tester.pumpAndSettle();
    expect(store.purchases.single.itemName, 'Dish soap');
    expect(store.purchases.single.memberName, 'Alex');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await openHomeTile(tester, 'Progress');
    expect(store.contributions.length, 1);
    await tester.scrollUntilVisible(find.text('Dish soap'), 300);
    expect(find.text('Dish soap'), findsOneWidget);
    final undo = find.byTooltip('Undo Dish soap');
    await tester.ensureVisible(undo);
    await tester.pumpAndSettle();
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(store.purchases, isEmpty);
    expect(
      find.text('No recorded contributions in this period.'),
      findsOneWidget,
    );
  });
  testWidgets('reminders can be added and completed', (tester) async {
    await tester.pumpWidget(HouseholdApp(store: store));
    await tester.pumpAndSettle();
    await openHomeTile(tester, 'Reminders');
    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Pay water bill');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(store.reminders.any((r) => r.title == 'Pay water bill'), isTrue);
    await tester.scrollUntilVisible(find.text('Pay water bill'), 200);
    final reminderTile = find.ancestor(
      of: find.text('Pay water bill'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: reminderTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(
      store.reminders.firstWhere((r) => r.title == 'Pay water bill').completed,
      isTrue,
    );
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
      expect(tester.takeException(), isNull, reason: 'Overflow on Home screen');
      for (final screen in ['Chores', 'Groceries', 'Reminders', 'Progress']) {
        await openHomeTile(tester, screen);
        final exception = tester.takeException();
        expect(exception, isNull, reason: 'Overflow on $screen screen');
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Overflow on Settings screen',
      );
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
