import 'package:flutter/material.dart';

import 'cycle.dart';

const monthsNom = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
];
const monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
];
const monthsShort = [
  'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
];
const weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const weekdaysFull = [
  'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота',
  'воскресенье'
];

String fmtDate(DateTime d, {bool year = false}) =>
    '${d.day} ${monthsGen[d.month - 1]}${year ? ' ${d.year}' : ''}';

String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

// неразрывный пробел: «5 дней» не разрывается между строк
String daysWord(int n) => '$n\u00A0${plural(n, 'день', 'дня', 'дней')}';

/// Шрифты: Unbounded — цифры и заголовки, Golos — текст.
const kDisplay = 'Unbounded';
const kText = 'Golos';

/// Палитра: гранат, румянец, лагуна, слива.
class Palette {
  static const period = Color(0xFFC2183F); // гранат
  static const predicted = Color(0xFFF29BAE); // румянец
  static const fertile = Color(0xFF6CC3BB); // лагуна
  static const ovulation = Color(0xFF17867F); // глубокая лагуна
  static const ink = Color(0xFF2B1520); // слива
  static const paper = Color(0xFFFFF6F7);
  static const night = Color(0xFF170C12);
  static const nightRaised = Color(0xFF231620);
  static const nightText = Color(0xFFF7E9EE);

  /// Заливка фертильных дней: в тёмной теме полупрозрачная бирюза
  /// на сливовом фоне становится серой, поэтому цвета заданы явно.
  static Color fertileFill(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF17423F) : const Color(0xFFD2EEEA);
  static Color fertileText(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFB4EAE4) : const Color(0xFF0F5B56);
}

Color? kindColor(DayKind k) => switch (k) {
      DayKind.period => Palette.period,
      DayKind.predicted => Palette.predicted,
      DayKind.fertile => Palette.fertile,
      DayKind.ovulation => Palette.ovulation,
      DayKind.none => null,
    };

/// Длительность анимации с учётом системной настройки «убрать анимации».
Duration motion(BuildContext context, int ms) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true
        ? Duration.zero
        : Duration(milliseconds: ms);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? Palette.night : Palette.paper;
  final fg = dark ? Palette.nightText : Palette.ink;
  final raised = dark ? Palette.nightRaised : Colors.white;
  final accent = dark ? const Color(0xFFF2738F) : Palette.period;

  final scheme = ColorScheme.fromSeed(seedColor: Palette.period, brightness: b)
      .copyWith(
    primary: accent,
    onPrimary: dark ? Palette.night : Colors.white,
    primaryContainer: dark ? const Color(0xFF4A1A2A) : const Color(0xFFFFDDE4),
    onPrimaryContainer: dark ? const Color(0xFFFFD9E1) : const Color(0xFF5A0A1E),
    secondary: Palette.ovulation,
    tertiary: dark ? Palette.fertile : Palette.ovulation,
    surface: bg,
    onSurface: fg,
    onSurfaceVariant: fg.withValues(alpha: 0.62),
    surfaceContainerLowest: raised,
    surfaceContainerLow: raised,
    surfaceContainer: dark ? const Color(0xFF1D1017) : const Color(0xFFFCEDF0),
    surfaceContainerHigh: dark ? const Color(0xFF2B1B25) : const Color(0xFFF8E3E8),
    surfaceContainerHighest:
        dark ? const Color(0xFF34222D) : const Color(0xFFF3D9DF),
    outline: fg.withValues(alpha: 0.28),
    outlineVariant: fg.withValues(alpha: 0.12),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    fontFamily: kText,
    scaffoldBackgroundColor: bg,
  );
  final t = base.textTheme;
  TextStyle? disp(TextStyle? s, double size, FontWeight w,
          {double spacing = -0.3}) =>
      s?.copyWith(
          fontFamily: kDisplay,
          fontSize: size,
          fontWeight: w,
          letterSpacing: spacing,
          height: 1.15);

  final text = t.copyWith(
    displayLarge: disp(t.displayLarge, 64, FontWeight.w600, spacing: -2),
    headlineMedium: disp(t.headlineMedium, 26, FontWeight.w600, spacing: -0.6),
    headlineSmall: disp(t.headlineSmall, 22, FontWeight.w600, spacing: -0.4),
    titleLarge: disp(t.titleLarge, 19, FontWeight.w500),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: t.bodyLarge?.copyWith(height: 1.4),
    bodyMedium: t.bodyMedium?.copyWith(height: 1.45),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(color: fg, fontSize: 21),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: accent.withValues(alpha: dark ? 0.22 : 0.14),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: kText,
            fontSize: 12,
            fontWeight:
                s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? fg : fg.withValues(alpha: 0.6),
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? accent : fg.withValues(alpha: 0.6),
          )),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: raised,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(
            fontFamily: kText, fontSize: 16, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        minimumSize: const Size(64, 52),
        side: BorderSide(color: fg.withValues(alpha: 0.22)),
        textStyle: const TextStyle(
            fontFamily: kText, fontSize: 16, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
            fontFamily: kText, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: raised,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: fg.withValues(alpha: 0.25),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: raised,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge?.copyWith(color: fg),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? Palette.nightText : Palette.ink,
      contentTextStyle: TextStyle(
          fontFamily: kText,
          color: dark ? Palette.ink : Palette.nightText,
          fontSize: 14.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: const StadiumBorder(),
      extendedTextStyle: const TextStyle(
          fontFamily: kText, fontSize: 15.5, fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: fg.withValues(alpha: 0.1)),
  );
}
