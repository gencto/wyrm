import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../dialogs/error_dialog.dart' show ErrorRowVm;
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What [StartFault] draws.
final class StartFaultVm extends Equatable {
  const StartFaultVm({
    required this.title,
    required this.body,
    required this.rows,
    required this.note,
    this.noteCode = '',
    this.fresh = 'Start with fresh settings',
    this.copy = 'Copy report',
    this.quit = 'Quit',
    this.failed,
    this.busy = false,
  });

  /// `Studio could not start`.
  final String title;

  /// Why, and that the brokers are not affected.
  final String body;

  /// `Error`, `File`, `Studio`.
  final List<ErrorRowVm> rows;

  /// The note on the kept file; [noteCode] inside it is drawn in mono
  /// (`settings.db.broken`).
  final String note;
  final String noteCode;
  final String fresh;
  final String copy;
  final String quit;

  /// Why *Start with fresh settings* did not work, in `bad` over the note.
  final String? failed;

  /// Fresh settings are being made: the buttons wait.
  final bool busy;

  @override
  List<Object?> get props => [
    title,
    body,
    rows,
    note,
    noteCode,
    fresh,
    copy,
    quit,
    failed,
    busy,
  ];
}

/// The start screen for when Studio cannot open its own settings (board
/// `ErrorFatal`, docs/design/specs/errors.md §6): the mark with its head
/// in `bad`, what happened, a box of details, and three ways on. It is the
/// whole window, before log-in; no other condition shows it.
class StartFault extends StatelessWidget {
  const StartFault({
    required this.vm,
    required this.onFresh,
    required this.onCopy,
    required this.onQuit,
    super.key,
  });

  final StartFaultVm vm;
  final VoidCallback onFresh;
  final VoidCallback onCopy;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (before, after) = switch (vm.note.indexOf(vm.noteCode)) {
      final i when i >= 0 && vm.noteCode.isNotEmpty => (
        vm.note.substring(0, i),
        vm.note.substring(i + vm.noteCode.length),
      ),
      _ => (vm.note, ''),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ground0,
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.6,
          colors: [c.ground1.withValues(alpha: 0.9), c.ground0],
          stops: const [0, 0.7],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                spacing: 20,
                children: [
                  Opacity(
                    opacity: 0.85,
                    child: CustomPaint(
                      size: const Size(88, 52),
                      painter: _BrokenMark(
                        spine: c.line3,
                        ring: c.muted,
                        head: c.bad,
                        fill: c.badTint,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: .start,
                    spacing: 8,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          vm.title,
                          style: boardText(
                            size: 28,
                            weight: .w600,
                            tracking: -0.28,
                            color: c.text1,
                          ),
                        ),
                      ),
                      Text(
                        vm.body,
                        style: boardText(size: 15, height: 1.6, color: c.text2),
                      ),
                    ],
                  ),
                  Container(
                    width: .infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: c.ground1,
                      border: .all(color: c.line1),
                      borderRadius: Radii.card,
                    ),
                    child: Table(
                      columnWidths: const {
                        0: IntrinsicColumnWidth(),
                        1: FlexColumnWidth(),
                      },
                      children: [
                        for (final (i, r) in vm.rows.indexed)
                          TableRow(
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  right: 16,
                                  top: i == 0 ? 0 : 6,
                                ),
                                child: Text(
                                  r.label,
                                  style: boardText(size: 12, color: c.text4),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                                child: SelectableText(
                                  r.value,
                                  style: boardText(
                                    size: 12,
                                    color: c.text2,
                                    code: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      Button.primary(
                        key: const ValueKey('start-fresh'),
                        label: vm.fresh,
                        size: .commit,
                        inset: 18,
                        autofocus: true,
                        onPressed: vm.busy ? null : onFresh,
                      ),
                      Button.secondary(
                        key: const ValueKey('start-copy'),
                        label: vm.copy,
                        size: .commit,
                        fontWeight: .w400,
                        onPressed: onCopy,
                      ),
                      InkWell(
                        key: const ValueKey('start-quit'),
                        onTap: onQuit,
                        borderRadius: Radii.button,
                        child: SizedBox(
                          height: 44,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                vm.quit,
                                style: boardText(color: c.text3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (vm.failed case final f?)
                    Text(
                      f,
                      style: boardText(size: 12, height: 1.5, color: c.badText),
                    ),
                  Text.rich(
                    TextSpan(
                      text: before,
                      children: [
                        if (after.isNotEmpty || before != vm.note) ...[
                          TextSpan(
                            text: vm.noteCode,
                            style: boardText(
                              size: 12,
                              height: 1.5,
                              color: c.text4,
                              code: true,
                            ),
                          ),
                          TextSpan(text: after),
                        ],
                      ],
                    ),
                    style: boardText(size: 12, height: 1.5, color: c.text4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The WYRM mark that did not wake: a dashed spine, four empty rings and
/// the head in `bad` (viewBox 220 × 130, drawn at any size).
class _BrokenMark extends CustomPainter {
  const _BrokenMark({
    required this.spine,
    required this.ring,
    required this.head,
    required this.fill,
  });

  final Color spine;
  final Color ring;
  final Color head;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 220, size.height / 130);
    // `M20 85 Q 42 60 65 45 T 115 30 T 165 55 T 200 100`, dashes 2 / 14.
    final path = Path()
      ..moveTo(20, 85)
      ..quadraticBezierTo(42, 60, 65, 45)
      ..quadraticBezierTo(88, 30, 115, 30)
      ..quadraticBezierTo(142, 30, 165, 55)
      ..quadraticBezierTo(188, 80, 200, 100);
    final dash = Paint()
      ..color = spine
      ..style = .stroke
      ..strokeWidth = 6
      ..strokeCap = .round;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 16) {
        canvas.drawPath(m.extractPath(d, (d + 2).clamp(0, m.length)), dash);
      }
    }
    final stroke = Paint()
      ..style = .stroke
      ..strokeWidth = 6;
    void circle(double x, double y, double r, {bool isHead = false}) {
      if (isHead) {
        canvas.drawCircle(Offset(x, y), r, Paint()..color = fill);
      }
      canvas.drawCircle(
        Offset(x, y),
        r,
        stroke..color = isHead ? head : ring,
      );
    }

    circle(20, 85, 12);
    circle(65, 45, 14);
    circle(115, 30, 18, isHead: true);
    circle(165, 55, 14);
    circle(200, 100, 12);
  }

  @override
  bool shouldRepaint(_BrokenMark old) =>
      spine != old.spine ||
      ring != old.ring ||
      head != old.head ||
      fill != old.fill;
}
