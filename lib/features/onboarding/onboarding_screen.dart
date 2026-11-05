import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';

enum _OnboardingStage { welcome, profile, household }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.store});
  final HouseholdStore store;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _profileName = TextEditingController();
  _OnboardingStage _stage = _OnboardingStage.welcome;
  String _entryLabel = 'Create account';

  @override
  void dispose() {
    _profileName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _stage == _OnboardingStage.welcome
        ? null
        : AppBar(
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => setState(() {
                _stage = _stage == _OnboardingStage.household
                    ? _OnboardingStage.profile
                    : _OnboardingStage.welcome;
              }),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
    body: SafeArea(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (_stage) {
          _OnboardingStage.welcome => _welcome(context),
          _OnboardingStage.profile => _profile(context),
          _OnboardingStage.household => _household(context),
        },
      ),
    ),
  );

  Widget _welcome(BuildContext context) => Center(
    key: const ValueKey('welcome'),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.home_outlined,
              size: 96,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'Daily Improvement\nHousehold',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Share chores, shopping, reminders, and progress with your household.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _start('Sign in'),
                icon: const Icon(Icons.person_outline),
                label: const Text('Sign in'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _start('Create account'),
                child: const Text('Create account'),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Local prototype: profiles are stored on this device and are not secure online accounts.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _profile(BuildContext context) => Center(
    key: const ValueKey('profile'),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.person_add_alt_1_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              _entryLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose the name roommates will see.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _profileName,
              autofocus: true,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _continueProfile(),
            ),
            FilledButton(
              onPressed: _continueProfile,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _household(BuildContext context) => Center(
    key: const ValueKey('household'),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Join or create a household',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Welcome, ${_profileName.text.trim()}.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.store.busy ? null : _joinHousehold,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Join household'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.store.busy ? null : _createHousehold,
                icon: const Icon(Icons.add_home_outlined),
                label: const Text('Create household'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _start(String label) => setState(() {
    _entryLabel = label;
    _stage = _OnboardingStage.profile;
  });

  void _continueProfile() {
    final name = _profileName.text.trim();
    if (name.isEmpty || name.length > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name to continue.')),
      );
      return;
    }
    setState(() => _stage = _OnboardingStage.household);
  }

  Future<void> _createHousehold() async {
    final controller = TextEditingController(
      text: '${_profileName.text.trim()}’s household',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create household'),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final ok = await widget.store.createHousehold(_profileName.text, name);
    if (!ok && mounted) _showError();
  }

  Future<void> _joinHousehold() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join household'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter an invite code. Use MAPLE to open the local demo household.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Invite code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (code == null || !mounted) return;
    if (code.trim().toUpperCase() != 'MAPLE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite code not found in this local prototype.'),
        ),
      );
      return;
    }
    if (!await widget.store.loadDemo()) {
      if (mounted) _showError();
      return;
    }
    final profile = _profileName.text.trim();
    final match = widget.store.activeMembers
        .where((m) => m.name.toLowerCase() == profile.toLowerCase())
        .firstOrNull;
    if (match != null) {
      await widget.store.selectMember(match.id);
    } else if (await widget.store.addMember(profile)) {
      await widget.store.selectMember(widget.store.activeMembers.last.id);
    }
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.store.error ?? 'Could not save your household.'),
      ),
    );
  }
}
