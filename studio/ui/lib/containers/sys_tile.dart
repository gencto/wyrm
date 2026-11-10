import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What [SysTile] draws: one value the broker serves under `sys`.
final class SysTileVm extends Equatable {
  const SysTileVm({
    required this.label,
    required this.keyName,
    required this.value,
    this.unit = '',
    this.sub = '',
    this.tone = Tone.neutral,
    this.subTone = Tone.neutral,
    this.outlined = false,
    this.about = '',
    this.link = false,
  });

  final String label;

  /// The key under `sys` the value is read from (`links_connected`).
  final String keyName;
  final String value;
  final String unit;
  final String sub;

  /// The colour of the value; neutral is the text colour.
  final Tone tone;
  final Tone subTone;

  /// The border takes [tone]: the tile needs a look.
  final bool outlined;

  /// The node's `description`, the tile's tooltip.
  final String about;

  /// The tile opens the screen that fixes it.
  final bool link;

  @override
  List<Object?> get props => [
    label,
    keyName,
    value,
    unit,
    sub,
    tone,
    subTone,
    outlined,
    about,
    link,
  ];
}

/// A `sys` value as a tile: label and key, the value with its unit, one line
/// that says what it means or names the problem (boards `System`,
/// `SystemAvail`). With [onTap] the whole card is a link.
class SysTile extends StatelessWidget {
  const SysTile({
    required this.vm,
    this.onTap,
    this.relaxed = false,
    this.width,
    super.key,
  });

  final SysTileVm vm;
  final VoidCallback? onTap;

  /// The tile's width when its composer knows it (a grid does). With it
  /// the key keeps its whole width and the label wraps beside it; without,
  /// the two share the row and the key ends in an ellipsis first.
  final double? width;

  /// The line under the value is a sentence that may wrap: line height 1.5.
  final bool relaxed;

  /// The label and, at the right, the key. The key keeps its whole width
  /// while the label can still wrap between its words; only when the
  /// label's longest word needs the room does the key end in an ellipsis.
  Widget _head(BuildContext context, AppColors c) {
    final base = DefaultTextStyle.of(context).style;
    final labelStyle = base.merge(TextStyle(fontSize: 12, color: c.text3));
    final keyStyle = base.merge(
      TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: keyColor(c)),
    );
    final keyText = Text(
      vm.keyName,
      maxLines: 1,
      overflow: .ellipsis,
      textAlign: .end,
      style: keyStyle,
    );
    final outer = width;
    if (outer == null) {
      return Row(
        spacing: 6,
        children: [
          Expanded(child: Text(vm.label, style: labelStyle)),
          Flexible(child: keyText),
        ],
      );
    }
    // No LayoutBuilder here: a grid sizes its rows by the tiles' intrinsic
    // height, which a LayoutBuilder cannot answer.
    final scaler = MediaQuery.textScalerOf(context);
    TextPainter measure(String text, TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    final label = measure(vm.label, labelStyle);
    final key = measure(vm.keyName, keyStyle);
    // 16 of padding on each side, 6 between the two.
    final room = (outer - 32 - 6).clamp(0.0, double.infinity);
    final labelWidth = (room - key.width)
        .clamp(label.minIntrinsicWidth, label.maxIntrinsicWidth)
        .clamp(0.0, room)
        .ceilToDouble();
    label.dispose();
    key.dispose();
    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(vm.label, style: labelStyle),
        ),
        const SizedBox(width: 6),
        Expanded(child: keyText),
      ],
    );
  }

  /// The grey of a key name beside a label, between `text4` and the card.
  static Color keyColor(AppColors c) =>
      Color.alphaBlend(c.text4.withValues(alpha: 0.72), c.ground1);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = vm.outlined
        ? switch (vm.tone) {
            .warn => c.warnLine,
            .bad => c.badLine,
            .good => c.goodLine,
            _ => c.line1,
          }
        : c.line1;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          _head(context, c),
          Row(
            crossAxisAlignment: .baseline,
            textBaseline: .alphabetic,
            spacing: 6,
            children: [
              Flexible(
                child: Text(
                  vm.value,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 22,
                    color: vm.tone == .neutral
                        ? c.text1
                        : toneColor(c, vm.tone),
                  ),
                ),
              ),
              if (vm.unit.isNotEmpty)
                Text(
                  vm.unit,
                  style: TextStyle(fontSize: 12, color: c.text4),
                ),
            ],
          ),
          Text(
            vm.sub,
            maxLines: 2,
            overflow: .ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: relaxed ? 1.5 : null,
              color: vm.subTone == .neutral
                  ? c.text4
                  : toneColor(c, vm.subTone),
            ),
          ),
        ],
      ),
    );
    final card = Material(
      color: c.ground1,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: border),
      ),
      clipBehavior: .antiAlias,
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              hoverColor: c.text1.withValues(alpha: 0.04),
              child: body,
            ),
    );
    final tile = Semantics(
      container: true,
      link: onTap != null,
      label: '${vm.label} ${vm.value} ${vm.unit}'.trim(),
      child: card,
    );
    return vm.about.isEmpty
        ? tile
        : Tooltip(
            message: vm.about,
            waitDuration: const Duration(milliseconds: 500),
            child: tile,
          );
  }
}

/// [tiles] in rows of equal columns at least [minWidth] wide, every tile of
/// a row as tall as its tallest (the board's `auto-fit` grid).
class SysTileGrid extends StatelessWidget {
  const SysTileGrid({
    required this.tiles,
    this.onTile,
    this.minWidth = 170,
    this.relaxed = false,
    super.key,
  });

  /// As [SysTile.relaxed], for every tile.
  final bool relaxed;

  final List<SysTileVm> tiles;

  /// A tile that is a link was tapped; its `keyName`.
  final ValueChanged<String>? onTile;
  final double minWidth;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final n = ((box.maxWidth + _gap) / (minWidth + _gap)).floor().clamp(
        1,
        tiles.isEmpty ? 1 : tiles.length,
      );
      final width = (box.maxWidth - _gap * (n - 1)) / n;
      return Column(
        spacing: _gap,
        children: [
          for (var i = 0; i < tiles.length; i += n)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: .stretch,
                spacing: _gap,
                children: [
                  for (var j = i; j < i + n; j++)
                    Expanded(
                      child: j < tiles.length
                          ? SysTile(
                              vm: tiles[j],
                              relaxed: relaxed,
                              width: width,
                              onTap: tiles[j].link && onTile != null
                                  ? () => onTile!(tiles[j].keyName)
                                  : null,
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
