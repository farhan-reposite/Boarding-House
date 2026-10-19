import 'package:flutter/material.dart';

/// Brand palette (sage / forest / tan / gold).
const kSage = Color(0xFF6D9773);
const kForest = Color(0xFF0C3B2E);
const kTan = Color(0xFFBB8A52);
const kGold = Color(0xFFFFBA00);

/// Seed for the generated tonal palette; the key colors are overridden below.
const kBrandSeed = kSage;

const _cardRadius = 16.0;
const _fieldRadius = 12.0;
const _fontFamily = 'PlusJakartaSans';

ThemeData buildLightTheme() => _buildTheme(Brightness.light);
ThemeData buildDarkTheme() => _buildTheme(Brightness.dark);

ColorScheme _scheme(Brightness b) {
  final base = ColorScheme.fromSeed(seedColor: kBrandSeed, brightness: b);
  if (b == Brightness.light) {
    return base.copyWith(
      primary: const Color(0xFF45785A),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDDEADF),
      onPrimaryContainer: kForest,
      secondary: const Color(0xFF9A6F3A),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFF3E6D2),
      onSecondaryContainer: const Color(0xFF4A3115),
      tertiary: kGold,
      onTertiary: kForest,
      tertiaryContainer: const Color(0xFFFFEDB8),
      onTertiaryContainer: const Color(0xFF3D2C00),
      surface: const Color(0xFFF2F5F0),
      onSurface: const Color(0xFF10241C),
      onSurfaceVariant: const Color(0xFF55665D),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: const Color(0xFFEAEFE8),
      surfaceContainerHighest: const Color(0xFFE5EBE3),
      outline: const Color(0xFF8A9A91),
      outlineVariant: const Color(0xFFD7DFD8),
    );
  }
  return base.copyWith(
    primary: const Color(0xFF8DBB98),
    onPrimary: kForest,
    primaryContainer: const Color(0xFF1F5240),
    onPrimaryContainer: const Color(0xFFD6EBDA),
    secondary: const Color(0xFFD9B27C),
    onSecondary: const Color(0xFF3A2610),
    secondaryContainer: const Color(0xFF4A3820),
    onSecondaryContainer: const Color(0xFFF3E6D2),
    tertiary: kGold,
    onTertiary: kForest,
    tertiaryContainer: const Color(0xFF4A3A00),
    onTertiaryContainer: const Color(0xFFFFEDB8),
    surface: const Color(0xFF08261D),
    onSurface: const Color(0xFFE6EFE9),
    onSurfaceVariant: const Color(0xFFA9BDB2),
    surfaceContainerLowest: const Color(0xFF061E17),
    surfaceContainerLow: const Color(0xFF0E3328),
    surfaceContainer: const Color(0xFF123B2F),
    surfaceContainerHigh: const Color(0xFF184436),
    surfaceContainerHighest: const Color(0xFF1B4A3B),
    outline: const Color(0xFF6F8A7C),
    outlineVariant: const Color(0xFF2A5646),
  );
}

ThemeData _buildTheme(Brightness brightness) {
  final scheme = _scheme(brightness);
  final isDark = brightness == Brightness.dark;
  final stadium = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

  return ThemeData(
    useMaterial3: true,
    fontFamily: _fontFamily,
    colorScheme: scheme,
    // One family at real weights (Plus Jakarta Sans 400-800). Section titles
    // use the same family, just bolder, instead of a second font.
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: TextStyle(fontWeight: FontWeight.w700),
      titleSmall: TextStyle(fontWeight: FontWeight.w600),
    ),
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,

    // ---------------------------------------------------------- app bar
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),

    // --------------------------------------------------------------- nav
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: stadium,
      height: 72,
      elevation: 3,
      shadowColor: Colors.black,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: stadium,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    ),

    // -------------------------------------------------------------- card
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.7 : 0.5)),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),

    // ------------------------------------------------------------- input
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: scheme.primary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: scheme.error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: scheme.error, width: 1.8),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide.none,
      ),
    ),

    // ------------------------------------------------------------ chips
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.primaryContainer,
      backgroundColor: scheme.surfaceContainerLow,
      labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      showCheckmark: false,
    ),

    // ---------------------------------------------------------- buttons
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: stadium,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: stadium,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: stadium,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: isDark ? scheme.primary : kForest,
      foregroundColor: isDark ? scheme.onPrimary : Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: stadium,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),

    // ------------------------------------------------------------- misc
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? scheme.surfaceContainerHighest : kForest,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme:
        ProgressIndicatorThemeData(color: scheme.primary),
  );
}
