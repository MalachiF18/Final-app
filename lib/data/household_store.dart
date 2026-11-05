import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef Json = Map<String, dynamic>;
DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);
String dateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

enum Repeat { once, daily, weekly, monthly }

enum GroceryCategory {
  produce,
  pantry,
  dairy,
  frozen,
  household,
  personal,
  other,
}

extension GroceryCategoryLabel on GroceryCategory {
  String get label => switch (this) {
    GroceryCategory.produce => 'Produce',
    GroceryCategory.pantry => 'Pantry',
    GroceryCategory.dairy => 'Dairy',
    GroceryCategory.frozen => 'Frozen',
    GroceryCategory.household => 'Household supplies',
    GroceryCategory.personal => 'Personal care',
    GroceryCategory.other => 'Other',
  };
}

enum ContributionKind { chore, grocery }

enum ContributionWindow { week, month }

class Member {
  Member(this.id, this.name, {this.active = true});
  final String id;
  final String name;
  bool active;
  Json toJson() => {'id': id, 'name': name, 'active': active};
  factory Member.fromJson(Json j) =>
      Member(j['id'], j['name'], active: j['active']);
}

class Chore {
  Chore({
    required this.id,
    required this.title,
    required this.due,
    required this.assignee,
    required this.eligible,
    this.repeat = Repeat.once,
    this.fixed = false,
    this.completed = false,
    this.occurrence = 0,
    int? anchorDay,
  }) : anchorDay = anchorDay ?? due.day;
  final String id;
  String title;
  DateTime due;
  String? assignee;
  List<String> eligible;
  Repeat repeat;
  bool fixed;
  bool completed;
  int occurrence;
  int anchorDay;
  Json toJson() => {
    'id': id,
    'title': title,
    'due': dateLabel(due),
    'assignee': assignee,
    'eligible': eligible,
    'repeat': repeat.name,
    'fixed': fixed,
    'completed': completed,
    'occurrence': occurrence,
    'anchorDay': anchorDay,
  };
  factory Chore.fromJson(Json j) => Chore(
    id: j['id'],
    title: j['title'],
    due: DateTime.parse(j['due']),
    assignee: j['assignee'],
    eligible: List<String>.from(j['eligible']),
    repeat: Repeat.values.byName(j['repeat']),
    fixed: j['fixed'],
    completed: j['completed'],
    occurrence: j['occurrence'],
    anchorDay: j['anchorDay'],
  );
}

class Completion {
  Completion({
    required this.choreId,
    required this.title,
    required this.memberName,
    required this.memberId,
    required this.due,
    required this.at,
    required this.occurrence,
  });
  final String choreId, title, memberName, memberId;
  final DateTime due, at;
  final int occurrence;
  Json toJson() => {
    'choreId': choreId,
    'title': title,
    'memberName': memberName,
    'memberId': memberId,
    'due': dateLabel(due),
    'at': at.toIso8601String(),
    'occurrence': occurrence,
  };
  factory Completion.fromJson(Json j) => Completion(
    choreId: j['choreId'],
    title: j['title'],
    memberName: j['memberName'],
    memberId: j['memberId'],
    due: DateTime.parse(j['due']),
    at: DateTime.parse(j['at']),
    occurrence: j['occurrence'],
  );
}

class GroceryItem {
  GroceryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.claimedBy,
    this.purchasedBy,
    this.purchasedAt,
    this.purchaseId,
  });
  final String id;
  String name;
  int quantity;
  GroceryCategory category;
  String? claimedBy;
  String? purchasedBy;
  DateTime? purchasedAt;
  String? purchaseId;
  final DateTime createdAt;
  DateTime updatedAt;
  bool get purchased => purchasedAt != null;
  Json toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'category': category.name,
    'claimedBy': claimedBy,
    'purchasedBy': purchasedBy,
    'purchasedAt': purchasedAt?.toIso8601String(),
    'purchaseId': purchaseId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory GroceryItem.fromJson(Json j) => GroceryItem(
    id: j['id'],
    name: j['name'],
    quantity: j['quantity'],
    category: GroceryCategory.values.byName(j['category']),
    claimedBy: j['claimedBy'],
    purchasedBy: j['purchasedBy'],
    purchasedAt: j['purchasedAt'] == null
        ? null
        : DateTime.parse(j['purchasedAt']),
    purchaseId: j['purchaseId'],
    createdAt: DateTime.parse(j['createdAt']),
    updatedAt: DateTime.parse(j['updatedAt']),
  );
}

class Purchase {
  Purchase({
    required this.id,
    required this.groceryId,
    required this.itemName,
    required this.quantity,
    required this.category,
    required this.memberName,
    required this.memberId,
    required this.at,
  });
  final String id, groceryId, itemName, memberName, memberId;
  final int quantity;
  final GroceryCategory category;
  final DateTime at;
  Json toJson() => {
    'id': id,
    'groceryId': groceryId,
    'itemName': itemName,
    'quantity': quantity,
    'category': category.name,
    'memberName': memberName,
    'memberId': memberId,
    'at': at.toIso8601String(),
  };
  factory Purchase.fromJson(Json j) => Purchase(
    id: j['id'],
    groceryId: j['groceryId'],
    itemName: j['itemName'],
    quantity: j['quantity'],
    category: GroceryCategory.values.byName(j['category']),
    memberName: j['memberName'],
    memberId: j['memberId'],
    at: DateTime.parse(j['at']),
  );
}

class Reminder {
  Reminder({
    required this.id,
    required this.title,
    required this.due,
    required this.createdBy,
    this.completed = false,
  });
  final String id;
  String title;
  DateTime due;
  String? createdBy;
  bool completed;
  Json toJson() => {
    'id': id,
    'title': title,
    'due': due.toIso8601String(),
    'createdBy': createdBy,
    'completed': completed,
  };
  factory Reminder.fromJson(Json j) => Reminder(
    id: j['id'],
    title: j['title'],
    due: DateTime.parse(j['due']),
    createdBy: j['createdBy'],
    completed: j['completed'] ?? false,
  );
}

class Contribution {
  const Contribution({
    required this.id,
    required this.kind,
    required this.title,
    required this.memberName,
    required this.memberId,
    required this.at,
  });
  final String id, title, memberName, memberId;
  final ContributionKind kind;
  final DateTime at;
  int get points => 1;
}

abstract class HouseholdStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class LocalHouseholdStorage implements HouseholdStorage {
  static const key = 'household.v1';
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  @override
  Future<String?> read() => _prefs.getString(key);
  @override
  Future<void> write(String value) => _prefs.setString(key, value);
}

/// One local household. Writes are serialized and published only after storage
/// succeeds. This is not authentication or multi-device synchronization.
class HouseholdStore extends ChangeNotifier {
  HouseholdStore(this.storage, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final HouseholdStorage storage;
  final DateTime Function() clock;
  List<Member> _members = [];
  List<Chore> _chores = [];
  List<Completion> _history = [];
  List<GroceryItem> _groceries = [];
  List<Purchase> _purchases = [];
  List<Reminder> _reminders = [];
  int _revision = 0;
  String? currentMemberId;
  String householdName = 'My household';
  bool loading = true, busy = false;
  String? error;
  DateTime? lastSyncedAt;
  bool remindersEnabled = true;
  int _serial = 0;
  List<Member> get members => List.unmodifiable(_members);
  List<Member> get activeMembers => _members.where((m) => m.active).toList();
  List<Chore> get chores => List.unmodifiable(_chores);
  List<Completion> get history => List.unmodifiable(_history.reversed);
  List<GroceryItem> get groceries => List.unmodifiable(_groceries);
  List<Purchase> get purchases => List.unmodifiable(_purchases.reversed);
  List<Reminder> get reminders => List.unmodifiable(_reminders);
  List<Contribution> get contributions {
    final result = <Contribution>[
      for (final h in _history)
        Contribution(
          id: 'chore:${h.choreId}:${h.occurrence}',
          kind: ContributionKind.chore,
          title: h.title,
          memberName: h.memberName,
          memberId: h.memberId,
          at: h.at,
        ),
      for (final p in _purchases)
        Contribution(
          id: 'grocery:${p.id}',
          kind: ContributionKind.grocery,
          title: p.itemName,
          memberName: p.memberName,
          memberId: p.memberId,
          at: p.at,
        ),
    ];
    result.sort((a, b) => b.at.compareTo(a.at));
    return List.unmodifiable(result);
  }

  String memberName(String? id) =>
      _members.where((m) => m.id == id).firstOrNull?.name ?? 'Unassigned';
  String _id() => '${clock().microsecondsSinceEpoch}-${_serial++}';
  Json _json() => {
    'version': 3,
    'revision': _revision,
    'name': householdName,
    'currentMemberId': currentMemberId,
    'members': _members.map((m) => m.toJson()).toList(),
    'chores': _chores.map((c) => c.toJson()).toList(),
    'history': _history.map((h) => h.toJson()).toList(),
    'groceries': _groceries.map((g) => g.toJson()).toList(),
    'purchases': _purchases.map((p) => p.toJson()).toList(),
    'reminders': _reminders.map((r) => r.toJson()).toList(),
    'remindersEnabled': remindersEnabled,
  };
  void _restore(Json j) {
    final version = j['version'];
    if (version != 1 && version != 2 && version != 3) {
      throw const FormatException('Unsupported saved data');
    }
    _revision = j['revision'] ?? 0;
    householdName = j['name'];
    currentMemberId = j['currentMemberId'];
    _members = (j['members'] as List).map((m) => Member.fromJson(m)).toList();
    _chores = (j['chores'] as List).map((c) => Chore.fromJson(c)).toList();
    _history = (j['history'] as List)
        .map((h) => Completion.fromJson(h))
        .toList();
    _groceries = version == 1
        ? []
        : (j['groceries'] as List).map((g) => GroceryItem.fromJson(g)).toList();
    _purchases = version == 1
        ? []
        : (j['purchases'] as List).map((p) => Purchase.fromJson(p)).toList();
    _reminders = version == 3
        ? (j['reminders'] as List).map((r) => Reminder.fromJson(r)).toList()
        : [];
    remindersEnabled = version == 3 ? j['remindersEnabled'] ?? true : true;
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final saved = await storage.read();
      if (saved != null) _restore(jsonDecode(saved));
      lastSyncedAt = clock();
    } catch (_) {
      error =
          'Could not read your saved household. Retry before making changes.';
    }
    loading = false;
    notifyListeners();
  }

  Future<bool> _change(void Function() action) async {
    if (busy || loading) return false;
    final previous = jsonEncode(_json());
    busy = true;
    error = null;
    notifyListeners();
    try {
      action();
      _revision++;
      await storage.write(jsonEncode(_json()));
      lastSyncedAt = clock();
      return true;
    } on ArgumentError catch (e) {
      _restore(jsonDecode(previous));
      error = e.message.toString();
      return false;
    } catch (_) {
      _restore(jsonDecode(previous));
      error =
          'Could not save changes. Your previous data is unchanged. Try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Refreshes this app instance from newer data in the same local store.
  /// This coordinates tabs/windows on one browser profile; it is not a
  /// cross-device backend.
  Future<bool> sync() async {
    if (busy || loading) return false;
    try {
      final saved = await storage.read();
      if (saved == null) return false;
      final remote = jsonDecode(saved) as Json;
      final remoteRevision = remote['revision'] ?? 0;
      if (remoteRevision > _revision) {
        _restore(remote);
        notifyListeners();
      }
      lastSyncedAt = clock();
      return true;
    } catch (_) {
      error = 'Could not refresh shared changes. Try again.';
      notifyListeners();
      return false;
    }
  }

  List<Contribution> contributionsFor(
    ContributionWindow window, {
    DateTime? anchor,
  }) {
    final value = day(anchor ?? clock());
    final start = switch (window) {
      ContributionWindow.week => value.subtract(
        Duration(days: value.weekday - DateTime.monday),
      ),
      ContributionWindow.month => DateTime(value.year, value.month),
    };
    final end = switch (window) {
      ContributionWindow.week => start.add(const Duration(days: 7)),
      ContributionWindow.month => DateTime(start.year, start.month + 1),
    };
    return contributions
        .where((c) => !c.at.isBefore(start) && c.at.isBefore(end))
        .toList();
  }

  Future<bool> addMember(String name) => _change(() {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60) {
      throw ArgumentError('Enter a name between 1 and 60 characters.');
    }
    if (activeMembers.any(
      (m) => m.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      throw ArgumentError('That roommate already exists.');
    }
    final member = Member(_id(), trimmed);
    _members.add(member);
    currentMemberId ??= member.id;
  });

  Future<bool> createHousehold(String memberName, String name) => _change(() {
    final trimmedMember = memberName.trim();
    final trimmedName = name.trim();
    if (trimmedMember.isEmpty || trimmedMember.length > 60) {
      throw ArgumentError('Enter your name between 1 and 60 characters.');
    }
    if (trimmedName.isEmpty || trimmedName.length > 80) {
      throw ArgumentError(
        'Enter a household name between 1 and 80 characters.',
      );
    }
    final member = Member(_id(), trimmedMember);
    householdName = trimmedName;
    _members = [member];
    currentMemberId = member.id;
    _chores = [];
    _history = [];
    _groceries = [];
    _purchases = [];
    _reminders = [];
  });

  Future<bool> renameHousehold(String name) => _change(() {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError(
        'Enter a household name between 1 and 80 characters.',
      );
    }
    householdName = trimmed;
  });

  Future<bool> setRemindersEnabled(bool enabled) => _change(() {
    remindersEnabled = enabled;
  });
  Future<bool> selectMember(String id) => _change(() {
    if (!activeMembers.any((m) => m.id == id)) {
      throw ArgumentError('Choose an active roommate.');
    }
    currentMemberId = id;
  });
  Future<bool> saveChore(Chore input) => _change(() {
    final c = Chore.fromJson(input.toJson());
    c.title = c.title.trim();
    if (c.title.isEmpty || c.title.length > 100) {
      throw ArgumentError('Enter a chore name between 1 and 100 characters.');
    }
    final active = activeMembers.map((m) => m.id).toSet();
    final selected = c.eligible.toSet();
    c.eligible = activeMembers
        .map((m) => m.id)
        .where(selected.contains)
        .toList();
    if (c.assignee == null || !active.contains(c.assignee)) {
      throw ArgumentError('Choose an active roommate.');
    }
    if (!c.fixed && !c.eligible.contains(c.assignee)) {
      throw ArgumentError(
        'The assigned roommate must be eligible for rotation.',
      );
    }
    final index = _chores.indexWhere((v) => v.id == c.id);
    if (index < 0) {
      _chores.add(
        Chore(
          id: _id(),
          title: c.title,
          due: day(c.due),
          assignee: c.assignee,
          eligible: c.eligible,
          repeat: c.repeat,
          fixed: c.fixed,
        ),
      );
    } else {
      // Invalidate any completion button rendered before this edit.
      c.occurrence = _chores[index].occurrence + 1;
      c.anchorDay = c.due.day;
      _chores[index] = c;
    }
  });
  Future<bool> deleteChore(String id) =>
      _change(() => _chores.removeWhere((c) => c.id == id));
  Future<bool> removeMember(String id) => _change(() {
    final member = _members.firstWhere((m) => m.id == id);
    member.active = false;
    for (final c in _chores.where((c) => !c.completed)) {
      final oldOrder = List<String>.from(c.eligible);
      c.eligible.remove(id);
      if (c.assignee == id) {
        c.assignee = c.fixed ? null : _next(oldOrder, id);
        c.occurrence++;
      }
    }
    for (final item in _groceries.where((g) => !g.purchased)) {
      if (item.claimedBy == id) {
        item.claimedBy = null;
        item.updatedAt = clock();
      }
    }
    if (currentMemberId == id) currentMemberId = activeMembers.firstOrNull?.id;
  });
  String? _next(List<String> order, String? current) {
    if (order.isEmpty) return null;
    final active = activeMembers.map((m) => m.id).toSet();
    final index = order.indexOf(current ?? '');
    for (var offset = 1; offset <= order.length; offset++) {
      final id = order[(index + offset) % order.length];
      if (active.contains(id)) return id;
    }
    return null;
  }

  Future<bool> complete(String id, int expectedOccurrence) => _change(() {
    final c = _chores.firstWhere((c) => c.id == id);
    if (c.completed ||
        c.occurrence != expectedOccurrence ||
        _history.any(
          (h) => h.choreId == id && h.occurrence == expectedOccurrence,
        )) {
      throw ArgumentError('This occurrence was already completed or changed.');
    }
    if (c.assignee == null || c.assignee != currentMemberId) {
      throw ArgumentError(
        'Switch to the assigned roommate to complete this chore.',
      );
    }
    if (day(c.due).isAfter(day(clock()))) {
      throw ArgumentError(
        'This chore can be completed on or after its due date.',
      );
    }
    _history.add(
      Completion(
        choreId: c.id,
        title: c.title,
        memberName: memberName(c.assignee),
        memberId: c.assignee!,
        due: c.due,
        at: clock(),
        occurrence: c.occurrence,
      ),
    );
    c.occurrence++;
    if (c.repeat == Repeat.once) {
      c.completed = true;
      return;
    }
    // Skip missed dates without fabricating completions or rotating extra turns.
    do {
      c.due = _advance(c);
    } while (!c.due.isAfter(day(clock())));
    if (!c.fixed) c.assignee = _next(c.eligible, c.assignee);
  });

  bool canUndoCompletion(Completion completion) {
    final chore = _chores.where((c) => c.id == completion.choreId).firstOrNull;
    if (chore == null || chore.occurrence != completion.occurrence + 1) {
      return false;
    }
    return !_history.any(
      (h) =>
          h.choreId == completion.choreId &&
          h.occurrence > completion.occurrence,
    );
  }

  Future<bool> undoCompletion(Completion completion) => _change(() {
    if (!canUndoCompletion(completion)) {
      throw ArgumentError(
        'This completion cannot be undone after the chore changed or was completed again.',
      );
    }
    final chore = _chores.firstWhere((c) => c.id == completion.choreId);
    chore.due = completion.due;
    chore.assignee = completion.memberId;
    chore.completed = false;
    chore.occurrence = completion.occurrence;
    _history.removeWhere(
      (h) =>
          h.choreId == completion.choreId &&
          h.occurrence == completion.occurrence,
    );
  });

  Future<bool> saveGrocery({
    String? id,
    required String name,
    required int quantity,
    required GroceryCategory category,
  }) => _change(() {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      throw ArgumentError('Enter an item name between 1 and 100 characters.');
    }
    if (quantity < 1 || quantity > 99) {
      throw ArgumentError('Choose a quantity between 1 and 99.');
    }
    final now = clock();
    if (id == null) {
      _groceries.add(
        GroceryItem(
          id: _id(),
          name: trimmed,
          quantity: quantity,
          category: category,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return;
    }
    final item = _groceries.firstWhere((g) => g.id == id);
    if (item.purchased) {
      throw ArgumentError('Undo the purchase before editing this item.');
    }
    item
      ..name = trimmed
      ..quantity = quantity
      ..category = category
      ..updatedAt = now;
  });

  Future<bool> deleteGrocery(String id) => _change(() {
    if (!_groceries.any((g) => g.id == id)) {
      throw ArgumentError('That item no longer exists.');
    }
    _groceries.removeWhere((g) => g.id == id);
  });

  Future<bool> claimGrocery(String id) => _change(() {
    final memberId = currentMemberId;
    if (memberId == null || !activeMembers.any((m) => m.id == memberId)) {
      throw ArgumentError('Choose an active roommate before claiming items.');
    }
    final item = _groceries.firstWhere((g) => g.id == id);
    if (item.purchased) throw ArgumentError('That item is already purchased.');
    if (item.claimedBy != null && item.claimedBy != memberId) {
      throw ArgumentError(
        '${memberName(item.claimedBy)} already claimed this item.',
      );
    }
    item
      ..claimedBy = memberId
      ..updatedAt = clock();
  });

  Future<bool> unclaimGrocery(String id) => _change(() {
    final item = _groceries.firstWhere((g) => g.id == id);
    if (item.purchased) throw ArgumentError('That item is already purchased.');
    if (item.claimedBy != currentMemberId) {
      throw ArgumentError(
        'Only the roommate who claimed this item can release it.',
      );
    }
    item
      ..claimedBy = null
      ..updatedAt = clock();
  });

  Future<bool> markGroceryPurchased(String id) => _change(() {
    final memberId = currentMemberId;
    if (memberId == null || !activeMembers.any((m) => m.id == memberId)) {
      throw ArgumentError(
        'Choose an active roommate before recording a purchase.',
      );
    }
    final item = _groceries.firstWhere((g) => g.id == id);
    if (item.purchased) throw ArgumentError('That item is already purchased.');
    if (item.claimedBy != null && item.claimedBy != memberId) {
      throw ArgumentError(
        '${memberName(item.claimedBy)} claimed this item. Ask them to release it first.',
      );
    }
    final now = clock();
    final purchaseId = _id();
    item
      ..claimedBy = memberId
      ..purchasedBy = memberId
      ..purchasedAt = now
      ..purchaseId = purchaseId
      ..updatedAt = now;
    _purchases.add(
      Purchase(
        id: purchaseId,
        groceryId: item.id,
        itemName: item.name,
        quantity: item.quantity,
        category: item.category,
        memberName: memberName(memberId),
        memberId: memberId,
        at: now,
      ),
    );
  });

  bool canUndoPurchase(Purchase purchase) {
    final item = _groceries
        .where((g) => g.id == purchase.groceryId)
        .firstOrNull;
    return item?.purchaseId == purchase.id;
  }

  Future<bool> undoPurchase(Purchase purchase) => _change(() {
    if (!canUndoPurchase(purchase)) {
      throw ArgumentError(
        'This purchase cannot be undone because the list item was removed or changed.',
      );
    }
    final item = _groceries.firstWhere((g) => g.id == purchase.groceryId);
    item
      ..claimedBy = purchase.memberId
      ..purchasedBy = null
      ..purchasedAt = null
      ..purchaseId = null
      ..updatedAt = clock();
    _purchases.removeWhere((p) => p.id == purchase.id);
  });

  Future<bool> saveReminder({
    String? id,
    required String title,
    required DateTime due,
  }) => _change(() {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      throw ArgumentError('Enter a reminder between 1 and 100 characters.');
    }
    if (id == null) {
      _reminders.add(
        Reminder(
          id: _id(),
          title: trimmed,
          due: due,
          createdBy: currentMemberId,
        ),
      );
      return;
    }
    final reminder = _reminders.firstWhere((r) => r.id == id);
    reminder
      ..title = trimmed
      ..due = due;
  });

  Future<bool> toggleReminder(String id) => _change(() {
    final reminder = _reminders.firstWhere((r) => r.id == id);
    reminder.completed = !reminder.completed;
  });

  Future<bool> deleteReminder(String id) => _change(() {
    if (!_reminders.any((r) => r.id == id)) {
      throw ArgumentError('That reminder no longer exists.');
    }
    _reminders.removeWhere((r) => r.id == id);
  });
  DateTime _advance(Chore c) {
    switch (c.repeat) {
      case Repeat.daily:
        return DateTime(c.due.year, c.due.month, c.due.day + 1);
      case Repeat.weekly:
        return DateTime(c.due.year, c.due.month, c.due.day + 7);
      case Repeat.monthly:
        final next = DateTime(c.due.year, c.due.month + 1);
        final last = DateTime(next.year, next.month + 1, 0).day;
        return DateTime(next.year, next.month, c.anchorDay.clamp(1, last));
      case Repeat.once:
        return c.due;
    }
  }

  Future<bool> loadDemo() => _change(() {
    householdName = 'Maple House · Demo';
    _members = [
      Member('alex', 'Alex'),
      Member('jordan', 'Jordan'),
      Member('sam', 'Sam'),
    ];
    currentMemberId = 'alex';
    _history = [];
    _purchases = [];
    remindersEnabled = true;
    final today = day(clock());
    final ids = _members.map((m) => m.id).toList();
    _chores = [
      Chore(
        id: 'demo-trash',
        title: 'Take out the trash',
        due: today,
        assignee: 'alex',
        eligible: List.of(ids),
        repeat: Repeat.weekly,
      ),
      Chore(
        id: 'demo-kitchen',
        title: 'Clean the kitchen',
        due: DateTime(today.year, today.month, today.day - 2),
        assignee: 'jordan',
        eligible: List.of(ids),
        repeat: Repeat.daily,
      ),
      Chore(
        id: 'demo-plants',
        title: 'Water the plants',
        due: today,
        assignee: 'sam',
        eligible: ['sam'],
        fixed: true,
        repeat: Repeat.weekly,
      ),
      Chore(
        id: 'demo-bathroom',
        title: 'Clean the bathroom',
        due: DateTime(today.year, today.month, today.day + 2),
        assignee: 'alex',
        eligible: List.of(ids),
        repeat: Repeat.weekly,
      ),
      Chore(
        id: 'demo-filter',
        title: 'Replace the air filter',
        due: today,
        assignee: 'alex',
        eligible: List.of(ids),
      ),
    ];
    _groceries = [
      GroceryItem(
        id: 'demo-milk',
        name: 'Milk',
        quantity: 1,
        category: GroceryCategory.dairy,
        createdAt: clock(),
        updatedAt: clock(),
      ),
      GroceryItem(
        id: 'demo-bananas',
        name: 'Bananas',
        quantity: 6,
        category: GroceryCategory.produce,
        createdAt: clock(),
        updatedAt: clock(),
      ),
      GroceryItem(
        id: 'demo-towels',
        name: 'Paper towels',
        quantity: 2,
        category: GroceryCategory.household,
        createdAt: clock(),
        updatedAt: clock(),
      ),
    ];
    _reminders = [
      Reminder(
        id: 'demo-reminder-trash',
        title: 'Take out the trash',
        due: DateTime(today.year, today.month, today.day, 18),
        createdBy: 'alex',
      ),
      Reminder(
        id: 'demo-reminder-grocery',
        title: 'Grocery run',
        due: DateTime(today.year, today.month, today.day + 2, 10),
        createdBy: 'alex',
      ),
    ];
  });
}
