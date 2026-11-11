import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'app_icon.dart';

/// The full key of the node on screen in mono 13, its last segment in
/// text/1, and a 28 × 28 Copy key button (docs/design/specs/explorer.md
/// §3.1).
///
/// A segment whose key (the path up to and with it) is in [links] is a
/// link: a pointer cursor, an underline on hover and on keyboard focus,
/// Enter or Space or a click calls [onOpen] with that key. The last segment
/// is the node on screen and never a link.
class KeyLine extends StatelessWidget {
  const KeyLine({
    required this.keyName,
    this.onCopy,
    this.copyLabel = 'Copy key',
    this.links = const {},
    this.onOpen,
    super.key,
  });

  /// `wy/<site>/downstream/…`.
  final String keyName;
  final VoidCallback? onCopy;
  final String copyLabel;

  /// The keys of the segments that open a node (`wy/plant/downstream`,
  /// `wy/plant/downstream/s7`, …).
  final Set<String> links;

  /// A link segment was activated; its key.
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parts = keyName.split('/');
    final spans = <InlineSpan>[];
    final plain = StringBuffer();
    void flush() {
      if (plain.isNotEmpty) {
        spans.add(TextSpan(text: plain.toString()));
        plain.clear();
      }
    }

    for (var i = 0; i < parts.length; i++) {
      final last = i == parts.length - 1;
      final key = parts.sublist(0, i + 1).join('/');
      if (last) {
        flush();
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextStyle(color: c.text1),
          ),
        );
      } else if (onOpen != null && links.contains(key)) {
        flush();
        spans.add(
          WidgetSpan(
            alignment: .baseline,
            baseline: .alphabetic,
            child: _Crumb(
              key: ValueKey('crumb:$key'),
              label: parts[i],
              onTap: () => onOpen!(key),
            ),
          ),
        );
        plain.write('/');
      } else {
        plain.write('${parts[i]}/');
      }
    }
    flush();
    return Row(
      spacing: 8,
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(children: spans),
            maxLines: 1,
            overflow: .ellipsis,
            style: mono(color: c.text4),
          ),
        ),
        if (onCopy != null)
          Tooltip(
            message: copyLabel,
            child: InkWell(
              onTap: onCopy,
              borderRadius: Radii.segment,
              child: SizedBox.square(
                dimension: 28,
                child: Center(
                  child: AppIcon('ui_copy', size: 14, color: c.text4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One link segment of a [KeyLine].
class _Crumb extends StatefulWidget {
  const _Crumb({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  var _hover = false;
  var _focus = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lit = _hover || _focus;
    return Semantics(
      link: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: .opaque,
            onTap: widget.onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _focus ? c.ground4 : null,
                borderRadius: Radii.chip,
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                style: mono(color: lit ? c.text1 : c.text4).copyWith(
                  decoration: lit ? TextDecoration.underline : null,
                  decorationColor: c.text2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
