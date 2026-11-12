/// How theming is organized in this project.
///
/// Three layers, and a token belongs to exactly one of them.
///
/// 1. `ColorScheme` — anything with a Material role.
/// 2. `ThemeExtension` — the canvas palette by its own names. `AppColors`,
///    read as `context.colors`. Register the same set in both brightnesses,
///    or `lerp` pops instead of interpolating.
/// 3. `const` scales — invariant across themes: `AppSpacing`, `AppRadii`,
///    `AppFonts`.
///
/// The values are the design canvas's (board *Design system*, ADR 0037 rule
/// 7). Studio is dark first; the light palette is a stand-in until a light
/// design exists.
///
/// Caveat: `ThemeData.lerp` does not interpolate `inputDecorationTheme`, it
/// swaps it at t=0.5. Colours that must animate therefore stay out of the baked
/// theme — see [inputDecorationThemeFrom].
library;

import 'package:material_ui/material_ui.dart';

import 'extensions/colors.dart';
import 'radii.dart';
import 'typography.dart';

/// The canvas palette (board *Design system* §02).
const darkColors = AppColors(
  ground0: Color(0xFF0E1113),
  ground1: Color(0xFF13171A),
  ground2: Color(0xFF161A1D),
  ground3: Color(0xFF1D2226),
  ground4: Color(0xFF22282D),
  line1: Color(0xFF252B30),
  line2: Color(0xFF2F373D),
  line3: Color(0xFF3A4249),
  text1: Color(0xFFECE9E1),
  text2: Color(0xFFC5CBCE),
  text3: Color(0xFFA3ABAF),
  text4: Color(0xFF8E979C),
  muted: Color(0xFF5A6168),
  ember: Color(0xFFE8893A),
  emberSoft: Color(0xFFF3A766),
  emberNew: Color(0xFFF6C59A),
  emberTint: Color(0xFF2A1F16),
  emberFill: Color(0xFF1E1813),
  emberLine: Color(0xFF5A3E25),
  onEmber: Color(0xFF0E1113),
  good: Color(0xFF6CC4B0),
  goodTint: Color(0xFF15302A),
  goodLine: Color(0xFF36705F),
  warn: Color(0xFFE2C15A),
  warnTint: Color(0xFF2E2814),
  warnLine: Color(0xFF4A4020),
  bad: Color(0xFFE07A5F),
  badText: Color(0xFFF0A28D),
  badTint: Color(0xFF33201B),
  badLine: Color(0xFF5A3328),
  thumb: Color(0xFF2F373D),
  thumbHover: Color(0xFF4A535A),
);

/// A light stand-in with the same roles (no light design yet).
const lightColors = AppColors(
  ground0: Color(0xFFF3F1EC),
  ground1: Color(0xFFFAF9F6),
  ground2: Color(0xFFFFFFFF),
  ground3: Color(0xFFEDEAE3),
  ground4: Color(0xFFE4E0D8),
  line1: Color(0xFFE2DED6),
  line2: Color(0xFFD3CEC4),
  line3: Color(0xFFBDB7AC),
  text1: Color(0xFF1B1F22),
  text2: Color(0xFF353B40),
  text3: Color(0xFF545B61),
  text4: Color(0xFF6B7378),
  muted: Color(0xFF9AA0A5),
  ember: Color(0xFFC0651A),
  emberSoft: Color(0xFFB0581A),
  emberNew: Color(0xFF8F4510),
  emberTint: Color(0xFFF7E6D6),
  emberFill: Color(0xFFFBF1E8),
  emberLine: Color(0xFFE2B48A),
  onEmber: Color(0xFFFFFFFF),
  good: Color(0xFF237A66),
  goodTint: Color(0xFFDDF1EC),
  goodLine: Color(0xFF8CC9BA),
  warn: Color(0xFF8A6D0E),
  warnTint: Color(0xFFF6EDCF),
  warnLine: Color(0xFFD9C27A),
  bad: Color(0xFFB3462B),
  badText: Color(0xFF9A3A22),
  badTint: Color(0xFFF8E3DD),
  badLine: Color(0xFFE0A897),
  thumb: Color(0xFFCFCAC0),
  thumbHover: Color(0xFFB1AA9E),
);

ThemeData lightTheme() => _themeFrom(lightColors, .light);

ThemeData darkTheme() => _themeFrom(darkColors, .dark);

ThemeData _themeFrom(AppColors c, Brightness brightness) {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: c.ember,
        brightness: brightness,
      ).copyWith(
        primary: c.ember,
        onPrimary: c.onEmber,
        secondary: c.good,
        onSecondary: c.ground0,
        error: c.bad,
        onError: c.ground0,
        surface: c.ground0,
        onSurface: c.text1,
        onSurfaceVariant: c.text3,
        surfaceContainerLowest: c.ground0,
        surfaceContainerLow: c.ground1,
        surfaceContainer: c.ground2,
        surfaceContainerHigh: c.ground3,
        surfaceContainerHighest: c.ground4,
        outline: c.line2,
        outlineVariant: c.line1,
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: AppFonts.sans,
    scaffoldBackgroundColor: c.ground0,
    canvasColor: c.ground0,
    dividerColor: c.line1,
  );

  return base.copyWith(
    textTheme: appTextTheme(base.textTheme, c),
    inputDecorationTheme: inputDecorationThemeFrom(
      base.inputDecorationTheme,
      colorScheme,
    ),
    elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
    scrollbarTheme: _scrollbarTheme(c),
    dividerTheme: DividerThemeData(color: c.line1, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.ground4,
        borderRadius: Radii.chip,
        border: .all(color: c.line2),
      ),
      textStyle: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 12,
        color: c.text1,
      ),
    ),
    // Both brightnesses go through here, so the two themes always carry the
    // same extension set.
    extensions: [c],
  );
}

/// Board *Design system* §06 Scrollbars: 6 px (10 with a 2 px clear border),
/// thumb line/2, hover #4A535A, no track, radius 8.
ScrollbarThemeData _scrollbarTheme(AppColors c) => ScrollbarThemeData(
  thickness: const WidgetStatePropertyAll(6),
  radius: const Radius.circular(8),
  crossAxisMargin: 2,
  thumbColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.hovered) ? c.thumbHover : c.thumb,
  ),
  trackVisibility: const WidgetStatePropertyAll(false),
);

/// Flat, ember-filled buttons in place of M3's tonal elevated pill.
ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme scheme) =>
    ElevatedButtonThemeData(
      style:
          ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            // `Material` runs its own 200ms animation and would trail the
            // theme; zero keeps the two in step.
            animationDuration: .zero,
            shape: const RoundedRectangleBorder(borderRadius: Radii.button),
          ).copyWith(
            // Not `styleFrom(elevation: 0)` — that still lifts to +2 on hover
            // and +6 on press.
            elevation: const WidgetStatePropertyAll(0),
          ),
    );

/// Shape and metrics shared by every field, independent of brightness.
const _inputShape = OutlineInputBorder(borderRadius: Radii.input);

/// Filled fields (ground/3) with a line/2 border; ember when focused.
///
/// Takes the `ColorScheme` so the caller picks when colours resolve:
/// `ThemeData` bakes them once, `InputFormField` re-reads them per build off
/// the live theme so a border tracks a switch instead of jumping at t=0.5.
InputDecorationThemeData inputDecorationThemeFrom(
  InputDecorationThemeData theme,
  ColorScheme scheme,
) {
  final line = OutlineInputBorder(
    borderRadius: Radii.input,
    borderSide: BorderSide(color: scheme.outline),
  );

  return theme.copyWith(
    isDense: true,
    errorMaxLines: 10,
    filled: true,
    fillColor: scheme.surfaceContainerHigh,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: _inputShape,
    enabledBorder: line,
    disabledBorder: line,
    focusedBorder: OutlineInputBorder(
      borderRadius: Radii.input,
      borderSide: BorderSide(color: scheme.primary),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: Radii.input,
      borderSide: BorderSide(color: scheme.error),
    ),
    labelStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
    hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
    focusColor: scheme.primary,
  );
}
