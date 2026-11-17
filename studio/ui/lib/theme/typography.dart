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
        fontSize: FontSizes.pageTitle,
        height: LineHeights.pageTitle,
        fontWeight: FontWeight.w600,
        color: c.text1,
      ),
      titleLarge: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: FontSizes.panelTitle,
        height: LineHeights.title,
        fontWeight: FontWeight.w600,
        color: c.text1,
      ),
      titleMedium: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: FontSizes.sectionTitle,
        height: LineHeights.meta,
        fontWeight: FontWeight.w600,
        color: c.text1,
      ),
      titleSmall: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: FontSizes.lg,
        height: LineHeights.meta,
        fontWeight: FontWeight.w600,
        color: c.text1,
      ),
      bodyLarge: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: FontSizes.lg,
        height: LineHeights.body,
        color: c.text1,
      ),
      bodyMedium: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: FontSizes.md,
        height: LineHeights.row,
        color: c.text2,
      ),
      bodySmall: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: FontSizes.sm,
        height: LineHeights.meta,
        color: c.text3,
      ),
      labelLarge: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: FontSizes.lg,
        fontWeight: FontWeight.w500,
        color: c.text1,
      ),
      labelMedium: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: FontSizes.sm,
        fontWeight: FontWeight.w600,
        letterSpacing: Trackings.label,
        color: c.text3,
      ),
      labelSmall: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: FontSizes.xs,
        fontWeight: FontWeight.w500,
        color: c.text3,
      ),
    );

/// Mono text: a key, a value, a code (Plex Mono 400 13/1.5 by default).
/// [size] is a step of [FontSizes]: a number cannot be written here.
TextStyle mono({
  FontSize size = FontSizes.md,
  FontWeight weight = FontWeight.w400,
  Color? color,
}) => TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: size,
  height: LineHeights.body,
  fontWeight: weight,
  color: color,
);

/// The wordmark (Unbounded 700).
TextStyle wordmark({FontSize size = FontSizes.wordmark, Color? color}) =>
    TextStyle(
      fontFamily: AppFonts.display,
      fontSize: size,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
      color: color,
      letterSpacing: Trackings.wordmark,
    );

/// Text as a board writes it in CSS: the size, the weight and the line
/// height it names, and no tracking. Material's base styles carry a letter
/// spacing (0.25 on `bodyMedium`) that a style without one inherits, which
/// makes a line about 3 % wider than the board's; the error surfaces
/// (docs/design/specs/errors.md) are measured against their boards, so they
/// say all four. [code] is Plex Mono. The default height is the browser's
/// `normal` for Plex. [size], [height] and [tracking] are tokens of
/// [FontSizes], [LineHeights] and [Trackings]: a number cannot be written
/// here.
TextStyle boardText({
  FontSize size = FontSizes.lg,
  FontWeight weight = FontWeight.w400,
  Color? color,
  LineHeight height = LineHeights.title,
  bool code = false,
  Tracking tracking = Trackings.none,
}) => TextStyle(
  fontFamily: code ? AppFonts.mono : AppFonts.sans,
  fontSize: size,
  height: height,
  fontWeight: weight,
  letterSpacing: tracking,
  color: color,
);

/// A font size of the canvas: one of [FontSizes]. It is a `double` wherever
/// one is read (`TextStyle.fontSize`), and it is made only in this file, so
/// a parameter of this type takes a token and never a number.
extension type const FontSize._(double _value) implements double {}

/// A line height of the canvas, as a multiple of the font size: one of
/// [LineHeights], made only in this file.
extension type const LineHeight._(double _value) implements double {}

/// A letter spacing of the canvas, in logical pixels: one of [Trackings],
/// made only in this file.
extension type const Tracking._(double _value) implements double {}

/// The font sizes of the canvas (board *Design system* §03). The four
/// body steps are a scale, like `AppSpacing`: [xs] … [lg] say where a size
/// sits, not what the text is. The titles and the figure are named for what
/// they set. A size off both lists is a smell: it gets a name here first.
abstract final class FontSizes {
  static const xxs = FontSize._(10);
  static const xs = FontSize._(11);
  static const sm = FontSize._(12);
  static const md = FontSize._(13);
  static const lg = FontSize._(14);

  /// A section's title (`titleMedium`).
  static const sectionTitle = FontSize._(16);

  /// A panel's or a dialog's title (`titleLarge`).
  static const panelTitle = FontSize._(20);

  /// A large figure: a tile's value, a metric.
  static const figure = FontSize._(22);

  /// A page's title (`headlineSmall`).
  static const pageTitle = FontSize._(26);

  /// A kind or tag chip of the flow editor: a block's `NODE` / `FX`, a
  /// palette row's `IN` / `OUT` (mono 600).
  static const flowTag = FontSize._(9);

  /// The detail beside or under a flow value: an inspector field's engine
  /// name and targets, its `bound` mark, a point's tag in the palette.
  static const flowDetail = FontSize._(10);

  /// The − / + glyph of a flow block's tool button.
  static const flowToolGlyph = FontSize._(15);

  /// The block's id at the top of the flow inspector (mono 600).
  static const flowInspectorTitle = FontSize._(18);

  /// A line set above the body: the account and the round button's label
  /// on the unlock, the lock card's lines, the groups of a CA code.
  static const lead = FontSize._(15);

  /// The label of a tall button (log in, the offer's `Use`).
  static const tallButton = FontSize._(16);

  /// The hero's lead under its headline.
  static const heroLead = FontSize._(16);

  /// The title of the lock card over the dimmed shell.
  static const lockTitle = FontSize._(22);

  /// The title of a sheet, an inspector or an error dialog.
  static const sheetTitle = FontSize._(18);

  /// A value set large where it is read or edited: the value viewer's
  /// editor and its yes/no, a task's number.
  static const value = FontSize._(20);

  /// The number the value viewer shows alone, and the unit beside it.
  static const soleValue = FontSize._(28);
  static const soleValueUnit = FontSize._(16);

  /// The title of the start fault, of a gallery section.
  static const faultTitle = FontSize._(28);
  static const galleryTitle = FontSize._(28);

  /// The wordmark of the logo, small and large, and on the gallery.
  static const logo = FontSize._(16);
  static const logoLarge = FontSize._(18);
  static const display = FontSize._(32);

  /// The words beside the logo, small and large.
  static const logoWords = FontSize._(14);
  static const logoWordsLarge = FontSize._(15);

  /// The `×` that closes a dialog where it is written as text.
  static const closeGlyph = FontSize._(18);

  /// The title of the conversation on the Assistant page.
  static const conversationTitle = FontSize._(17);

  /// The text typed into a boxed field (the log-in form).
  static const boxedField = FontSize._(15);

  /// The hero's headline, beside the form and above it.
  static const heroHeadline = FontSize._(40);
  static const heroHeadlineSmall = FontSize._(28);

  /// The wordmark where nothing sets its size.
  static const wordmark = FontSize._(17);
}

/// The line heights of the canvas (board *Design system* §03), named for
/// the text they set. A height off this list is a smell: it gets a name
/// here first.
abstract final class LineHeights {
  /// One glyph or one key cap on its own line.
  static const glyph = LineHeight._(1.1);

  /// The hero's headline.
  static const headline = LineHeight._(1.12);

  /// A page's title (`headlineSmall`), a flow block's name.
  static const pageTitle = LineHeight._(1.2);

  /// A panel's title (`titleLarge`), a field's own text, and the
  /// browser's `normal` for Plex (what `boardText` takes by default).
  static const title = LineHeight._(1.3);

  /// A title that may wrap to a second line.
  static const wrappedTitle = LineHeight._(1.35);

  /// Meta text and section titles (`bodySmall`, `titleMedium`).
  static const meta = LineHeight._(1.4);

  /// A row of a list or a table (`bodyMedium`).
  static const row = LineHeight._(1.45);

  /// Body text (`bodyLarge`) and mono text.
  static const body = LineHeight._(1.5);

  /// A paragraph that is read: an answer, what the broker said, a note.
  static const prose = LineHeight._(1.55);

  /// A lead paragraph under a headline.
  static const lead = LineHeight._(1.6);

  /// Lines of code or commands listed one under another.
  static const listing = LineHeight._(1.7);
}

/// The letter spacings of the canvas. Caps labels are spaced +6 % of
/// their size (board *Design system* §03); titles are tightened by 1 %.
abstract final class Trackings {
  /// No tracking, said so that Material's own is not inherited.
  static const none = Tracking._(0);

  /// A caps label of 12 (`labelMedium`): +6 %.
  static const label = Tracking._(0.72);

  /// A caps label of 11: +6 %.
  static const smallLabel = Tracking._(0.66);

  /// The operation tag of a review card (11, +5 %).
  static const opTag = Tracking._(0.55);

  /// The head of a points table column (12, +4 %).
  static const columnHead = Tracking._(0.48);

  /// A page's title of 26: −1 %.
  static const pageTitle = Tracking._(-0.26);

  /// The title of the start fault of 28: −1 %.
  static const faultTitle = Tracking._(-0.28);

  /// The hero's headline of 40 and of 28: −2 %.
  static const heroHeadline = Tracking._(-0.8);
  static const heroHeadlineSmall = Tracking._(-0.56);

  /// The groups of a CA code.
  static const caCode = Tracking._(1.2);

  /// The dots of a hidden secret in a boxed field.
  static const hiddenSecret = Tracking._(3);

  /// The wordmark where nothing sets its tracking.
  static const wordmark = Tracking._(0.4);

  /// The wordmark of the logo, small and large: +8 % of 16 and of 18.
  static const logo = Tracking._(1.28);
  static const logoLarge = Tracking._(1.44);
}

/// Text styles that set the size only: a widget adds its colour and weight
/// with `copyWith` (`AppText.sm.copyWith(color: c.text4)`), which is the
/// same style as `TextStyle(fontSize: FontSizes.sm, color: …)` written out.
abstract final class AppText {
  static const xs = TextStyle(fontSize: FontSizes.xs);
  static const sm = TextStyle(fontSize: FontSizes.sm);
  static const md = TextStyle(fontSize: FontSizes.md);
  static const lg = TextStyle(fontSize: FontSizes.lg);
}
