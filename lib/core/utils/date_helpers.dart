/// Date-only helpers. All dates in the app are "calendar dates" (no time part).

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime todayDate() => dateOnly(DateTime.now());

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Adds [months] to [anchor] but keeps the anchor's day-of-month where possible.
/// A tenant who moved in on the 31st is due on the 28th/29th in February,
/// then back on the 31st in March (always computed from the anchor, never chained).
DateTime addMonthsAnchored(DateTime anchor, int months) {
  final total = anchor.year * 12 + (anchor.month - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, anchor.day > lastDay ? lastDay : anchor.day);
}

int monthsBetween(DateTime a, DateTime b) =>
    (b.year - a.year) * 12 + (b.month - a.month);

/// The most recent due date on or before [today] for a tenant who moved in on [moveIn].
DateTime latestDueOnOrBefore(DateTime moveIn, DateTime today) {
  if (today.isBefore(moveIn)) return moveIn;
  var n = monthsBetween(moveIn, today);
  var due = addMonthsAnchored(moveIn, n);
  if (due.isAfter(today)) {
    n -= 1;
    due = addMonthsAnchored(moveIn, n);
  }
  return due;
}

/// yyyy-MM-dd, used for storage in SQLite (sorts correctly as text).
String toDb(DateTime d) {
  final x = dateOnly(d);
  return '${x.year.toString().padLeft(4, '0')}-'
      '${x.month.toString().padLeft(2, '0')}-'
      '${x.day.toString().padLeft(2, '0')}';
}

DateTime fromDb(String s) {
  final parts = s.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

DateTime? fromDbN(String? s) => (s == null || s.isEmpty) ? null : fromDb(s);
