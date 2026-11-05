import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';

class FairnessScreen extends StatefulWidget {
  const FairnessScreen({super.key, required this.store});
  final HouseholdStore store;

  @override
  State<FairnessScreen> createState() => _FairnessScreenState();
}

class _FairnessScreenState extends State<FairnessScreen> {
  ContributionWindow _window = ContributionWindow.week;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final contributions = store.contributionsFor(_window);
    final now = day(store.clock());
    final start = _window == ContributionWindow.week
        ? now.subtract(Duration(days: now.weekday - DateTime.monday))
        : DateTime(now.year, now.month);
    final end = _window == ContributionWindow.week
        ? start.add(const Duration(days: 6))
        : DateTime(start.year, start.month + 1, 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Fairness')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Contribution dashboard',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'A contribution is recorded only after a chore is completed or a shopping item is purchased.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('This week'),
                selected: _window == ContributionWindow.week,
                onSelected: (_) =>
                    setState(() => _window = ContributionWindow.week),
              ),
              ChoiceChip(
                label: const Text('This month'),
                selected: _window == ContributionWindow.month,
                onSelected: (_) =>
                    setState(() => _window = ContributionWindow.month),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${dateLabel(start)} through ${dateLabel(end)}'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team rules',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• One completed chore = 1 contribution point.\n'
                    '• One purchased list item = 1 contribution point.\n'
                    '• Quantity, category, time, and cost do not change points.\n'
                    '• Undoing a completion or purchase removes its point.\n'
                    '• Former roommates keep their valid history.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Roommate totals',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (store.members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Add roommates to start tracking contributions.'),
            ),
          for (final member in store.members)
            _memberCard(context, member, contributions),
          const SizedBox(height: 24),
          Text(
            'Contribution history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Newest first. Undo is available only while the matching item has not changed.',
          ),
          if (contributions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No recorded contributions in this period.'),
            ),
          for (final contribution in contributions)
            _historyTile(context, contribution),
        ],
      ),
    );
  }

  Widget _memberCard(
    BuildContext context,
    Member member,
    List<Contribution> contributions,
  ) {
    final mine = contributions.where((c) => c.memberId == member.id).toList();
    final chores = mine.where((c) => c.kind == ContributionKind.chore).length;
    final groceries = mine
        .where((c) => c.kind == ContributionKind.grocery)
        .length;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(member.name.characters.first.toUpperCase()),
        ),
        title: Text(
          '${member.name}${member.active ? '' : ' (former roommate)'}',
        ),
        subtitle: Text('$chores chores · $groceries purchases'),
        trailing: Text(
          '${mine.length} pt${mine.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  Widget _historyTile(BuildContext context, Contribution contribution) {
    final store = widget.store;
    Completion? completion;
    Purchase? purchase;
    if (contribution.kind == ContributionKind.chore) {
      completion = store.history
          .where((h) => contribution.id == 'chore:${h.choreId}:${h.occurrence}')
          .firstOrNull;
    } else {
      purchase = store.purchases
          .where((p) => contribution.id == 'grocery:${p.id}')
          .firstOrNull;
    }
    final canUndo = completion != null
        ? store.canUndoCompletion(completion)
        : purchase != null && store.canUndoPurchase(purchase);
    return Card(
      child: ListTile(
        leading: Icon(
          contribution.kind == ContributionKind.chore
              ? Icons.task_alt
              : Icons.shopping_bag_outlined,
        ),
        title: Text(contribution.title),
        subtitle: Text(
          '${contribution.memberName} · ${contribution.kind == ContributionKind.chore ? 'Chore' : 'Purchase'} · ${dateLabel(contribution.at)}',
        ),
        trailing: canUndo
            ? IconButton(
                tooltip: 'Undo ${contribution.title}',
                icon: const Icon(Icons.undo),
                onPressed: store.busy
                    ? null
                    : () async {
                        final ok = completion != null
                            ? await store.undoCompletion(completion)
                            : await store.undoPurchase(purchase!);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? '${contribution.title} undone and totals recalculated.'
                                  : store.error ??
                                        'Could not undo this contribution.',
                            ),
                          ),
                        );
                      },
              )
            : null,
      ),
    );
  }
}
