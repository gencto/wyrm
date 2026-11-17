import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../dialogs/error_dialog.dart' show errorTone;
import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/shades.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'system_toast.dart';

/// One toast: a quiet failure, or something that went well (`good`).
///
/// [id] is what the composer gets back in its callbacks; the handlers are
/// the stack's, one for all toasts.
final class ToastVm extends Equatable {
  const ToastVm({
    required this.id,
    required this._title,
    this.tone = Tone.warn,
    this._line = '',
    this.details = false,
    this.retry = false,
    this.seconds = 8,
    this.stays,
  }) : words = null;

  /// A toast of System, worded here from [words], in `good`, gone after
  /// 3 s.
  const ToastVm.system({
    required this.id,
    required SysToastVm this.words,
  }) : _title = '',
       _line = '',
       tone = Tone.good,
       details = false,
       retry = false,
       seconds = 3,
       stays = null;

  /// Something was copied (`Key copied`, `3 keys copied`): a toast in
  /// `good` for 3 s.
  factory ToastVm.copied(int id, Copied what, {int count = 1}) => ToastVm(
    id: id,
    tone: Tone.good,
    seconds: 3,
    title: switch (what) {
      Copied.key => S.current.keyCopied,
      Copied.keys => S.current.keysCopied(count),
      Copied.value => S.current.valueCopied,
    },
  );

  final int id;
  final String _title;
  final String _line;

  /// What a toast of System says, typed (worded by [title] and [line]).
  final SysToastVm? words;

  String get title => words?.title ?? _title;

  /// The tone of the mark: `warn`, `bad`, `neutral`, or `good` for a
  /// success.
  final Tone tone;

  /// One line under the title: `timeout: the device did not answer.`
  String get line => words?.line ?? _line;

  /// It has a *Details* link (a failure does, a success does not).
  final bool details;

  /// It has a *Try again* link.
  final bool retry;

  /// How long it stays; ignored when [stays] is set.
  final int seconds;

  /// A toast that does not hide by itself says why (`stays until edge is
  /// back`): a stream that is down. Its border is the tone's line.
  final String? stays;

  @override
  List<Object?> get props => [
    id,
    _title,
    tone,
    _line,
    words,
    details,
    retry,
    seconds,
    stays,
  ];
}

/// What a copy toast says was copied.
enum Copied { key, keys, value }

/// The toasts of quiet failures and of successes (boards `ErrorQuiet`,
/// docs/design/specs/errors.md §4): 380 wide, the newest at the bottom, at
/// most [max] at once (older ones wait in Problems, behind the counter).
/// The composer places it (bottom right, 20 from the edges).
///
/// A toast counts its own seconds and reports [onExpire] when they are up;
/// one that [ToastVm.stays] does not count.
class ToastStack extends StatelessWidget {
  const ToastStack({
    required this.toasts,
    required this.onDismiss,
    this.onExpire,
    this.onDetails,
    this.onRetry,
    super.key,
  });

  /// Oldest first.
  final List<ToastVm> toasts;
  final ValueChanged<int> onDismiss;

  /// The toast's time is up; [onDismiss] when null.
  final ValueChanged<int>? onExpire;
  final ValueChanged<int>? onDetails;
  final ValueChanged<int>? onRetry;

  /// How many are drawn at once.
  static const max = 3;

  /// The width of a toast.
  static const width = 380.0;

  @override
  Widget build(BuildContext context) {
    final shown = toasts.length > max
        ? toasts.sublist(toasts.length - max)
        : toasts;
    if (shown.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      container: true,
      liveRegion: true,
      label: S.current.toastNotifications,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: width),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 10,
          children: [
            for (final t in shown)
              _Toast(
                key: ValueKey(t.id),
                vm: t,
                onDismiss: () => onDismiss(t.id),
                onExpire: () => (onExpire ?? onDismiss)(t.id),
                onDetails: onDetails == null ? null : () => onDetails!(t.id),
                onRetry: onRetry == null ? null : () => onRetry!(t.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// One toast of the stack, with its own clock.
class _Toast extends StatefulWidget {
  const _Toast({
    required this.vm,
    required this.onDismiss,
    required this.onExpire,
    required this.onDetails,
    required this.onRetry,
    super.key,
  });

  final ToastVm vm;
  final VoidCallback onDismiss;
  final VoidCallback onExpire;
  final VoidCallback? onDetails;
  final VoidCallback? onRetry;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  late int _left = widget.vm.seconds;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_Toast old) {
    super.didUpdateWidget(old);
    // The stream came back or went down: the clock follows.
    if ((old.vm.stays == null) != (widget.vm.stays == null)) {
      _left = widget.vm.seconds;
      _arm();
    }
  }

  void _arm() {
    _tick?.cancel();
    _tick = null;
    if (widget.vm.stays != null) {
      return;
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        _tick?.cancel();
        widget.onExpire();
        return;
      }
      setState(() => _left--);
    });
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
    final line = switch (vm.tone) {
      .warn => c.warnLine,
      .bad => c.badLine,
      .good => c.goodLine,
      .ember => c.emberLine,
      .neutral => c.line3,
    };
    Widget link(String label, VoidCallback onTap, Key key) => InkWell(
      key: key,
      onTap: onTap,
      child: Text(
        label,
        style: boardText(size: FontSizes.sm, color: c.emberSoft).copyWith(
          decoration: .underline,
          decorationColor: c.emberSoft,
        ),
      ),
    );
    return Semantics(
      container: true,
      child: Material(
        type: .transparency,
        child: Container(
          padding: Insets.cardBody,
          decoration: BoxDecoration(
            color: c.ground3,
            border: .all(color: vm.stays == null ? c.line2 : line),
            borderRadius: Radii.card,
            boxShadow: const [
              BoxShadow(
                color: Shades.popupShadow,
                offset: Offset(0, 12),
                blurRadius: 32,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: .start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: Radii.button,
                ),
                alignment: .center,
                child: AppIconView(
                  vm.tone == .good ? AppIcon.errOk : AppIcon.errMark,
                  size: IconSizes.sm,
                  color: fg,
                ),
              ),
              Gaps.hToastParts,
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 4,
                  children: [
                    Text(
                      vm.title,
                      style: boardText(
                        size: FontSizes.md,
                        weight: .w600,
                        color: c.text1,
                      ),
                    ),
                    if (vm.line.isNotEmpty)
                      Text(
                        vm.line,
                        maxLines: 3,
                        overflow: .ellipsis,
                        style: boardText(
                          size: FontSizes.sm,
                          height: LineHeights.row,
                          color: c.text3,
                        ),
                      ),
                    Padding(
                      padding: Insets.messageLinks,
                      child: Row(
                        spacing: 14,
                        children: [
                          if (widget.onDetails case final f? when vm.details)
                            link(
                              S.current.errDetails,
                              f,
                              ValueKey('toast-details-${vm.id}'),
                            ),
                          if (widget.onRetry case final f? when vm.retry)
                            link(
                              S.current.errTryAgain,
                              f,
                              ValueKey('toast-retry-${vm.id}'),
                            ),
                          Expanded(
                            child: Text(
                              vm.stays ?? S.current.toastHidesIn(_left),
                              textAlign: .end,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: boardText(
                                size: FontSizes.sm,
                                color: c.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Gaps.hToastParts,
              Transform.translate(
                offset: const Offset(4, -4),
                child: Semantics(
                  button: true,
                  label: S.current.toastDismiss,
                  child: InkWell(
                    key: ValueKey('toast-dismiss-${vm.id}'),
                    onTap: widget.onDismiss,
                    borderRadius: Radii.segment,
                    child: SizedBox.square(
                      dimension: 26,
                      child: Center(
                        child: AppIconView(
                          AppIcon.errClose,
                          size: IconSizes.xs,
                          color: c.text4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
