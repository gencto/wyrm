import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'quality_mark.dart';

/// The result of one check.
enum CheckResult { ok, failed, skipped }

/// One check of a package: a title, its result, a mono detail.
final class CheckRowVm extends Equatable {
  const CheckRowVm({
    required this.title,
    required this.result,
    this.detail = '',
  });

  final String title;
  final CheckResult result;
  final String detail;

  @override
  List<Object?> get props => [title, result, detail];
}

/// The archive checks of a custom package (Add a link › Check).
class CheckList extends StatelessWidget {
  const CheckList({required this.rows, super.key});

  final List<CheckRowVm> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c.line1),
        borderRadius: BorderRadius.circular(10),
        color: c.ground2,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.line1)),
              ),
              child: Row(
                crossAxisAlignment: .start,
                spacing: 10,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: StateMark(
                      mark: switch (rows[i].result) {
                        .ok => Mark.check,
                        .failed => Mark.cross,
                        .skipped => Mark.dashed,
                      },
                      color: switch (rows[i].result) {
                        .ok => c.good,
                        .failed => c.bad,
                        .skipped => c.muted,
                      },
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        Text(
                          rows[i].title,
                          style: TextStyle(fontSize: 13, color: c.text1),
                        ),
                        if (rows[i].detail.isNotEmpty)
                          Text(
                            rows[i].detail,
                            style: mono(
                              size: 12,
                              color: rows[i].result == .failed
                                  ? c.badText
                                  : c.text3,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
