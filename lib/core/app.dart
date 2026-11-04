import 'dart:async';

import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';
import 'package:household_app/core/theme.dart';
import 'package:household_app/features/chores/chores_screen.dart';
import 'package:household_app/features/fairness/fairness_screen.dart';
import 'package:household_app/features/groceries/groceries_screen.dart';
import 'package:household_app/features/household/household_screen.dart';

/// App root: MaterialApp plus the four-tab bottom-nav shell.
class HouseholdApp extends StatelessWidget {
  const HouseholdApp({super.key, this.store});
  final HouseholdStore? store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Improvement Household',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: AppShell(store: store),
    );
  }
}

/// Holds the selected tab; each tab screen owns its own Scaffold and AppBar.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.store});
  final HouseholdStore? store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  late final HouseholdStore store;
  Timer? _clockRefresh;
  @override
  void initState() {
    super.initState();
    store = widget.store ?? HouseholdStore(LocalHouseholdStorage());
    store.load();
    WidgetsBinding.instance.addObserver(this);
    _clockRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading household',
              ),
            ),
          );
        }
        if (store.error != null && store.error!.startsWith('Could not read')) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(store.error!),
                    FilledButton(
                      onPressed: store.load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Scaffold(
          // IndexedStack keeps every tab mounted so each keeps its state
          // (scroll position, form input) when you switch away and back.
          body: Column(
            children: [
              if (store.busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Saving household',
                ),
              if (store.error != null)
                MaterialBanner(
                  content: Text(store.error!),
                  actions: [
                    TextButton(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Try your action again. Your previous data is saved.',
                              ),
                            ),
                          ),
                      child: const Text('Help'),
                    ),
                  ],
                ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    ChoresScreen(store: store),
                    const GroceriesScreen(),
                    FairnessScreen(store: store),
                    HouseholdScreen(store: store),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.checklist_outlined),
                selectedIcon: Icon(Icons.checklist),
                label: 'Chores',
              ),
              NavigationDestination(
                icon: Icon(Icons.shopping_cart_outlined),
                selectedIcon: Icon(Icons.shopping_cart),
                label: 'Groceries',
              ),
              NavigationDestination(
                icon: Icon(Icons.balance_outlined),
                selectedIcon: Icon(Icons.balance),
                label: 'Fairness',
              ),
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Household',
              ),
            ],
          ),
        );
      },
    );
  }
}
