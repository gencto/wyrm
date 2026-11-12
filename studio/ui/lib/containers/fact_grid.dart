import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One fact of an inspector.
final class FactVm extends Equatable {
  const FactVm({
    required this.label,
    required this.value,
    this.mono = false,
    this.code,
  });

  final String label;
  final String value;

  /// The name behind [label] when the label says it in other words
  /// (`poll_s` under `Poll (s)`): the label's tooltip.
  final String? code;

  /// Keys, addresses, hashes: in mono.
  final bool mono;

  @override
  List<Object?> get props => [label, value, mono, code];
}

/// Label/value pairs in two columns.
class FactGrid extends StatelessWidget {
  const FactGrid({required this.facts, this.labelWidth = 120, super.key});

  final List<FactVm> facts;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        for (final f in facts)
          Row(
            crossAxisAlignment: .start,
            children: [
              SizedBox(
                width: labelWidth,
                child: switch (f.code) {
                  final code? when code != f.label => Tooltip(
                    message: code,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(
                      f.label,
                      style: TextStyle(fontSize: 13, color: c.text4),
                    ),
                  ),
                  _ => Text(
                    f.label,
                    style: TextStyle(fontSize: 13, color: c.text4),
                  ),
                },
              ),
              Expanded(
                child: SelectableText(
                  f.value,
                  style: f.mono
                      ? mono(color: c.text1)
                      : TextStyle(fontSize: 13, color: c.text1),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
