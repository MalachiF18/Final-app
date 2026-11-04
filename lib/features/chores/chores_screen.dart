import 'package:flutter/material.dart';
import 'package:household_app/core/dates.dart';
import 'package:household_app/data/household_store.dart';

import 'chore_editor.dart';

class ChoresScreen extends StatefulWidget {
  const ChoresScreen({super.key, required this.store});
  final HouseholdStore store;
  @override
  State<ChoresScreen> createState() => _ChoresScreenState();
}

class _ChoresScreenState extends State<ChoresScreen> {
  bool _mine = false;
  String _filter = 'All';
  void _edit([Chore? chore]) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ChoreEditor(store: widget.store, chore: chore),
    ),
  );
  Future<void> _complete(Chore c, int occurrence) async {
    final ok = await widget.store.complete(c.id, occurrence);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${c.title} completed. History saved.'
              : widget.store.error ?? 'Another save is in progress.',
        ),
      ),
    );
  }

  Future<void> _delete(Chore c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${c.title}?'),
        content: const Text(
          'Future occurrences will be removed. Completion history stays saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.store.deleteChore(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final now = day(store.clock());
    final active =
        store.chores
            .where(
              (c) =>
                  !c.completed &&
                  (!_mine || c.assignee == store.currentMemberId),
            )
            .toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    final visible = active
        .where(
          (c) => switch (_filter) {
            'Overdue' => c.due.isBefore(now),
            'Upcoming' => c.due.isAfter(now),
            'Today' => c.due == now,
            _ => true,
          },
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_mine ? 'My Responsibilities' : 'Chores'),
        actions: [
          IconButton(
            tooltip: 'Completion history',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => HistoryScreen(store: store),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: store.activeMembers.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: store.busy ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add chore'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text(
            store.householdName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '${active.length} open · ${active.where((c) => c.due.isBefore(now)).length} overdue',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Household chores'),
                selected: !_mine,
                onSelected: (_) => setState(() => _mine = false),
              ),
              ChoiceChip(
                label: const Text('My Responsibilities'),
                selected: _mine,
                onSelected: (_) => setState(() => _mine = true),
              ),
            ],
          ),
          if (_mine)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Viewing ${store.memberName(store.currentMemberId)}. Switch roommates in Household.',
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final f in ['All', 'Overdue', 'Today', 'Upcoming'])
                FilterChip(
                  label: Text(f),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (store.activeMembers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Welcome home. Open Household to add roommates or load the demo household.',
              ),
            )
          else if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                active.isEmpty
                    ? 'All clear! Add a chore to plan the next responsibility.'
                    : 'No chores match this filter.',
              ),
            ),
          for (final c in visible) _card(context, c, now),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Chore c, DateTime now) {
    final occurrence = c.occurrence;
    final canComplete =
        c.assignee != null &&
        c.assignee == widget.store.currentMemberId &&
        !c.due.isAfter(now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    c.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Actions for ${c.title}',
                  enabled: !widget.store.busy,
                  onSelected: (value) =>
                      value == 'edit' ? _edit(c) : _delete(c),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit / reassign'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            Text(widget.store.memberName(c.assignee)),
            const SizedBox(height: 8),
            Text(
              '${relativeDue(c.due, now)} · ${dateLabel(c.due)}',
              style: TextStyle(
                color: c.due.isBefore(now)
                    ? Theme.of(context).colorScheme.error
                    : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${c.repeat.name} · ${c.fixed ? 'Fixed assignment' : 'Rotating assignment'}',
            ),
            if (c.assignee == null)
              const Text(
                'Needs reassignment: edit this chore to choose a roommate.',
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: canComplete && !widget.store.busy
                  ? () => _complete(c, occurrence)
                  : null,
              icon: const Icon(Icons.check),
              label: const Text('Mark complete'),
            ),
            if (!canComplete && c.assignee != null)
              Text(
                c.due.isAfter(now)
                    ? 'Available to complete on the due date.'
                    : 'Switch to ${widget.store.memberName(c.assignee)} in Household to complete.',
              ),
          ],
        ),
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.store});
  final HouseholdStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Completion history')),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) => store.history.isEmpty
          ? const Center(
              child: Text('No completions yet. Completed chores appear here.'),
            )
          : ListView(
              children: [
                for (final h in store.history)
                  ListTile(
                    leading: const Icon(Icons.task_alt),
                    title: Text(h.title),
                    subtitle: Text(
                      '${h.memberName} · completed ${dateLabel(h.at)}\nOriginally due ${dateLabel(h.due)}',
                    ),
                  ),
              ],
            ),
    ),
  );
}
