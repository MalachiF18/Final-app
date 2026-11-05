import 'dart:async';

import 'package:flutter/material.dart';
import 'package:household_app/core/theme.dart';
import 'package:household_app/data/household_store.dart';
import 'package:household_app/features/home/home_screen.dart';
import 'package:household_app/features/onboarding/onboarding_screen.dart';

/// App root: MaterialApp plus the local household navigation shell.
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

/// Loads the shared store, then shows onboarding or the home dashboard.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.store});
  final HouseholdStore? store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final HouseholdStore store;
  Timer? _clockRefresh;
  Timer? _syncRefresh;
  @override
  void initState() {
    super.initState();
    store = widget.store ?? HouseholdStore(LocalHouseholdStorage());
    store.load();
    WidgetsBinding.instance.addObserver(this);
    _clockRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _syncRefresh = Timer.periodic(
      const Duration(seconds: 5),
      (_) => store.sync(),
    );
  }

  @override
  void dispose() {
    _clockRefresh?.cancel();
    _syncRefresh?.cancel();
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
        final screen = store.activeMembers.isEmpty
            ? OnboardingScreen(store: store)
            : HomeScreen(store: store);
        return Stack(
          children: [
            screen,
            if (store.busy)
              const SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(
                    semanticsLabel: 'Saving household',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
