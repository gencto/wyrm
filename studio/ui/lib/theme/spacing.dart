import 'package:flutter/widgets.dart';

/// The spacing scale — layer 3 of the theme strategy (see `common.dart`).
///
/// A 4-point scale, doubling from [sm]. A value off the scale is a smell: the
/// point is that screens built from these line up with each other.
abstract final class AppSpacing {
  /// No space, where a constructor asks for every side.
  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Ready-made gaps, so a layout reads as rhythm rather than arithmetic.
abstract final class Gaps {
  /// Vertical — the common case, since columns dominate these layouts.
  static const Widget xs = SizedBox(height: AppSpacing.xs);
  static const Widget sm = SizedBox(height: AppSpacing.sm);
  static const Widget md = SizedBox(height: AppSpacing.md);
  static const Widget lg = SizedBox(height: AppSpacing.lg);
  static const Widget xl = SizedBox(height: AppSpacing.xl);

  /// Horizontal, for a `Row`.
  static const Widget hXs = SizedBox(width: AppSpacing.xs);
  static const Widget hSm = SizedBox(width: AppSpacing.sm);
  static const Widget hMd = SizedBox(width: AppSpacing.md);
  static const Widget hLg = SizedBox(width: AppSpacing.lg);
  static const Widget hXl = SizedBox(width: AppSpacing.xl);
}

/// Padding built from the same scale, and the paddings the canvas repeats,
/// named for what they pad.
abstract final class Insets {
  static const sm = EdgeInsets.all(AppSpacing.sm);
  static const md = EdgeInsets.all(AppSpacing.md);
  static const lg = EdgeInsets.all(AppSpacing.lg);

  /// Screen-edge padding: generous horizontally, tighter vertically.
  static const screen = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.lg,
  );

  /// Inside a one-line control of a fixed height: a field, a chip, a
  /// search box, a block's header row.
  static const control = EdgeInsets.symmetric(horizontal: 10);

  /// Inside a card or a row of a card list (Account › Security's options
  /// and devices, a found gateway, a notice).
  static const card = EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  /// Inside an alert or a banner that spans its panel.
  static const notice = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: 14,
  );

  /// Inside a bordered panel of System: a value's tile, the Log toolbar
  /// (board `System`).
  static const systemPanel = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: 14,
  );

  /// Around System's main column, beside the attention panel (board
  /// `System`: 28 at the sides).
  static const systemColumn = EdgeInsets.symmetric(
    horizontal: 28,
    vertical: AppSpacing.lg,
  );

  /// Around an Assistant card: indented past the avatar column (42) and
  /// apart from the next card.
  static const assistantCard = EdgeInsets.only(left: 42, bottom: 12);

  /// An Assistant line under the model's mark: indented past the avatar
  /// column, as [assistantCard] is.
  static const assistantIndent = EdgeInsets.only(left: 42);

  /// The title row of a card with rows under it (a plan, a run): as
  /// [card] at the sides and the top, tighter above the first row.
  static const cardHead = EdgeInsets.fromLTRB(14, 12, 14, 10);

  /// One row of a card (a plan's step, a suggestion's title): as [card]
  /// at the sides, tighter between rows.
  static const cardRow = EdgeInsets.symmetric(horizontal: 14, vertical: 10);

  /// The line that closes a card under its rows (a note): tighter under
  /// the last row, as [card] at the bottom.
  static const cardFoot = EdgeInsets.fromLTRB(14, 10, 14, 12);

  /// Inside a warning band in a card (a link's finding, a caution).
  static const band = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

  /// Inside a removable chip: the text, then its close button.
  static const chip = EdgeInsets.only(left: AppSpacing.sm, right: 2);

  /// Around a small text button beside chips (`+ prefix`).
  static const textLink = EdgeInsets.symmetric(horizontal: 6, vertical: 3);

  // ---- the log-in page, the unlock, the lock and the step-up ----

  /// Around the log-in form, in its panel (login.md §1: 40 × 32).
  static const logInForm = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
    vertical: 40,
  );

  /// Around the welcome while the tree opens.
  static const welcome = EdgeInsets.symmetric(vertical: 40);

  /// Around the hero's content (login.md §2: 40 × 48).
  static const hero = EdgeInsets.fromLTRB(48, 40, 48, 40);

  /// Beside the hero's logo mark.
  static const heroMark = EdgeInsets.only(right: 1);

  /// Above the trust card or the panel of found gateways, under the
  /// gateway field's status line.
  static const underGateway = EdgeInsets.only(top: 12);

  /// Above a footer's text, under its rule (the log-in form, the unlock).
  static const footer = EdgeInsets.only(top: 14);

  /// Beside the label of a button of a fixed height (the alert's buttons,
  /// *Find on this network*, *Probe*).
  static const button = EdgeInsets.symmetric(horizontal: 14);

  /// Inside a small field of a row of fields (*Probe a range*).
  static const smallField = EdgeInsets.symmetric(horizontal: 12);

  /// Inside the box of the CA code on the trust card.
  static const caCode = EdgeInsets.all(12);

  /// Inside the panel of found gateways, and the step-up's device row.
  static const panelBox = EdgeInsets.all(14);

  /// Above a bullet's dot, to sit on the first line of its text.
  static const bulletDot = EdgeInsets.only(top: 7);

  /// Above *Probe a range instead*, under the reasons.
  static const probeRange = EdgeInsets.only(top: 10);

  /// Inside a tag of a found gateway.
  static const foundTag = EdgeInsets.symmetric(horizontal: 7, vertical: 1);

  /// Above and below the round unlock button and its lines.
  static const unlockButton = EdgeInsets.symmetric(vertical: 6);

  /// Inside the account card of the unlock.
  static const accountCard = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: 14,
  );

  /// The step-up dialog: its head, the box of changes, a row under them
  /// (the password, the device), the gap above its foot and the foot.
  static const dialogHead = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    22,
    AppSpacing.lg,
    6,
  );
  static const dialogList = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: 10,
  );
  static const dialogRow = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    6,
    AppSpacing.lg,
    AppSpacing.none,
  );
  static const dialogFootGap = EdgeInsets.only(top: 12);
  static const dialogFoot = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: 18,
  );

  /// Inside the level badge of a step-up change.
  static const levelBadge = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: 2,
  );
}
