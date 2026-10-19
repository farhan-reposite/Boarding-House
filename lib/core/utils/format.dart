import 'package:intl/intl.dart';

import 'date_helpers.dart';
import '../i18n/app_language.dart';

final NumberFormat _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final Map<String, DateFormat> _dateFormats = {};

/// 1500000 -> "Rp 1.500.000"
String rp(int value) => _rupiah.format(value);

/// App UI date in the current language, e.g. "12 Sep 2026" / "12 Okt 2026".
String fmtDate(DateTime? d) {
  if (d == null) return '-';
  final locale = AppLang.current.dateLocale;
  final format =
      _dateFormats.putIfAbsent(locale, () => DateFormat('d MMM yyyy', locale));
  return format.format(d);
}

/// Tenant-facing date (invoices, WhatsApp), e.g. "12 September 2026".
String fmtDateId(DateTime? d) =>
    d == null ? '-' : DateFormat('d MMMM yyyy', 'id_ID').format(d);

bool isOverdue(DateTime due) => due.isBefore(todayDate());

String dueLabel(DateTime due) => isOverdue(due)
    ? tr('Overdue since {date}', {'date': fmtDate(due)})
    : tr('Due {date}', {'date': fmtDate(due)});

/// Digits only -> int, null when empty.
int? parseMoney(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

/// Indonesian phone number -> international digits for wa.me links.
/// 0812... -> 62812..., 812... -> 62812..., 62812... stays.
String normalizePhone(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('0')) {
    d = '62${d.substring(1)}';
  } else if (d.startsWith('8')) {
    d = '62$d';
  }
  return d;
}

/// Sorts "A2" before "A10".
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+|\D+)');
  final pa = re.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i];
    final y = pb[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}
