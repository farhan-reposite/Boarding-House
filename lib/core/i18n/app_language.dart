import 'package:flutter/widgets.dart';

import 'id_strings.dart';

/// Languages the UI can be shown in. Indonesian is the default.
enum AppLanguage {
  id('id', 'Bahasa Indonesia', Locale('id', 'ID'), 'id_ID'),
  en('en', 'English', Locale('en', 'US'), 'en_US');

  const AppLanguage(this.code, this.nativeName, this.locale, this.dateLocale);

  /// Stored in the database (app_settings 'language').
  final String code;
  final String nativeName;
  final Locale locale;

  /// Locale tag used by intl's DateFormat.
  final String dateLocale;

  static AppLanguage fromCode(String? code) => AppLanguage.values
      .firstWhere((l) => l.code == code, orElse: () => AppLanguage.id);
}

/// Holds the language currently in use so [tr] can be called from anywhere
/// (widgets, models, the data layer) without a BuildContext.
abstract final class AppLang {
  static AppLanguage current = AppLanguage.id;
}

/// Translates a UI string.
///
/// The English text is the key. Indonesian translations live in
/// `id_strings.dart`; a missing translation falls back to the English text,
/// so a forgotten entry never breaks the screen.
///
/// Dynamic parts use `{name}` placeholders:
/// `tr('Remind all {n} overdue', {'n': 3})`.
String tr(String en, [Map<String, Object?>? args]) {
  var s = AppLang.current == AppLanguage.id ? (kIdStrings[en] ?? en) : en;
  if (args != null) {
    args.forEach((key, value) {
      s = s.replaceAll('{$key}', '$value');
    });
  }
  return s;
}
