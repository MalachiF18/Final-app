import 'package:flutter/material.dart';
import 'package:household_app/data/household_store.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key, required this.store});
  final HouseholdStore store;

  void _edit(BuildContext context, [Reminder? reminder]) {
    showDialog<void>(
      context: context,
      builder: (_) => ReminderEditorDialog(store: store, reminder: reminder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reminders = store.reminders.toList()
      ..sort((a, b) {
        if (a.completed != b.completed) return a.completed ? 1 : -1;
        return a.due.compareTo(b.due);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('REMINDERS')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-reminder',
        onPressed: store.busy ? null : () => _edit(context),
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Add reminder'),
      ),
      body: reminders.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No reminders yet. Add one for a chore, grocery run, or household event.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: reminders.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reminder = reminders[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  leading: Checkbox(
                    value: reminder.completed,
                    onChanged: store.busy
                        ? null
                        : (_) => store.toggleReminder(reminder.id),
                    semanticLabel: 'Complete ${reminder.title}',
                  ),
                  title: Text(
                    reminder.title,
                    style: TextStyle(
                      decoration: reminder.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    '${_dateTimeLabel(reminder.due)}\nAdded by ${store.memberName(reminder.createdBy)}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Actions for ${reminder.title}',
                    enabled: !store.busy,
                    onSelected: (action) async {
                      if (action == 'edit') {
                        _edit(context, reminder);
                      } else {
                        await store.deleteReminder(reminder.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit reminder'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete reminder'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class ReminderEditorDialog extends StatefulWidget {
  const ReminderEditorDialog({super.key, required this.store, this.reminder});
  final HouseholdStore store;
  final Reminder? reminder;

  @override
  State<ReminderEditorDialog> createState() => _ReminderEditorDialogState();
}

class _ReminderEditorDialogState extends State<ReminderEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late DateTime _due;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.reminder?.title ?? '');
    _due =
        widget.reminder?.due ??
        widget.store.clock().add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.reminder == null ? 'Add reminder' : 'Edit reminder'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _title,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Reminder',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a reminder.'
                  : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(dateLabel(_due)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule_outlined),
              label: Text(TimeOfDay.fromDateTime(_due).format(context)),
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
                final ok = await widget.store.saveReminder(
                  id: widget.reminder?.id,
                  title: _title.text,
                  due: _due,
                );
                if (!context.mounted) return;
                if (ok) {
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        widget.store.error ?? 'Could not save reminder.',
                      ),
                    ),
                  );
                }
              },
        child: Text(widget.reminder == null ? 'Add' : 'Save'),
      ),
    ],
  );

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(widget.store.clock().year - 1),
      lastDate: DateTime(widget.store.clock().year + 5),
    );
    if (value == null) return;
    setState(() {
      _due = DateTime(
        value.year,
        value.month,
        value.day,
        _due.hour,
        _due.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due),
    );
    if (value == null) return;
    setState(() {
      _due = DateTime(
        _due.year,
        _due.month,
        _due.day,
        value.hour,
        value.minute,
      );
    });
  }
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
