import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';
import 'package:household_app/features/chores/chores_screen.dart';
import 'package:household_app/features/fairness/fairness_screen.dart';
import 'package:household_app/features/groceries/groceries_screen.dart';
import 'package:household_app/features/reminders/reminders_screen.dart';
import 'package:household_app/features/settings/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});
  final HouseholdStore store;

  void _open(BuildContext context, Widget Function() builder) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ListenableBuilder(listenable: store, builder: (_, _) => builder()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekly = store.contributionsFor(ContributionWindow.week);
    final completedChores = weekly
        .where((c) => c.kind == ContributionKind.chore)
        .length;
    final now = day(store.clock());
    final weekEnd = now.add(Duration(days: DateTime.sunday - now.weekday));
    final openThisWeek = store.chores
        .where((c) => !c.completed && !day(c.due).isAfter(day(weekEnd)))
        .length;
    final planned = math.max(1, completedChores + openThisWeek);
    final upcomingReminders =
        store.reminders.where((r) => !r.completed).toList()
          ..sort((a, b) => a.due.compareTo(b.due));

    return Scaffold(
      appBar: AppBar(
        title: const Text('HOME'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _open(context, () => SettingsScreen(store: store)),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.home_outlined, size: 44),
                    const SizedBox(height: 8),
                    Text(
                      store.householdName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Acting as ${store.memberName(store.currentMemberId)}',
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Home'),
                selected: true,
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  _open(context, () => SettingsScreen(store: store));
                },
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(store.householdName),
              subtitle: Text('${store.activeMembers.length} active roommates'),
              trailing: const Icon(Icons.expand_more),
              onTap: () => _open(context, () => SettingsScreen(store: store)),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => GridView.count(
              crossAxisCount: constraints.maxWidth >= 720 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: constraints.maxWidth >= 720 ? 0.9 : 0.65,
              children: [
                _HomeTile(
                  icon: Icons.check_box_outlined,
                  label: 'Chores',
                  detail:
                      '${store.chores.where((c) => !c.completed).length} open',
                  onTap: () => _open(context, () => ChoresScreen(store: store)),
                ),
                _HomeTile(
                  icon: Icons.shopping_cart_outlined,
                  label: 'Groceries',
                  detail:
                      '${store.groceries.where((g) => !g.purchased).length} needed',
                  onTap: () =>
                      _open(context, () => GroceriesScreen(store: store)),
                ),
                _HomeTile(
                  icon: Icons.notifications_none,
                  label: 'Reminders',
                  detail: '${upcomingReminders.length} upcoming',
                  onTap: () =>
                      _open(context, () => RemindersScreen(store: store)),
                ),
                _HomeTile(
                  icon: Icons.bar_chart_outlined,
                  label: 'Progress',
                  detail: '${weekly.length} points this week',
                  onTap: () =>
                      _open(context, () => FairnessScreen(store: store)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Text(
                        'This week',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('$completedChores / $planned chores'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (completedChores / planned).clamp(0, 1),
                    minHeight: 12,
                    borderRadius: BorderRadius.circular(8),
                    semanticsLabel:
                        'Weekly chore progress, $completedChores of $planned chores completed',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    weekly.isEmpty
                        ? 'Complete a chore or purchase an item to start your progress.'
                        : '${weekly.length} total contribution point${weekly.length == 1 ? '' : 's'} this week.',
                  ),
                ],
              ),
            ),
          ),
          if (upcomingReminders.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Next reminders',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      _open(context, () => RemindersScreen(store: store)),
                  child: const Text('View all'),
                ),
              ],
            ),
            for (final reminder in upcomingReminders.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_none),
                title: Text(reminder.title),
                subtitle: Text(_dateTimeLabel(reminder.due)),
              ),
          ],
        ],
      ),
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });
  final IconData icon;
  final String label, detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _dateTimeLabel(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '${dateLabel(value)} · $hour:$minute $period';
}
