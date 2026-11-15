import 'package:flutter/widgets.dart';

/// The spacing scale — layer 3 of the theme strategy (see `common.dart`).
///
/// [xs] … [xl] are the rhythm: a 4-point scale, doubling from [sm]. The
/// design canvas also uses the steps in between; they are named by their
/// pixels (`s12` is 12), and only where no rhythm name has the same value,
/// so every value has exactly one name. A value on neither list is off the
/// scale: it gets a token here, named for what it is for, before it is used.
abstract final class AppSpacing {
  static const double none = 0;

  /// A hairline offset: a border's width, a nudge.
  static const double s1 = 1;
  static const double s2 = 2;
  static const double s3 = 3;
  static const double xs = 4;
  static const double s6 = 6;
  static const double sm = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double md = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s22 = 22;
  static const double lg = 24;
  static const double s28 = 28;
  static const double xl = 32;
  static const double s40 = 40;
  static const double s42 = 42;
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

/// Padding built from the same scale.
///
/// The `const` forms are fields: [sm], [md], [lg], [screen]. The side and
/// axis forms read as the board says them — `Insets.top.sm`,
/// `Insets.h.md`, `Insets.v.of(AppSpacing.s10)` — and are not `const` (a
/// getter of a const object is not a constant); inside a `const` widget
/// write `EdgeInsets.only(top: AppSpacing.sm)` instead.
abstract final class Insets {
  static const EdgeInsets none = EdgeInsets.zero;
  static const xs = EdgeInsets.all(AppSpacing.xs);
  static const sm = EdgeInsets.all(AppSpacing.sm);
  static const md = EdgeInsets.all(AppSpacing.md);
  static const lg = EdgeInsets.all(AppSpacing.lg);

  /// Screen-edge padding: generous horizontally, tighter vertically.
  static const screen = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.lg,
  );

  /// One side: `Insets.top.sm` is `EdgeInsets.only(top: 8)`.
  static const top = InsetsOf._(_Side.top);
  static const bottom = InsetsOf._(_Side.bottom);
  static const left = InsetsOf._(_Side.left);
  static const right = InsetsOf._(_Side.right);

  /// One axis: `Insets.h.md` is `EdgeInsets.symmetric(horizontal: 16)`.
  static const h = InsetsOf._(_Side.horizontal);
  static const v = InsetsOf._(_Side.vertical);
}

enum _Side { top, bottom, left, right, horizontal, vertical }

/// The spacing scale on one side or one axis (see [Insets.top], [Insets.h]).
final class InsetsOf {
  const InsetsOf._(this._side);

  final _Side _side;

  /// Any value of [AppSpacing] on this side or axis.
  EdgeInsets of(double v) => switch (_side) {
    _Side.top => EdgeInsets.only(top: v),
    _Side.bottom => EdgeInsets.only(bottom: v),
    _Side.left => EdgeInsets.only(left: v),
    _Side.right => EdgeInsets.only(right: v),
    _Side.horizontal => EdgeInsets.symmetric(horizontal: v),
    _Side.vertical => EdgeInsets.symmetric(vertical: v),
  };

  EdgeInsets get xs => of(AppSpacing.xs);
  EdgeInsets get sm => of(AppSpacing.sm);
  EdgeInsets get md => of(AppSpacing.md);
  EdgeInsets get lg => of(AppSpacing.lg);
  EdgeInsets get xl => of(AppSpacing.xl);
}
