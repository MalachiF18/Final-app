import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef Json = Map<String, dynamic>;
DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);
String dateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

enum Repeat { once, daily, weekly, monthly }

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
  String? currentMemberId;
  String householdName = 'My household';
  bool loading = true, busy = false;
  String? error;
  int _serial = 0;
  List<Member> get members => List.unmodifiable(_members);
  List<Member> get activeMembers => _members.where((m) => m.active).toList();
  List<Chore> get chores => List.unmodifiable(_chores);
  List<Completion> get history => List.unmodifiable(_history.reversed);
  String memberName(String? id) =>
      _members.where((m) => m.id == id).firstOrNull?.name ?? 'Unassigned';
  String _id() => '${clock().microsecondsSinceEpoch}-${_serial++}';
  Json _json() => {
    'version': 1,
    'name': householdName,
    'currentMemberId': currentMemberId,
    'members': _members.map((m) => m.toJson()).toList(),
    'chores': _chores.map((c) => c.toJson()).toList(),
    'history': _history.map((h) => h.toJson()).toList(),
  };
  void _restore(Json j) {
    if (j['version'] != 1) {
      throw const FormatException('Unsupported saved data');
    }
    householdName = j['name'];
    currentMemberId = j['currentMemberId'];
    _members = (j['members'] as List).map((m) => Member.fromJson(m)).toList();
    _chores = (j['chores'] as List).map((c) => Chore.fromJson(c)).toList();
    _history = (j['history'] as List)
        .map((h) => Completion.fromJson(h))
        .toList();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final saved = await storage.read();
      if (saved != null) _restore(jsonDecode(saved));
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
      await storage.write(jsonEncode(_json()));
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
  });
}
