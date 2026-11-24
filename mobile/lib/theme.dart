import 'package:material_ui/material_ui.dart';

/// Warna Propestindo, sama dengan web & landing page (hijau, emas, merah dari logo).
class AppColors {
  static const green950 = Color(0xFF062616);
  static const green900 = Color(0xFF0B3B24);
  static const green800 = Color(0xFF0F4D2F);
  static const green700 = Color(0xFF14632F);
  static const green600 = Color(0xFF15803D);
  static const green50 = Color(0xFFEFFAF2);
  static const gold = Color(0xFFE2B22B);
  static const gold600 = Color(0xFFB8861A);
  static const gold50 = Color(0xFFFDF6E1);
  static const red = Color(0xFFC81E1E);
  static const red50 = Color(0xFFFDECEC);
  static const amber = Color(0xFFB45309);
  static const amber50 = Color(0xFFFEF4E2);
  static const blue = Color(0xFF1D4F91);
  static const blue50 = Color(0xFFE8F0FB);
  static const ink = Color(0xFF0F1D16);
  static const ink2 = Color(0xFF44544B);
  static const muted = Color(0xFF6B7A71);
  static const line = Color(0xFFE3E9E5);
  static const line2 = Color(0xFFEEF2EF);
  static const bg = Color(0xFFF4F7F5);
}

/// Gradien header (sama dengan hero landing page).
const heroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.green900, AppColors.green950],
);

ThemeData buildTheme() {
  const font = 'PlusJakartaSans';
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.green700,
    primary: AppColors.green700,
    secondary: AppColors.gold,
    onSecondary: AppColors.green950,
    error: AppColors.red,
    surface: Colors.white,
  );
  final base = ThemeData(colorScheme: scheme, fontFamily: font, useMaterial3: true);
  final radius = BorderRadius.circular(12);
  OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c, width: w));
  const pill = StadiumBorder();
  const btnText = TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 15);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink).copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -.3),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.green950,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(AppColors.line),
      enabledBorder: border(AppColors.line),
      focusedBorder: border(AppColors.green600, 2),
      labelStyle: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.green700,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 50),
        shape: pill,
        textStyle: btnText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(48, 46),
        shape: pill,
        side: const BorderSide(color: AppColors.line, width: 1.5),
        textStyle: btnText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.green700, textStyle: btnText.copyWith(fontSize: 14)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.green700,
      foregroundColor: Colors.white,
      elevation: 3,
      highlightElevation: 5,
      shape: StadiumBorder(),
      extendedTextStyle: btnText,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: AppColors.line, width: 1.5),
      backgroundColor: Colors.white,
      selectedColor: AppColors.green50,
      labelStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink2),
      showCheckmark: false,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: AppColors.ink2,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      tabAlignment: TabAlignment.start,
      labelStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 13.5),
      unselectedLabelStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 13.5),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.green950,
      contentTextStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w600, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.green600 : null),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line2, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.green600),
  );
}
