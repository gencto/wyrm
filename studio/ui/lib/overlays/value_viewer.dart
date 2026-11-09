import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../buttons/button.dart';
import '../indicators/quality_mark.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import '../trees/json_tree.dart';
import 'floating_window.dart';

/// How the value of a [ValueViewerVm] is drawn, by its type.
sealed class ValueContentVm extends Equatable {
  const ValueContentVm();
}

/// A map or a list: a pretty tree.
final class JsonContentVm extends ValueContentVm {
  const JsonContentVm(this.root);

  final JsonNodeVm root;

  @override
  List<Object?> get props => [root];
}

/// A text: mono, wrapped, with line numbers.
final class TextContentVm extends ValueContentVm {
  const TextContentVm(this.lines);

  final List<String> lines;

  @override
  List<Object?> get props => [lines];
}

/// A number, already rounded for reading, with its unit.
final class NumberContentVm extends ValueContentVm {
  const NumberContentVm(this.number, {this.unit = ''});

  final String number;
  final String unit;

  @override
  List<Object?> get props => [number, unit];
}

/// A bool: a mark and its word (or the name a point gives it).
final class FlagContentVm extends ValueContentVm {
  const FlagContentVm({required this.value, required this.word});

  final bool value;
  final String word;

  @override
  List<Object?> get props => [value, word];
}

/// Binary data as a hex dump: rows of `offset  hex  text`.
final class BytesContentVm extends ValueContentVm {
  const BytesContentVm(this.rows);

  final List<String> rows;

  @override
  List<Object?> get props => [rows];
}

/// No value (yet), or `null`.
final class EmptyContentVm extends ValueContentVm {
  const EmptyContentVm(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// The value one viewer shows: whose it is ([title]: `concat1.out`, a
/// point key), its [type] and [size] (`map` · `3 keys`), how to draw it,
/// its quality when it is a sample, and the raw value as [copy] puts it on
/// the clipboard (JSON or the text itself).
final class ValueViewerVm extends Equatable {
  const ValueViewerVm({
    required this.title,
    required this.type,
    required this.content,
    required this.copy,
    this.size = '',
    this.quality,
  });

  final String title;
  final String type;
  final String size;
  final ValueContentVm content;
  final QualityMarkVm? quality;
  final String copy;

  @override
  List<Object?> get props => [title, type, size, content, quality, copy];
}

/// The floating window of a field's or a point's value (owner request
/// 2026-11-09): the title in mono with the type and size beside it, Copy,
/// close; the value styled by its type and redrawn as it changes. One is
/// open at a time; the page keeps it in a `Positioned.fill` of its stack.
class ValueViewer extends StatefulWidget {
  const ValueViewer({
    required this.vm,
    required this.onClose,
    this.copyLabel = 'Copy',
    this.copiedLabel = 'Copied',
    this.closeLabel = 'Close',
    super.key,
  });

  final ValueViewerVm vm;
  final VoidCallback onClose;
  final String copyLabel;
  final String copiedLabel;
  final String closeLabel;

  @override
  State<ValueViewer> createState() => _ValueViewerState();
}

class _ValueViewerState extends State<ValueViewer> {
  var _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.vm.copy)));
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    return FloatingWindow(
      onClose: widget.onClose,
      closeLabel: widget.closeLabel,
      header: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Row(
              spacing: 10,
              children: [
                Flexible(
                  child: Tooltip(
                    message: vm.title,
                    waitDuration: const Duration(milliseconds: 600),
                    child: LayoutBuilder(
                      // A key loses its start, not its name: `…/plc1/level`.
                      builder: (context, box) {
                        final style = mono(weight: .w600, color: c.text1);
                        return Text(
                          _fitStart(vm.title, style, box.maxWidth),
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: style,
                        );
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.ground4,
                    borderRadius: Radii.chip,
                  ),
                  child: Text(
                    [vm.type, if (vm.size.isNotEmpty) vm.size].join(' · '),
                    maxLines: 1,
                    style: mono(size: 11, color: c.text3),
                  ),
                ),
              ],
            ),
          ),
          Button.quiet(
            label: _copied ? widget.copiedLabel : widget.copyLabel,
            icon: _copied ? 'ui_check' : 'ui_copy',
            size: ButtonSize.small,
            onPressed: _copy,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                child: _body(context, vm.content),
              ),
            ),
          ),
          if (vm.quality case final q?)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: QualityMark(vm: q, size: 12),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ValueContentVm content) {
    final c = context.colors;
    return switch (content) {
      JsonContentVm(:final root) => JsonTree(root: root),
      TextContentVm(:final lines) => _Lines(lines: lines),
      NumberContentVm(:final number, :final unit) => SelectionArea(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: number,
                style: mono(size: 28, color: c.text1),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: '  $unit',
                  style: mono(size: 16, color: c.text3),
                ),
            ],
          ),
        ),
      ),
      FlagContentVm(:final value, :final word) => Row(
        spacing: 10,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: .circle,
              color: value ? c.good : null,
              border: .all(color: value ? c.good : c.text4, width: 1.6),
            ),
          ),
          Text(
            word,
            style: mono(size: 20, color: value ? c.good : c.text2),
          ),
        ],
      ),
      BytesContentVm(:final rows) => SelectionArea(
        child: Column(
          crossAxisAlignment: .start,
          children: [
            for (final r in rows)
              Text(r, style: mono(size: 12, color: c.text2)),
          ],
        ),
      ),
      EmptyContentVm(:final text) => Text(
        text,
        style: mono(size: 14, color: c.text4),
      ),
    };
  }
}

/// [text] as it fits in [width]: whole, or its last `/` segments after
/// `…/`.
String _fitStart(String text, TextStyle style, double width) {
  bool fits(String t) {
    final p = TextPainter(
      text: TextSpan(text: t, style: style),
      maxLines: 1,
      textDirection: .ltr,
    )..layout();
    final w = p.width;
    p.dispose();
    return w <= width;
  }

  if (fits(text)) {
    return text;
  }
  final parts = text.split('/');
  for (var i = 1; i < parts.length; i++) {
    final t = '…/${parts.sublist(i).join('/')}';
    if (fits(t)) {
      return t;
    }
  }
  return text;
}

/// Text lines, numbered in a gutter on the left, each wrapped to the
/// width.
class _Lines extends StatelessWidget {
  const _Lines({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gutter = 10.0 + 7.5 * '${lines.length}'.length;
    return SelectionArea(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final (i, l) in lines.indexed)
            Row(
              crossAxisAlignment: .start,
              spacing: 10,
              children: [
                SizedBox(
                  width: gutter,
                  child: SelectionContainer.disabled(
                    child: Text(
                      '${i + 1}',
                      textAlign: .right,
                      style: mono(size: 12, color: c.text4),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    l,
                    softWrap: true,
                    style: mono(size: 12, color: c.text1),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
