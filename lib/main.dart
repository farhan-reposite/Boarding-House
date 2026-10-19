import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/db/database.dart';
import 'core/i18n/app_language.dart';
import 'core/theme.dart';
import 'core/tutorial/tutorial.dart';
import 'core/tutorial/tutorial_target.dart';
import 'core/utils/photo_store.dart';
import 'data/repository.dart';
import 'features/home_shell.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await initializeDateFormatting('id_ID');
  await initializeDateFormatting('en_US');
  await PhotoStore.init();

  // Load the saved appearance and language before the first frame so the app
  // never flashes the wrong theme or language on launch.
  final repo = KostRepository(AppDatabase.instance);
  final savedThemeMode = themeModeFromSetting(await repo.getThemeModeSetting());
  final savedLanguage = AppLanguage.fromCode(await repo.getLanguageSetting());
  AppLang.current = savedLanguage;

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith((ref) => savedThemeMode),
        languageProvider.overrideWith((ref) => savedLanguage),
      ],
      child: const KostApp(),
    ),
  );
}

class KostApp extends ConsumerWidget {
  const KostApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(languageProvider);
    return MaterialApp(
      title: 'Kost Manager',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      // Date pickers, dialogs' built-in buttons etc. follow the app language.
      locale: language.locale,
      supportedLocales: [
        for (final l in AppLanguage.values) l.locale,
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // The tutorial spotlight sits above every screen.
      builder: (context, child) => Stack(
        children: [
          Positioned.fill(child: child ?? const SizedBox.shrink()),
          const Positioned.fill(child: TutorialLayer()),
        ],
      ),
      home: const HomeShell(),
    );
  }
}
