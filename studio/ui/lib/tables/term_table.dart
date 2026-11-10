import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/code_text.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// One row of [TermTable]: a term and what it means.
final class TermVm extends Equatable {
  const TermVm({required this.term, required this.text});

  final String term;
  final String text;

  @override
  List<Object?> get props => [term, text];
}

/// A boxed list of terms with their explanations (board `SystemAvail`,
/// *What the standby holds*).
class TermTable extends StatelessWidget {
  const TermTable({required this.rows, super.key});

  final List<TermVm> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final first = (box.maxWidth * 0.3).clamp(150.0, 220.0);
          return Column(
            children: [
              for (final (i, r) in rows.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: c.ground3)),
                  ),
                  child: Row(
                    crossAxisAlignment: .start,
                    spacing: 16,
                    children: [
                      SizedBox(
                        width: first,
                        child: Text(
                          r.term,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: .w600,
                            color: c.text1,
                          ),
                        ),
                      ),
                      Expanded(
                        child: CodeText(
                          r.text,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: c.text3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
