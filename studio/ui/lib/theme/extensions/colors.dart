import 'package:material_ui/material_ui.dart';
import 'package:theme_extensions_builder_annotation/theme_extensions_builder_annotation.dart';

part 'colors.g.theme.dart';

/// The WYRM Studio palette (design canvas, board *Design system* §02).
///
/// Read via `context.colors`. The roles that Material has (page, surfaces,
/// primary, error, text) also feed `ColorScheme` — see `theme/common.dart` —
/// but the names here are the canvas's own, so a widget reads the token the
/// design names: `context.colors.goodTint`, `context.colors.line2`.
@ThemeExtensions(contextAccessorName: 'colors')
class AppColors extends ThemeExtension<AppColors> with _$AppColors {
  const AppColors({
    required this.ground0,
    required this.ground1,
    required this.ground2,
    required this.ground3,
    required this.ground4,
    required this.line1,
    required this.line2,
    required this.line3,
    required this.text1,
    required this.text2,
    required this.text3,
    required this.text4,
    required this.muted,
    required this.ember,
    required this.emberSoft,
    required this.emberNew,
    required this.emberTint,
    required this.emberFill,
    required this.emberLine,
    required this.onEmber,
    required this.good,
    required this.goodTint,
    required this.goodLine,
    required this.warn,
    required this.warnTint,
    required this.warnLine,
    required this.bad,
    required this.badText,
    required this.badTint,
    required this.badLine,
    required this.thumb,
    required this.thumbHover,
  });

  /// App background, workspace.
  final Color ground0;

  /// Panels: tree, inspector, rail.
  final Color ground1;

  /// Cards, rows, flow blocks.
  final Color ground2;

  /// Inputs, hover, selected row.
  final Color ground3;

  /// Chips, the active rail item.
  final Color ground4;

  /// Panel borders, dividers.
  final Color line1;

  /// Input borders.
  final Color line2;

  /// Secondary button border.
  final Color line3;

  /// Primary text, values.
  final Color text1;

  /// Body in tables.
  final Color text2;

  /// Secondary, labels.
  final Color text3;

  /// Captions, keys (12 px and up).
  final Color text4;

  /// Disabled text, an empty ring.
  final Color muted;

  /// Primary action, selection, staged.
  final Color ember;

  /// Staged text, hover links.
  final Color emberSoft;

  /// A new value in a diff.
  final Color emberNew;

  /// Selected tree row, the OUT tag.
  final Color emberTint;

  /// The fill of a selected card.
  final Color emberFill;

  /// The border of an ember-tinted block.
  final Color emberLine;

  /// Text on an ember fill.
  final Color onEmber;

  /// Good quality, connected, wires.
  final Color good;

  /// Good chip ground.
  final Color goodTint;

  /// The border of a good notice.
  final Color goodLine;

  /// Uncertain, connecting, quarantine.
  final Color warn;

  /// Uncertain chip ground.
  final Color warnTint;

  /// The border of a warning notice.
  final Color warnLine;

  /// Bad, failed, an invalid field.
  final Color bad;

  /// Text in a bad notice.
  final Color badText;

  /// Bad chip and notice ground.
  final Color badTint;

  /// The border of a bad notice.
  final Color badLine;

  /// Scrollbar thumb.
  final Color thumb;

  /// Scrollbar thumb under the pointer.
  final Color thumbHover;
}
