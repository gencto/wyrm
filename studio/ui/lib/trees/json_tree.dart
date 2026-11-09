import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What a [JsonNodeVm] holds; it picks the colour of its text.
enum JsonKind { object, array, string, number, flag, nil }

/// One node of a JSON value: a map or a list with its [children], or a
/// scalar with its [text] already written as JSON (`"on"`, `12.5`, `true`,
/// `null`).
final class JsonNodeVm extends Equatable {
  const JsonNodeVm({
    required this.kind,
    this.key,
    this.text = '',
    this.children = const [],
  });

  /// The key in its map, or null in a list and at the root.
  final String? key;
  final JsonKind kind;

  /// A scalar as JSON; a map or a list shows what [children] hold.
  final String text;
  final List<JsonNodeVm> children;

  bool get isContainer => kind == JsonKind.object || kind == JsonKind.array;

  @override
  List<Object?> get props => [key, kind, text, children];
}

/// A JSON value as a pretty tree: a chevron opens and closes each map and
/// list, keys and values in the syntax colours of the palette (keys plain,
/// strings teal, numbers ember, bools amber, `null` grey). A closed map
/// shows `{…}` and how many keys it has. Everything is open at first.
class JsonTree extends StatefulWidget {
  const JsonTree({required this.root, super.key});

  final JsonNodeVm root;

  @override
  State<JsonTree> createState() => _JsonTreeState();
}

class _JsonTreeState extends State<JsonTree> {
  /// Paths of the closed nodes (`0/2/name`).
  final _closed = <String>{};

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    _rows(context, widget.root, '', 0, rows);
    return SelectionArea(
      child: Column(crossAxisAlignment: .start, children: rows),
    );
  }

  void _rows(
    BuildContext context,
    JsonNodeVm n,
    String path,
    int depth,
    List<Widget> out,
  ) {
    final c = context.colors;
    final style = mono(size: 12, color: c.text1);
    final bracket = mono(size: 12, color: c.text4);
    final indent = 16.0 * depth;
    final key = n.key;
    final label = <InlineSpan>[
      if (key != null) ...[
        TextSpan(
          text: '"$key"',
          style: mono(size: 12, weight: .w500, color: c.text2),
        ),
        TextSpan(text: ': ', style: bracket),
      ],
    ];
    if (!n.isContainer) {
      out.add(
        Padding(
          padding: EdgeInsets.only(left: indent + 18, top: 1, bottom: 1),
          child: Text.rich(
            TextSpan(
              children: [
                ...label,
                TextSpan(
                  text: n.text,
                  style: mono(size: 12, color: _color(c, n.kind)),
                ),
              ],
            ),
            style: style,
          ),
        ),
      );
      return;
    }
    final open = !_closed.contains(path);
    final (start, end) = n.kind == JsonKind.object ? ('{', '}') : ('[', ']');
    final empty = n.children.isEmpty;
    out.add(
      InkWell(
        onTap: empty
            ? null
            : () => setState(() {
                if (!_closed.remove(path)) {
                  _closed.add(path);
                }
              }),
        child: Padding(
          padding: EdgeInsets.only(left: indent, top: 1, bottom: 1),
          child: Row(
            mainAxisSize: .min,
            children: [
              SizedBox(
                width: 18,
                child: empty
                    ? null
                    : AppIcon(
                        open ? 'ui_chevron_down' : 'ui_chevron_right',
                        size: 14,
                        color: c.text4,
                      ),
              ),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      ...label,
                      TextSpan(text: start, style: bracket),
                      if (empty)
                        TextSpan(text: end, style: bracket)
                      else if (!open) ...[
                        TextSpan(text: '…$end', style: bracket),
                        TextSpan(
                          text: '  ${n.text}',
                          style: mono(size: 11, color: c.text4),
                        ),
                      ],
                    ],
                  ),
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (empty || !open) {
      return;
    }
    for (final (i, ch) in n.children.indexed) {
      _rows(context, ch, '$path/${ch.key ?? i}', depth + 1, out);
    }
    out.add(
      Padding(
        padding: EdgeInsets.only(left: indent + 18, top: 1, bottom: 1),
        child: Text(end, style: bracket),
      ),
    );
  }

  static Color _color(AppColors c, JsonKind k) => switch (k) {
    JsonKind.string => c.good,
    JsonKind.number => c.emberSoft,
    JsonKind.flag => c.warn,
    JsonKind.nil => c.text4,
    JsonKind.object || JsonKind.array => c.text1,
  };
}
