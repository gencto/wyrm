import 'package:flutter/widgets.dart';

import '../charts/trend.dart';
import '../theme/extensions/colors.dart';

/// Where a view is shown (docs/design/specs/genui-views.md §3.2, board
/// `GenStyle`). The density comes from here, never from the document: the
/// catalog widgets read it from [ViewScope].
enum ViewDensity {
  /// A desk with a pointer: values 24 px, buttons 40, header 56, gap 12.
  desktop(value: 24, button: 40, header: 56, gap: 12, label: 13, pad: 16),

  /// A touch panel of 10–15": values 34, buttons 56, header 68, gap 16;
  /// the menu is a row of tabs 52 high.
  panel(value: 34, button: 56, header: 68, gap: 16, label: 15, pad: 20),

  /// A phone: values 22, buttons 56, the menu is a bottom bar.
  phone(value: 22, button: 56, header: 56, gap: 12, label: 13, pad: 14),

  /// A wall screen: as [panel], the menu hidden.
  kiosk(value: 34, button: 56, header: 68, gap: 16, label: 15, pad: 20);

  const ViewDensity({
    required this.value,
    required this.button,
    required this.header,
    required this.gap,
    required this.label,
    required this.pad,
  });

  /// The size of a value's figures at size `m`.
  final double value;

  /// The height of a button, a switch row, a slider row.
  final double button;

  /// The height of the frame's header.
  final double header;

  /// The gap between parts.
  final double gap;

  /// The size of a label.
  final double label;

  /// The padding inside a card.
  final double pad;

  /// The height of the menu as a row of tabs.
  static const double tabs = 52;

  /// The density of a surface [width] wide: a phone below 600, a panel up
  /// to 1100, a desktop above.
  static ViewDensity forWidth(double width) => width < 600
      ? phone
      : width <= 1100
      ? panel
      : desktop;

  /// Stacked instead of side by side: a `Row` of the document becomes a
  /// column.
  bool get narrow => this == phone;
}

/// The `size` a document may choose on Value, Gauge and Symbol.
enum ViewSize {
  s(0.75),
  m(1),
  l(1.5);

  const ViewSize(this.scale);

  final double scale;

  static ViewSize of(Object? name) => switch (name) {
    's' => s,
    'l' => l,
    _ => m,
  };
}

/// What a value or a symbol says about its point. The colours are fixed
/// (after ISA-101, §3.2): colour means state, never decoration.
enum ViewState {
  /// A value in its range: `text1`.
  normal,

  /// Running, on: `good`.
  on,

  /// A warn limit crossed, or an uncertain value: `warn`.
  warn,

  /// A bad limit crossed, a fault, an active alarm: `bad`.
  alarm,

  /// Stopped, no data, not readable: `muted`.
  off;

  Color of(AppColors c) => switch (this) {
    normal => c.text1,
    on => c.good,
    warn => c.warn,
    alarm => c.bad,
    off => c.muted,
  };

  /// The worse of two states, for a badge or a card.
  ViewState worse(ViewState other) => _rank > other._rank ? this : other;

  int get _rank => switch (this) {
    alarm => 3,
    warn => 2,
    _ => 0,
  };
}

/// What the page hands down to every catalog widget of a surface: the
/// density of where it is shown and how times are written.
class ViewScope extends InheritedWidget {
  const ViewScope({
    required this.density,
    required this.format,
    required super.child,
    super.key,
  });

  final ViewDensity density;
  final TrendFormat format;

  static ViewScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ViewScope>()!;

  /// The density here; a desktop outside a surface (a gallery, a test of
  /// one widget).
  static ViewDensity densityOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ViewScope>()?.density ??
      .desktop;

  @override
  bool updateShouldNotify(ViewScope old) =>
      old.density != density || old.format != format;
}
