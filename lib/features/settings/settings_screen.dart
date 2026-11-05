import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';
import 'package:household_app/features/household/household_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final HouseholdStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SETTINGS')),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: const Icon(Icons.groups_outlined),
          title: Text('Members (${store.activeMembers.length})'),
          subtitle: Text(
            'Acting as ${store.memberName(store.currentMemberId)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ListenableBuilder(
                listenable: store,
                builder: (_, _) => HouseholdScreen(store: store),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Household info'),
          subtitle: Text(store.householdName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _renameHousehold(context),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Chore rotation'),
          subtitle: const Text('Review automatic and fixed assignment rules'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Chore rotation'),
              content: const Text(
                'Rotating chores move to the next eligible active roommate after completion. Fixed assignments stay with the selected roommate. You can change either rule while editing a chore.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_none),
          title: const Text('Notifications'),
          subtitle: const Text('Show reminder status inside the app'),
          value: store.remindersEnabled,
          onChanged: store.busy ? null : store.setRemindersEnabled,
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Local prototype · household data is stored in this browser/device. Secure accounts, remote invitations, push notifications, and cross-device sync require a connected backend.',
          ),
        ),
      ],
    ),
  );

  Future<void> _renameHousehold(BuildContext context) async {
    final controller = TextEditingController(text: store.householdName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Household info'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Household name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final ok = await store.renameHousehold(name);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.error ?? 'Could not rename household.')),
      );
    }
  }
}
