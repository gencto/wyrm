import 'package:material_ui/material_ui.dart';

import 'extensions/colors.dart';

/// Board *Design system* §03: IBM Plex Sans for reading, IBM Plex Mono for
/// anything a machine reads (keys, node names, registers, values, units),
/// Unbounded for the wordmark only. All three are bundled in `ui` (no font
/// download at run time: edge machines are often offline).
abstract final class AppFonts {
  // Declared in `ui/pubspec.yaml`; a family of a dependency package is named
  // `packages/<package>/<family>` wherever it is used, the app included.
  static const sans = 'packages/ui/IBM Plex Sans';
  static const mono = 'packages/ui/IBM Plex Mono';
  static const display = 'packages/ui/Unbounded';
}

/// The type scale of the canvas, as named text styles.
///
/// | Style | Canvas | Use |
/// |---|---|---|
/// | `headlineSmall` | title/page 26/600 | page title |
/// | `titleLarge` | title/panel 20/600 | inspector title |
/// | `titleMedium` | 16/600 | section |
/// | `bodyLarge` | body 14 | body |
/// | `bodyMedium` | 13 | rows |
/// | `bodySmall` | 12 | meta |
/// | `labelMedium` | label 12/600 caps +6 % | section label |
/// | `labelSmall` | 11 | tags |
TextTheme appTextTheme(TextTheme base, AppColors c) => base
    .apply(
      fontFamily: AppFonts.sans,
      bodyColor: c.text1,
      displayColor: c.text1,
    )
    .copyWith(
      headlineSmall: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: c.text1,
      ),
      titleLarge: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: c.text1,
      ),
      titleMedium: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: c.text1,
      ),
      titleSmall: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: c.text1,
      ),
      bodyLarge: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 14,
        height: 1.5,
        color: c.text1,
      ),
      bodyMedium: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 13,
        height: 1.45,
        color: c.text2,
      ),
      bodySmall: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 12,
        height: 1.4,
        color: c.text3,
      ),
      labelLarge: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: c.text1,
      ),
      labelMedium: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.72,
        color: c.text3,
      ),
      labelSmall: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: c.text3,
      ),
    );

/// Mono text: a key, a value, a code (Plex Mono 400 13/1.5 by default).
TextStyle mono({
  double size = 13,
  FontWeight weight = FontWeight.w400,
  Color? color,
}) => TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: size,
  height: 1.5,
  fontWeight: weight,
  color: color,
);

/// The wordmark (Unbounded 700).
TextStyle wordmark({double size = 17, Color? color}) => TextStyle(
  fontFamily: AppFonts.display,
  fontSize: size,
  fontWeight: FontWeight.w700,
  fontVariations: const [FontVariation('wght', 700)],
  color: color,
  letterSpacing: 0.4,
);

/// Text as a board writes it in CSS: the size, the weight and the line
/// height it names, and no tracking. Material's base styles carry a letter
/// spacing (0.25 on `bodyMedium`) that a style without one inherits, which
/// makes a line about 3 % wider than the board's; the error surfaces
/// (docs/design/specs/errors.md) are measured against their boards, so they
/// say all four. [code] is Plex Mono. The default height is the browser's
/// `normal` for Plex.
TextStyle boardText({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double height = 1.3,
  bool code = false,
  double tracking = 0,
}) => TextStyle(
  fontFamily: code ? AppFonts.mono : AppFonts.sans,
  fontSize: size,
  height: height,
  fontWeight: weight,
  letterSpacing: tracking,
  color: color,
);

/// The font sizes of the canvas, by what they set (board *Design system*
/// §03). `TextStyle(fontSize: FontSizes.meta, …)` where a style is written
/// out; [AppText] for a new one.
abstract final class FontSizes {
  /// A badge's count, a superscript.
  static const double micro = 10;

  /// A tag, a column head, a tile word (`labelSmall`).
  static const double tag = 11;

  /// Meta text, a caption, a hint (`bodySmall`, `labelMedium`).
  static const double meta = 12;

  /// A row of a list or a table (`bodyMedium`).
  static const double row = 13;

  /// Body text, a field, a button (`bodyLarge`).
  static const double body = 14;

  /// A lead line under a title.
  static const double lead = 15;

  /// A section title (`titleMedium`).
  static const double section = 16;

  /// A card's heading.
  static const double heading = 18;

  /// A panel's or a dialog's title (`titleLarge`).
  static const double panel = 20;

  /// A large figure, a hero line.
  static const double display = 22;

  /// A page title (`headlineSmall`).
  static const double page = 26;
}

/// Text styles that set the size only: a widget adds its colour and weight
/// with `copyWith` (`AppText.meta.copyWith(color: c.text4)`), which is the
/// same style as `TextStyle(fontSize: 12, color: …)` written out.
abstract final class AppText {
  static const micro = TextStyle(fontSize: FontSizes.micro);
  static const tag = TextStyle(fontSize: FontSizes.tag);
  static const meta = TextStyle(fontSize: FontSizes.meta);
  static const row = TextStyle(fontSize: FontSizes.row);
  static const body = TextStyle(fontSize: FontSizes.body);
  static const lead = TextStyle(fontSize: FontSizes.lead);
  static const section = TextStyle(fontSize: FontSizes.section);
  static const heading = TextStyle(fontSize: FontSizes.heading);
  static const panel = TextStyle(fontSize: FontSizes.panel);
  static const display = TextStyle(fontSize: FontSizes.display);
  static const page = TextStyle(fontSize: FontSizes.page);
}
