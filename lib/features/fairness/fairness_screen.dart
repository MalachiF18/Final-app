import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';

class FairnessScreen extends StatelessWidget {
  const FairnessScreen({super.key, required this.store});
  final HouseholdStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fairness')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Every completed chore counts',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'All-time completion counts, including former roommates. Counts do not measure chore difficulty or time spent.',
        ),
        const SizedBox(height: 16),
        if (store.history.isEmpty)
          const Text(
            'No completions yet. Finish a chore to see contributions.',
          ),
        for (final member in store.members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(
              '${member.name}${member.active ? '' : ' (former roommate)'}',
            ),
            subtitle: Text(
              '${store.chores.where((c) => !c.completed && c.assignee == member.id).length} open chores',
            ),
            trailing: Text(
              '${store.history.where((h) => h.memberId == member.id).length} completed',
            ),
          ),
      ],
    ),
  );
}
