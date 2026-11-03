/// Human label for when a chore is due, relative to [now].
///
/// Compares calendar dates only, so 11:59 pm and 12:01 am on the same day are
/// both "Due today".
String relativeDue(DateTime due, DateTime now) {
  // Build UTC midnights: UTC has no daylight-saving shifts, so the difference
  // is always a whole number of days (local midnights can be 23 or 25 hours
  // apart).
  final dueDay = DateTime.utc(due.year, due.month, due.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = dueDay.difference(today).inDays;

  if (days < 0) {
    final late = -days;
    return late == 1 ? 'Overdue by 1 day' : 'Overdue by $late days';
  }
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due in $days days';
}
