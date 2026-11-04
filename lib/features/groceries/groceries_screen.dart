import 'package:flutter/material.dart';

/// Placeholder until card 3.1 lands.
class GroceriesScreen extends StatelessWidget {
  const GroceriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groceries')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Grocery sharing is planned for a future release.\nThis demo focuses on household chores.',
          ),
        ),
      ),
    );
  }
}
