import 'package:flutter/material.dart';
import 'package:household_app/core/theme.dart';
import 'package:household_app/features/chores/chores_screen.dart';
import 'package:household_app/features/fairness/fairness_screen.dart';
import 'package:household_app/features/groceries/groceries_screen.dart';
import 'package:household_app/features/household/household_screen.dart';

/// App root: MaterialApp plus the four-tab bottom-nav shell.
class HouseholdApp extends StatelessWidget {
  const HouseholdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Improvement Household',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}

/// Holds the selected tab; each tab screen owns its own Scaffold and AppBar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps every tab mounted so each keeps its state
      // (scroll position, form input) when you switch away and back.
      body: IndexedStack(
        index: _index,
        children: const [
          ChoresScreen(),
          GroceriesScreen(),
          FairnessScreen(),
          HouseholdScreen(),
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
  }
}
