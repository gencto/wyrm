import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// The tone of an error surface (docs/design/specs/errors.md §1): the
/// colour of its mark and the ground under it. `neutral` is the grey of
/// *busy* and *gone* (`text3` on `ground4`).
(Color, Color) errorTone(AppColors c, Tone tone) => switch (tone) {
  .warn => (c.warn, c.warnTint),
  .ember => (c.emberSoft, c.emberTint),
  .bad => (c.bad, c.badTint),
  .good => (c.good, c.goodTint),
  .neutral => (c.text3, c.ground4),
};

/// One row of Details: `Status` · `permission_denied (0x21)`.
final class ErrorRowVm extends Equatable {
  const ErrorRowVm(this.label, this.value);

  final String label;
  final String value;

  @override
  List<Object?> get props => [label, value];
}

/// What [ErrorDialog] draws: one failure, in words already chosen.
///
/// The buttons' handlers are parameters of the widget, not fields here: a
/// closure built on every `fromStore` would make two equal dialogs compare
/// unequal.
final class ErrorDialogVm extends Equatable {
  const ErrorDialogVm({
    required this.tone,
    required this.icon,
    required this.title,
    required this.saidLabel,
    required this.said,
    required this.primary,
    this.where = '',
    this.adviceLabel = 'What you can do',
    this.advice = const [],
    this.note,
    this.detailsLabel = 'Details',
    this.chip = '',
    this.details = const [],
    this.detailsOpen = false,
    this.copy = 'Copy details',
    this.secondary,
    this.countdown,
    this.countdownLabel,
    this.close = 'Close',
  });

  /// The kind's tone: the icon square, the dots, the status chip.
  final Tone tone;

  /// An icon of `ui/assets/svg/icons` (`err_rights`, `err_reach`, …).
  final String icon;

  /// What did not happen: `You can’t deploy pump-control`.
  final String title;

  /// The key and the call, in mono under the title:
  /// `wy/plant/dataflows/pump-control › deploy`.
  final String where;

  /// `The broker said`, `Studio waited 10 s`, `What happened`.
  final String saidLabel;

  /// The broker's message as it came, selectable.
  final String said;
  final String adviceLabel;

  /// One or two lines of what the user can do.
  final List<String> advice;

  /// The amber note of a write that timed out; null for none.
  final String? note;
  final String detailsLabel;

  /// The status name beside *Details* (`permission_denied`).
  final String chip;
  final List<ErrorRowVm> details;

  /// Details start open (`broker`, `studio`).
  final bool detailsOpen;

  /// `Copy details`, or `Copy report` for a fault in Studio.
  final String copy;

  /// The outlined button's label; null for none.
  final String? secondary;

  /// The main button's label (`OK`, `Try again`, `Refresh`).
  final String primary;

  /// Seconds the main button waits, disabled, before it presses itself
  /// (`busy`); null for a button that is enabled at once.
  final int? countdown;

  /// The main button's label while it counts (`Try again in 4 s`).
  /// Behaviour of the text, so out of [props].
  final String Function(int seconds)? countdownLabel;

  /// The close button's name for a screen reader.
  final String close;

  @override
  List<Object?> get props => [
    tone,
    icon,
    title,
    where,
    saidLabel,
    said,
    adviceLabel,
    advice,
    note,
    detailsLabel,
    chip,
    details,
    detailsOpen,
    copy,
    secondary,
    primary,
    countdown,
    close,
  ];
}

/// The error dialog (boards `ErrorDialog`, `Err*`,
/// docs/design/specs/errors.md §3): a card of at most 520 with the kind's
/// icon, the title, key › call, the broker's message, what the user can do,
/// Details and the buttons.
///
/// Keys: the main button has the focus, so Enter presses it; Esc is
/// [onClose]; Cmd/Ctrl+C copies the details unless text is selected in the
/// message (then it copies that); Tab stays inside the route.
class ErrorDialog extends StatefulWidget {
  const ErrorDialog({
    required this.vm,
    required this.onPrimary,
    required this.onClose,
    this.onSecondary,
    this.onCopy,
    super.key,
  });

  final ErrorDialogVm vm;

  /// The main button, and what the countdown does when it ends.
  final VoidCallback onPrimary;

  /// The close button and Esc.
  final VoidCallback onClose;
  final VoidCallback? onSecondary;

  /// *Copy details* / *Copy report*.
  final VoidCallback? onCopy;

  /// The scrim of the board: `rgba(6, 8, 9, 0.66)` over the whole window.
  static const scrim = Color(0xA8060809);

  /// Shows [dialog] over [context]'s navigator on the board's scrim. A tap
  /// on the scrim does nothing: the dialog closes by its buttons and Esc,
  /// so the choice is always one the user made.
  static Future<T?> show<T>(BuildContext context, WidgetBuilder dialog) =>
      showGeneralDialog<T>(
        context: context,
        barrierColor: scrim,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        transitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (context, _, _) => dialog(context),
        transitionBuilder: (context, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      );

  @override
  State<ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<ErrorDialog> {
  late bool _open = widget.vm.detailsOpen;
  late int _left = widget.vm.countdown ?? 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (_left > 0) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _left--);
        if (_left <= 0) {
          _tick?.cancel();
          widget.onPrimary();
        }
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final c = context.colors;
    final (fg, bg) = errorTone(c, vm.tone);
    final counting = _left > 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        if (!counting) ...{
          const SingleActivator(LogicalKeyboardKey.enter): widget.onPrimary,
          const SingleActivator(LogicalKeyboardKey.numpadEnter):
              widget.onPrimary,
        },
        if (widget.onCopy case final copy?) ...{
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): copy,
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): copy,
        },
      },
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              // The board's 520 is the content box: the 1 px line is
              // outside it.
              constraints: const BoxConstraints(maxWidth: 522),
              child: Semantics(
                role: .alertDialog,
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: vm.title,
                child: Material(
                  type: .transparency,
                  child: FocusTraversalGroup(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.ground2,
                        border: .all(color: c.line2),
                        borderRadius: const .all(.circular(14)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x8C000000),
                            offset: Offset(0, 24),
                            blurRadius: 64,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: .min,
                        crossAxisAlignment: .stretch,
                        children: [
                          _header(c, vm, fg, bg),
                          _body(c, vm, fg, bg),
                          _footer(c, vm, counting),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppColors c, ErrorDialogVm vm, Color fg, Color bg) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
    child: Row(
      crossAxisAlignment: .start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const .all(.circular(10)),
          ),
          alignment: .center,
          child: AppIcon(vm.icon, color: fg),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              Semantics(
                header: true,
                child: Text(
                  vm.title,
                  style: boardText(
                    size: 18,
                    height: 1.35,
                    weight: .w600,
                    color: c.text1,
                  ),
                ),
              ),
              if (vm.where.isNotEmpty)
                SelectableText(
                  vm.where,
                  style: boardText(size: 12, color: c.text4, code: true),
                ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(8, -4),
          child: Tooltip(
            message: vm.close,
            child: Semantics(
              button: true,
              label: vm.close,
              child: InkWell(
                key: const ValueKey('error-close'),
                onTap: widget.onClose,
                borderRadius: Radii.button,
                canRequestFocus: false,
                child: SizedBox.square(
                  dimension: 32,
                  child: Center(
                    child: AppIcon('err_close', size: 16, color: c.text4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _body(AppColors c, ErrorDialogVm vm, Color fg, Color bg) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
    child: Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Column(
          crossAxisAlignment: .stretch,
          spacing: 6,
          children: [
            Text(vm.saidLabel, style: boardText(size: 12, color: c.text4)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.ground0,
                border: .all(color: c.ground4),
                borderRadius: Radii.control,
              ),
              child: SelectableText(
                vm.said,
                style: boardText(height: 1.55, color: c.text1),
              ),
            ),
          ],
        ),
        if (vm.advice.isNotEmpty)
          Column(
            crossAxisAlignment: .stretch,
            spacing: 6,
            children: [
              Text(
                vm.adviceLabel.toUpperCase(),
                style: boardText(
                  size: 12,
                  weight: .w600,
                  tracking: 0.72,
                  color: c.text4,
                ),
              ),
              for (final line in vm.advice)
                Row(
                  crossAxisAlignment: .start,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 9, right: 10),
                      decoration: BoxDecoration(color: fg, shape: .circle),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: boardText(height: 1.5, color: c.text2),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        if (vm.note case final note?)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.warnTint,
              border: .all(color: c.warnLine),
              borderRadius: Radii.control,
            ),
            child: Row(
              crossAxisAlignment: .start,
              spacing: 10,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: AppIcon('err_warn', size: 16, color: c.warn),
                ),
                Expanded(
                  child: Text(
                    note,
                    style: boardText(size: 13, height: 1.5, color: c.warn),
                  ),
                ),
              ],
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.ground4)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Semantics(
                  button: true,
                  expanded: _open,
                  child: InkWell(
                    key: const ValueKey('error-details'),
                    onTap: () => setState(() => _open = !_open),
                    borderRadius: Radii.segment,
                    child: SizedBox(
                      height: 36,
                      child: Row(
                        mainAxisSize: .min,
                        spacing: 8,
                        children: [
                          RotatedBox(
                            quarterTurns: _open ? 1 : 0,
                            child: AppIcon(
                              'err_chevron',
                              size: 14,
                              color: c.text3,
                            ),
                          ),
                          Text(
                            vm.detailsLabel,
                            style: boardText(size: 13, color: c.text3),
                          ),
                          if (vm.chip.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: Radii.chip,
                              ),
                              child: Text(
                                vm.chip,
                                style: boardText(
                                  size: 11,
                                  color: fg,
                                  code: true,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 0, 6),
                    child: Table(
                      columnWidths: const {
                        0: IntrinsicColumnWidth(),
                        1: FlexColumnWidth(),
                      },
                      children: [
                        for (final (i, r) in vm.details.indexed)
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
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _footer(AppColors c, ErrorDialogVm vm, bool counting) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
    child: Wrap(
      alignment: .spaceBetween,
      crossAxisAlignment: .center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Semantics(
          button: true,
          child: InkWell(
            key: const ValueKey('error-copy'),
            onTap: widget.onCopy,
            borderRadius: Radii.button,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  AppIcon('err_copy', size: 14, color: c.text3),
                  Text(
                    vm.copy,
                    style: boardText(size: 13, color: c.text3),
                  ),
                ],
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: .min,
          spacing: 8,
          children: [
            if (vm.secondary case final label?)
              Button.secondary(
                key: const ValueKey('error-secondary'),
                label: label,
                fontWeight: .w400,
                onPressed: widget.onSecondary ?? widget.onClose,
              ),
            if (counting)
              // Disabled while it counts (`ground4` / `text4`); the label is
              // the countdown itself.
              Semantics(
                button: true,
                enabled: false,
                liveRegion: true,
                child: Container(
                  key: const ValueKey('error-primary'),
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: c.ground4,
                    borderRadius: Radii.button,
                  ),
                  alignment: .center,
                  child: Text(
                    vm.countdownLabel?.call(_left) ?? vm.primary,
                    style: boardText(weight: .w600, color: c.text4),
                  ),
                ),
              )
            else
              Button.primary(
                key: const ValueKey('error-primary'),
                label: vm.primary,
                inset: 18,
                autofocus: true,
                onPressed: widget.onPrimary,
              ),
          ],
        ),
      ],
    ),
  );
}
