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
}
