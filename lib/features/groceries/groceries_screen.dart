import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';

class GroceriesScreen extends StatefulWidget {
  const GroceriesScreen({super.key, required this.store});
  final HouseholdStore store;

  @override
  State<GroceriesScreen> createState() => _GroceriesScreenState();
}

class _GroceriesScreenState extends State<GroceriesScreen> {
  GroceryCategory? _category;

  void _edit([GroceryItem? item]) {
    showDialog<void>(
      context: context,
      builder: (_) => GroceryEditorDialog(store: widget.store, item: item),
    );
  }

  void _message(bool ok, String success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? success : widget.store.error ?? 'Try again.'),
      ),
    );
  }

  Future<void> _remove(GroceryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${item.name}?'),
        content: Text(
          item.purchased
              ? 'The item leaves the list, but its purchase stays in contribution history.'
              : 'This removes the item from the shared list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await widget.store.deleteGrocery(item.id);
      _message(ok, '${item.name} removed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final filtered = store.groceries
        .where((item) => _category == null || item.category == _category)
        .toList();
    final needed = filtered.where((item) => !item.purchased).toList()
      ..sort((a, b) {
        final category = a.category.index.compareTo(b.category.index);
        return category == 0 ? a.name.compareTo(b.name) : category;
      });
    final purchased = filtered.where((item) => item.purchased).toList()
      ..sort((a, b) => b.purchasedAt!.compareTo(a.purchasedAt!));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping list'),
        actions: [
          IconButton(
            tooltip: 'Refresh shared list',
            onPressed: store.busy
                ? null
                : () async {
                    final ok = await store.sync();
                    _message(ok, 'Shared list refreshed.');
                  },
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: store.activeMembers.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add-grocery',
              onPressed: store.busy ? null : _edit,
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text(
            store.householdName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            store.currentMemberId == null
                ? 'Add a roommate before using the shared list.'
                : 'Shopping as ${store.memberName(store.currentMemberId)} · ${needed.length} needed',
          ),
          const SizedBox(height: 4),
          const Text(
            'Changes refresh between app instances using this browser/device. Cross-device sharing requires a connected household account.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<GroceryCategory?>(
            key: ValueKey(_category),
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Category filter',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('All categories'),
              ),
              for (final category in GroceryCategory.values)
                DropdownMenuItem(value: category, child: Text(category.label)),
            ],
            onChanged: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: 20),
          Text('Needed', style: Theme.of(context).textTheme.titleLarge),
          if (store.activeMembers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Open Household and add roommates to start a shared list.',
              ),
            )
          else if (needed.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nothing needed in this category. Add an item when supplies run low.',
              ),
            ),
          for (final item in needed) _neededCard(context, item),
          const SizedBox(height: 24),
          Text('Purchased', style: Theme.of(context).textTheme.titleLarge),
          if (purchased.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Purchased items will appear here with the buyer recorded.',
              ),
            ),
          for (final item in purchased) _purchasedCard(context, item),
        ],
      ),
    );
  }

  Widget _neededCard(BuildContext context, GroceryItem item) {
    final store = widget.store;
    final mine = item.claimedBy == store.currentMemberId;
    final available = item.claimedBy == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Actions for ${item.name}',
                  enabled: !store.busy,
                  onSelected: (action) =>
                      action == 'edit' ? _edit(item) : _remove(item),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit item')),
                    PopupMenuItem(value: 'remove', child: Text('Remove item')),
                  ],
                ),
              ],
            ),
            Text('Quantity ${item.quantity} · ${item.category.label}'),
            const SizedBox(height: 6),
            Text(
              available
                  ? 'Unclaimed'
                  : mine
                  ? 'Claimed by you'
                  : 'Claimed by ${store.memberName(item.claimedBy)}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: store.busy || (!available && !mine)
                      ? null
                      : () async {
                          final ok = mine
                              ? await store.unclaimGrocery(item.id)
                              : await store.claimGrocery(item.id);
                          _message(
                            ok,
                            mine
                                ? '${item.name} released.'
                                : '${item.name} claimed.',
                          );
                        },
                  icon: Icon(
                    mine
                        ? Icons.person_remove_outlined
                        : Icons.person_add_outlined,
                  ),
                  label: Text(mine ? 'Release' : 'Claim'),
                ),
                FilledButton.icon(
                  onPressed: store.busy || (!available && !mine)
                      ? null
                      : () async {
                          final ok = await store.markGroceryPurchased(item.id);
                          _message(ok, '${item.name} marked purchased.');
                        },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Mark purchased'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _purchasedCard(BuildContext context, GroceryItem item) {
    final purchase = widget.store.purchases
        .where((p) => p.id == item.purchaseId)
        .firstOrNull;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: Text(item.name),
        subtitle: Text(
          'Quantity ${item.quantity} · ${item.category.label}\n'
          'Bought by ${widget.store.memberName(item.purchasedBy)} on ${dateLabel(item.purchasedAt!)}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          tooltip: 'Actions for purchased ${item.name}',
          enabled: !widget.store.busy,
          onSelected: (action) async {
            if (action == 'undo' && purchase != null) {
              final ok = await widget.store.undoPurchase(purchase);
              _message(ok, '${item.name} returned to the needed list.');
            } else if (action == 'remove') {
              await _remove(item);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'undo',
              enabled:
                  purchase != null && widget.store.canUndoPurchase(purchase),
              child: const Text('Undo purchase'),
            ),
            const PopupMenuItem(value: 'remove', child: Text('Remove item')),
          ],
        ),
      ),
    );
  }
}

class GroceryEditorDialog extends StatefulWidget {
  const GroceryEditorDialog({super.key, required this.store, this.item});
  final HouseholdStore store;
  final GroceryItem? item;

  @override
  State<GroceryEditorDialog> createState() => _GroceryEditorDialogState();
}

class _GroceryEditorDialogState extends State<GroceryEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late GroceryCategory _category;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name ?? '');
    _quantity = TextEditingController(text: '${widget.item?.quantity ?? 1}');
    _category = widget.item?.category ?? GroceryCategory.pantry;
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.item == null ? 'Add shopping item' : 'Edit shopping item',
    ),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Item name',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an item name.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final number = int.tryParse(value ?? '');
                return number == null || number < 1 || number > 99
                    ? 'Enter a number from 1 to 99.'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<GroceryCategory>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final category in GroceryCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(category.label),
                  ),
              ],
              onChanged: (value) => setState(() => _category = value!),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: widget.store.busy
            ? null
            : () async {
                if (!_form.currentState!.validate()) return;
                final ok = await widget.store.saveGrocery(
                  id: widget.item?.id,
                  name: _name.text,
                  quantity: int.parse(_quantity.text),
                  category: _category,
                );
                if (!context.mounted) return;
                if (ok) {
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        widget.store.error ?? 'Could not save item.',
                      ),
                    ),
                  );
                }
              },
        child: Text(widget.item == null ? 'Add item' : 'Save changes'),
      ),
    ],
  );
}
