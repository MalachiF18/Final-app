import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:household_app/data/household_store.dart';

class MemoryStorage implements HouseholdStorage {
  String? value;
  bool failRead = false, failWrite = false;
  Completer<void>? gate;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('read');
    return value;
  }

  @override
  Future<void> write(String data) async {
    if (gate != null) await gate!.future;
    if (failWrite) throw StateError('write');
    value = data;
  }
}

void main() {
  late MemoryStorage storage;
  late HouseholdStore store;
  var now = DateTime(2026, 11, 4, 12);
  setUp(() async {
    now = DateTime(2026, 11, 4, 12);
    storage = MemoryStorage();
    store = HouseholdStore(storage, clock: () => now);
    await store.load();
    await store.loadDemo();
  });
  Chore chore(String id) => store.chores.firstWhere((c) => c.id == id);
  test('rotates once and saves historical assignee and due date', () async {
    expect(await store.complete('demo-trash', 0), isTrue);
    expect(chore('demo-trash').assignee, 'jordan');
    expect(chore('demo-trash').due, DateTime(2026, 11, 11));
    expect(store.history.single.memberName, 'Alex');
    expect(store.history.single.due, DateTime(2026, 11, 4));
    expect(await store.complete('demo-trash', 0), isFalse);
    expect(store.history.length, 1);
  });
  test('concurrent duplicate requests commit one completion', () async {
    storage.gate = Completer<void>();
    final first = store.complete('demo-trash', 0);
    expect(await store.complete('demo-trash', 0), isFalse);
    storage.gate!.complete();
    expect(await first, isTrue);
    expect(store.history.length, 1);
  });
  test('one-time completion archives chore and cannot repeat', () async {
    expect(await store.complete('demo-filter', 0), isTrue);
    expect(chore('demo-filter').completed, isTrue);
    expect(await store.complete('demo-filter', 1), isFalse);
    expect(store.history.length, 1);
  });
  test(
    'overdue daily chore skips missed dates and rotates only once',
    () async {
      await store.selectMember('jordan');
      expect(await store.complete('demo-kitchen', 0), isTrue);
      expect(chore('demo-kitchen').due, DateTime(2026, 11, 5));
      expect(chore('demo-kitchen').assignee, 'sam');
      expect(store.history.length, 1);
    },
  );
  test('fixed recurring assignment never rotates', () async {
    await store.selectMember('sam');
    await store.complete('demo-plants', 0);
    expect(chore('demo-plants').assignee, 'sam');
    expect(chore('demo-plants').due, DateTime(2026, 11, 11));
  });
  test('monthly schedule clamps February then restores original day', () async {
    now = DateTime(2028, 1, 31);
    await store.saveChore(
      Chore(
        id: '',
        title: 'Monthly',
        due: now,
        assignee: 'alex',
        eligible: ['alex'],
        repeat: Repeat.monthly,
      ),
    );
    final id = store.chores.last.id;
    await store.complete(id, 0);
    expect(chore(id).due, DateTime(2028, 2, 29));
    now = DateTime(2028, 2, 29);
    await store.complete(id, 1);
    expect(chore(id).due, DateTime(2028, 3, 31));
  });
  test('departure rotates to next eligible and keeps history', () async {
    await store.complete('demo-trash', 0);
    await store.removeMember('jordan');
    expect(chore('demo-trash').assignee, 'sam');
    expect(chore('demo-trash').eligible, ['alex', 'sam']);
    expect(store.history.single.memberName, 'Alex');
  });
  test('fixed assignment becomes unassigned when member leaves', () async {
    await store.removeMember('sam');
    expect(chore('demo-plants').assignee, isNull);
    expect(chore('demo-plants').fixed, isTrue);
  });
  test('no eligible members leaves chore unassigned', () async {
    await store.removeMember('alex');
    await store.removeMember('jordan');
    await store.removeMember('sam');
    expect(chore('demo-trash').assignee, isNull);
    expect(store.currentMemberId, isNull);
    expect(
      await store.complete('demo-trash', chore('demo-trash').occurrence),
      isFalse,
    );
  });
  test('write failure rolls back completion and allows retry', () async {
    storage.failWrite = true;
    expect(await store.complete('demo-trash', 0), isFalse);
    expect(store.history, isEmpty);
    expect(chore('demo-trash').assignee, 'alex');
    storage.failWrite = false;
    expect(await store.complete('demo-trash', 0), isTrue);
  });
  test(
    'saved household survives restart and retains duplicate guard',
    () async {
      await store.complete('demo-filter', 0);
      final reopened = HouseholdStore(storage, clock: () => now);
      await reopened.load();
      expect(reopened.history.length, 1);
      expect(await reopened.complete('demo-filter', 0), isFalse);
      expect(reopened.householdName, 'Maple House · Demo');
    },
  );
  test('deleting and editing a chore preserve completion snapshots', () async {
    await store.complete('demo-trash', 0);
    final edited = Chore.fromJson(chore('demo-trash').toJson())
      ..title = 'New title';
    await store.saveChore(edited);
    await store.deleteChore('demo-trash');
    expect(store.history.single.title, 'Take out the trash');
  });
  test('editing invalidates stale completion actions', () async {
    final edited = Chore.fromJson(chore('demo-trash').toJson())
      ..title = 'Trash bins';
    expect(await store.saveChore(edited), isTrue);
    expect(await store.complete('demo-trash', 0), isFalse);
    expect(await store.complete('demo-trash', 1), isTrue);
  });
  test(
    'future chores and another roommates chores cannot be completed',
    () async {
      expect(await store.complete('demo-bathroom', 0), isFalse);
      expect(await store.complete('demo-plants', 0), isFalse);
      expect(store.history, isEmpty);
    },
  );
  test(
    'invalid assignments and empty titles do not change saved data',
    () async {
      final before = storage.value;
      final edited = Chore.fromJson(chore('demo-trash').toJson())
        ..eligible = ['sam'];
      expect(await store.saveChore(edited), isFalse);
      edited.eligible = ['alex'];
      edited.title = '  ';
      expect(await store.saveChore(edited), isFalse);
      expect(storage.value, before);
    },
  );
  test('failed or malformed reads surface recoverable errors', () async {
    storage.failRead = true;
    await store.load();
    expect(store.error, contains('Could not read'));
    storage.failRead = false;
    storage.value = '{broken';
    await store.load();
    expect(store.error, contains('Could not read'));
    storage.value = null;
    await store.load();
    expect(store.error, isNull);
  });

  test('grocery items can be added, edited, and removed', () async {
    expect(
      await store.saveGrocery(
        name: 'Dish soap',
        quantity: 2,
        category: GroceryCategory.household,
      ),
      isTrue,
    );
    final item = store.groceries.last;
    expect(item.name, 'Dish soap');
    expect(item.quantity, 2);
    expect(item.category, GroceryCategory.household);

    expect(
      await store.saveGrocery(
        id: item.id,
        name: 'Unscented dish soap',
        quantity: 3,
        category: GroceryCategory.household,
      ),
      isTrue,
    );
    expect(store.groceries.last.name, 'Unscented dish soap');
    expect(store.groceries.last.quantity, 3);
    expect(await store.deleteGrocery(item.id), isTrue);
    expect(store.groceries.any((g) => g.id == item.id), isFalse);
  });

  test('claims protect shoppers and purchases record the buyer once', () async {
    expect(await store.claimGrocery('demo-milk'), isTrue);
    expect(store.groceries.first.claimedBy, 'alex');
    await store.selectMember('jordan');
    expect(await store.markGroceryPurchased('demo-milk'), isFalse);
    expect(store.purchases, isEmpty);

    await store.selectMember('alex');
    expect(await store.markGroceryPurchased('demo-milk'), isTrue);
    expect(await store.markGroceryPurchased('demo-milk'), isFalse);
    expect(store.purchases.single.memberName, 'Alex');
    expect(store.purchases.single.quantity, 1);
    expect(store.contributions.single.kind, ContributionKind.grocery);
  });

  test(
    'undo purchase removes its contribution and restores needed item',
    () async {
      await store.markGroceryPurchased('demo-milk');
      final purchase = store.purchases.single;
      expect(await store.undoPurchase(purchase), isTrue);
      final item = store.groceries.firstWhere((g) => g.id == 'demo-milk');
      expect(item.purchased, isFalse);
      expect(item.claimedBy, 'alex');
      expect(store.purchases, isEmpty);
      expect(store.contributions, isEmpty);
    },
  );

  test('undo chore completion restores schedule and fairness total', () async {
    await store.complete('demo-trash', 0);
    final completion = store.history.single;
    expect(store.contributions.length, 1);
    expect(await store.undoCompletion(completion), isTrue);
    expect(store.history, isEmpty);
    expect(store.contributions, isEmpty);
    expect(chore('demo-trash').due, DateTime(2026, 11, 4));
    expect(chore('demo-trash').assignee, 'alex');
    expect(chore('demo-trash').occurrence, 0);
  });

  test('weekly and monthly totals use recorded completion dates', () async {
    await store.complete('demo-trash', 0);
    await store.markGroceryPurchased('demo-milk');
    expect(store.contributionsFor(ContributionWindow.week).length, 2);
    expect(store.contributionsFor(ContributionWindow.month).length, 2);
    expect(
      store.contributionsFor(
        ContributionWindow.month,
        anchor: DateTime(2026, 12, 1),
      ),
      isEmpty,
    );
  });

  test('a second app instance refreshes newer grocery changes', () async {
    final second = HouseholdStore(storage, clock: () => now);
    await second.load();
    expect(second.groceries.length, 3);
    await store.saveGrocery(
      name: 'Laundry detergent',
      quantity: 1,
      category: GroceryCategory.household,
    );
    expect(second.groceries.any((g) => g.name == 'Laundry detergent'), isFalse);
    expect(await second.sync(), isTrue);
    expect(second.groceries.any((g) => g.name == 'Laundry detergent'), isTrue);
  });

  test('reminders can be created, edited, completed, and removed', () async {
    final due = DateTime(2026, 11, 5, 18, 30);
    expect(await store.saveReminder(title: 'Pay water bill', due: due), isTrue);
    final reminder = store.reminders.last;
    expect(reminder.createdBy, 'alex');
    expect(reminder.due, due);
    expect(
      await store.saveReminder(
        id: reminder.id,
        title: 'Pay utility bill',
        due: due.add(const Duration(hours: 1)),
      ),
      isTrue,
    );
    expect(store.reminders.last.title, 'Pay utility bill');
    expect(await store.toggleReminder(reminder.id), isTrue);
    expect(store.reminders.last.completed, isTrue);
    expect(await store.deleteReminder(reminder.id), isTrue);
    expect(store.reminders.any((r) => r.id == reminder.id), isFalse);
  });

  test('household profile, name, and reminder settings persist', () async {
    final freshStorage = MemoryStorage();
    final fresh = HouseholdStore(freshStorage, clock: () => now);
    await fresh.load();
    expect(await fresh.createHousehold('Taylor', 'Oak House'), isTrue);
    expect(await fresh.setRemindersEnabled(false), isTrue);
    expect(await fresh.renameHousehold('Oak Street House'), isTrue);

    final reopened = HouseholdStore(freshStorage, clock: () => now);
    await reopened.load();
    expect(reopened.householdName, 'Oak Street House');
    expect(reopened.activeMembers.single.name, 'Taylor');
    expect(reopened.remindersEnabled, isFalse);
  });
}
