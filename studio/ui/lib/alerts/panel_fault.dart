import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/fault_boundary.dart';
import '../indicators/app_icon.dart';
import '../theme/common.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What [PanelFault] draws.
final class PanelFaultVm extends Equatable {
  const PanelFaultVm({
    required this.title,
    required this.body,
    required this.line,
    this.drawAgain = 'Draw it again',
    this.copy = 'Copy report',
  });

  /// `The inspector could not be drawn`.
  final String title;

  /// `The rest of Studio still works; …`
  final String body;

  /// The error's first line, the panel and the time, in mono.
  final String line;
  final String drawAgain;
  final String copy;

  @override
  List<Object?> get props => [title, body, line, drawAgain, copy];
}

/// The card that takes the place of a part of the screen that threw while
/// it was built (board `ErrorPanel`, docs/design/specs/errors.md §5): a
/// dashed `badLine` card in `ground2` with the tone square, what could not
/// be drawn, one sentence, the error's first line, *Draw it again* and
/// *Copy report*. Everything else on the screen keeps working.
///
/// In a box too small for the card (a cell, an icon) it is the tone square
/// alone.
class PanelFault extends StatelessWidget {
  const PanelFault({
    required this.vm,
    this.onDrawAgain,
    this.onCopy,
    super.key,
  });

  final PanelFaultVm vm;

  /// Null when there is no boundary to draw again: the button is not shown.
  final VoidCallback? onDrawAgain;
  final VoidCallback? onCopy;

  /// The first line of a thrown object as the card shows it. The app sets
  /// one that masks what looks like a secret.
  static String Function(Object error) describe = _firstLine;

  /// *Copy report* of a card built by [builder]: the app puts the report on
  /// the clipboard. The second argument is the boundary's name, or null.
  static void Function(FlutterErrorDetails details, String? panel)? copyReport;

  static String _firstLine(Object error) {
    final first = '$error'.split('\n').first.trim();
    return first.length > 160 ? '${first.substring(0, 160)}…' : first;
  }

  /// For `ErrorWidget.builder`: the card for [details], named by the
  /// nearest [FaultBoundary] of the place it is built in.
  static Widget builder(FlutterErrorDetails details) =>
      _FaultHost(details: details);

  @override
  Widget build(BuildContext context) {
    // Whatever threw may sit above the theme: the card must draw anywhere.
    final c =
        Theme.of(context).extension<AppColors>() ??
        darkTheme().extension<AppColors>()!;
    return LayoutBuilder(
      builder: (context, box) {
        final small =
            (box.hasBoundedWidth && box.maxWidth < 200) ||
            (box.hasBoundedHeight && box.maxHeight < 150);
        if (small) {
          return Center(
            child: FittedBox(
              fit: .scaleDown,
              child: _square(c, 28, 14),
            ),
          );
        }
        final card = Container(
          padding: const EdgeInsets.all(20),
          decoration: ShapeDecoration(
            color: c.ground2,
            shape: _DashedBorder(color: c.badLine),
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            spacing: 12,
            children: [
              _square(c, 36, 18),
              Text(
                vm.title,
                style: boardText(size: 16, weight: .w600, color: c.text1),
              ),
              Text(
                vm.body,
                style: boardText(size: 13, height: 1.55, color: c.text3),
              ),
              Container(
                width: .infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.ground0,
                  borderRadius: const .all(.circular(6)),
                ),
                child: Text(
                  vm.line,
                  style: boardText(size: 11, color: c.text4, code: true),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onDrawAgain case final f?)
                    Button.primary(
                      key: const ValueKey('fault-draw-again'),
                      label: vm.drawAgain,
                      size: .compact,
                      fontSize: 13,
                      inset: 14,
                      onPressed: f,
                    ),
                  Button.secondary(
                    key: const ValueKey('fault-copy'),
                    label: vm.copy,
                    size: .compact,
                    fontSize: 13,
                    fontWeight: .w400,
                    inset: 14,
                    onPressed: onCopy,
                  ),
                ],
              ),
            ],
          ),
        );
        final sized = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: card,
        );
        return Semantics(
          container: true,
          liveRegion: true,
          child: box.hasBoundedHeight
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Align(alignment: .topCenter, child: sized),
                )
              : Padding(padding: const EdgeInsets.all(20), child: sized),
        );
      },
    );
  }

  Widget _square(AppColors c, double size, double icon) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: c.badTint,
      borderRadius: const .all(.circular(10)),
    ),
    alignment: .center,
    child: AppIcon('err_studio', size: icon, color: c.bad),
  );
}

/// Builds the card where something threw: finds the boundary, keeps the
/// time of the fault, and brings what the card needs above it when the
/// fault is above the app's own (a text direction, a theme).
class _FaultHost extends StatefulWidget {
  const _FaultHost({required this.details});

  final FlutterErrorDetails details;

  @override
  State<_FaultHost> createState() => _FaultHostState();
}

class _FaultHostState extends State<_FaultHost> {
  final _at = DateTime.now();

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// The app's words, or English when no locale is loaded yet (a fault
  /// above the app).
  static T _words<T>(T Function(S s) words, T Function() english) {
    try {
      return words(S.current);
    } on Object {
      return english();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = FaultBoundary.maybeOf(context);
    final panel = switch (scope?.panel) {
      null => null,
      .tree => _words((s) => s.panelTree, () => 'tree'),
      .inspector => _words((s) => s.panelInspector, () => 'inspector'),
      .canvas => _words((s) => s.panelCanvas, () => 'editor canvas'),
      .drawer => _words((s) => s.panelDrawer, () => 'drawer'),
      .workspace => _words((s) => s.panelWorkspace, () => 'workspace'),
    };
    final time = '${_two(_at.hour)}:${_two(_at.minute)}:${_two(_at.second)}';
    final card = PanelFault(
      vm: PanelFaultVm(
        title: panel == null
            ? _words(
                (s) => s.faultTitleThis,
                () => 'This part could not be drawn',
              )
            : _words(
                (s) => s.faultTitle(panel),
                () => 'The $panel could not be drawn',
              ),
        body: _words(
          (s) => s.faultBody,
          () =>
              'The rest of Studio still works; values and actions elsewhere '
              'are not affected.',
        ),
        line: [
          PanelFault.describe(widget.details.exception),
          ?panel,
          time,
        ].join(' · '),
        drawAgain: _words((s) => s.faultDrawAgain, () => 'Draw it again'),
        copy: _words((s) => s.errCopyReport, () => 'Copy report'),
      ),
      onDrawAgain: scope?.redraw,
      onCopy: () => PanelFault.copyReport?.call(widget.details, panel),
    );
    Widget out = card;
    if (Theme.of(context).extension<AppColors>() == null) {
      out = Theme(data: darkTheme(), child: out);
    }
    if (context.findAncestorWidgetOfExactType<Material>() == null) {
      out = Material(type: .transparency, child: out);
    }
    if (Directionality.maybeOf(context) == null) {
      out = Directionality(textDirection: .ltr, child: out);
    }
    return out;
  }
}

/// A rounded rectangle (radius 12) with a dashed outline, 1 px.
class _DashedBorder extends ShapeBorder {
  const _DashedBorder({required this.color});

  final Color color;

  static const _radius = Radius.circular(12);

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(1);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect.deflate(1), _radius));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, _radius));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect.deflate(0.5), _radius));
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, (d + 3).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  ShapeBorder scale(double t) => this;
}
