import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';

class ChoreEditor extends StatefulWidget {
  const ChoreEditor({super.key, required this.store, this.chore});
  final HouseholdStore store;
  final Chore? chore;
  @override
  State<ChoreEditor> createState() => _ChoreEditorState();
}

class _ChoreEditorState extends State<ChoreEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late DateTime _due;
  late String? _assignee;
  late Set<String> _eligible;
  late Repeat _repeat;
  late bool _fixed;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final c = widget.chore;
    _title = TextEditingController(text: c?.title ?? '');
    _due = c?.due ?? day(widget.store.clock());
    _assignee = c?.assignee ?? widget.store.currentMemberId;
    _eligible =
        (c?.eligible ?? widget.store.activeMembers.map((m) => m.id).toList())
            .toSet();
    _repeat = c?.repeat ?? Repeat.once;
    _fixed = c?.fixed ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.store.saveChore(
      Chore(
        id: widget.chore?.id ?? '',
        title: _title.text,
        due: _due,
        assignee: _assignee,
        eligible: _eligible.toList(),
        repeat: _repeat,
        fixed: _fixed,
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = widget.store.error ?? 'Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.chore == null ? 'New chore' : 'Edit chore'),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save chore'),
        ),
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: _title,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Chore name',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a chore name' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _assignee,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Assigned roommate'),
            items: widget.store.activeMembers
                .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                .toList(),
            onChanged: _saving
                ? null
                : (v) => setState(() {
                    _assignee = v;
                    if (v != null) _eligible.add(v);
                  }),
            validator: (v) => v == null ? 'Choose a roommate' : null,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text('Due date: ${dateLabel(_due)}'),
            onPressed: _saving
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _due,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2200),
                    );
                    if (picked != null && mounted) {
                      setState(() => _due = picked);
                    }
                  },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Repeat>(
            initialValue: _repeat,
            decoration: const InputDecoration(labelText: 'Repeat schedule'),
            items: Repeat.values
                .map(
                  (r) => DropdownMenuItem(
                    value: r,
                    child: Text(
                      r == Repeat.once
                          ? 'Does not repeat'
                          : r.name[0].toUpperCase() + r.name.substring(1),
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving ? null : (v) => setState(() => _repeat = v!),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Agreed fixed assignment'),
            subtitle: const Text(
              'Keep this roommate on every repeat. Confirm agreement with your household.',
            ),
            value: _fixed,
            onChanged: _saving ? null : (v) => setState(() => _fixed = v),
          ),
          if (!_fixed) ...[
            const Text(
              'Eligible roommates',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Rotation follows the order below after each completion.',
            ),
            for (final member in widget.store.activeMembers)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(member.name),
                value: _eligible.contains(member.id),
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                        if (v!) {
                          _eligible.add(member.id);
                        } else {
                          _eligible.remove(member.id);
                        }
                      }),
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
