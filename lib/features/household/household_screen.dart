import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';

class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({super.key, required this.store});
  final HouseholdStore store;
  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  final _name = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Household')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            store.householdName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Local demo · saved in this browser/device. Open app instances refresh from the same local store. Roommate selection is for demonstration, not a secure login; cross-device sharing needs a connected household account.',
          ),
          const SizedBox(height: 24),
          if (store.activeMembers.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(store.currentMemberId),
              initialValue: store.currentMemberId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Acting as roommate',
                border: OutlineInputBorder(),
              ),
              items: store.activeMembers
                  .map(
                    (m) => DropdownMenuItem(value: m.id, child: Text(m.name)),
                  )
                  .toList(),
              onChanged: store.busy ? null : (id) => store.selectMember(id!),
            ),
          const SizedBox(height: 24),
          Text('Roommates', style: Theme.of(context).textTheme.titleLarge),
          if (store.activeMembers.isEmpty)
            const Text('Add your first roommate to create chores.'),
          for (final member in store.activeMembers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(member.name),
              trailing: IconButton(
                tooltip: 'Remove ${member.name}',
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: store.busy
                    ? null
                    : () async {
                        if (await _confirm(
                          'Remove ${member.name}?',
                          'Their rotating chores move to the next eligible roommate. Fixed chores become unassigned until you edit them. Completion history is preserved.',
                        )) {
                          await store.removeMember(member.id);
                        }
                      },
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'New roommate name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: store.busy ? null : (_) => _add(),
          ),
          FilledButton.icon(
            onPressed: store.busy ? null : _add,
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Add roommate'),
          ),
          const SizedBox(height: 32),
          Text(
            'Try Maple House',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Three roommates, five chores, and a starter grocery and household-supply list. Demo dates are relative to today.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: store.busy
                ? null
                : () async {
                    if (await _confirm(
                      'Load demo household?',
                      'This replaces the locally saved roommates, chores, groceries, purchases, and contribution history on this device.',
                    )) {
                      await store.loadDemo();
                    }
                  },
            icon: const Icon(Icons.science_outlined),
            label: const Text('Load demo household'),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    if (await widget.store.addMember(_name.text)) _name.clear();
  }
}
