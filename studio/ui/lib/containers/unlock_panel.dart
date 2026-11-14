import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../alerts/unlock_notice.dart';
import '../alerts/unreachable_alert.dart';
import '../buttons/log_in_button.dart';
import '../buttons/unlock_button.dart';
import '../forms/base_form.dart';
import '../indicators/biometric_icon.dart';
import '../inputs/boxed_form_field.dart';
import '../inputs/check_row.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'rise.dart';
import 'shake.dart';

/// The account the key is for, as the card of the board `Unlock` shows it.
final class UnlockAccountVm extends Equatable {
  const UnlockAccountVm({
    required this.initials,
    required this.user,
    required this.role,
    required this.host,
    required this.last,
    this.tone = Tone.good,
  });

  /// Two letters of the user.
  final String initials;
  final String user;

  /// `· engineer on plant`, or empty before the role is known.
  final String role;

  /// `plant.local:8446 + standby`, in mono with the probe's dot.
  final String host;
  final Tone tone;

  /// `Touch ID · 2 h ago`, `password`.
  final String last;

  @override
  List<Object?> get props => [initials, user, role, host, last, tone];
}

/// The log-in page while a device key is in play (boards `Unlock`,
/// `UnlockFallback`, `UnlockChanged`, `UnlockSignedOut`, `UnlockLinux`),
/// resolved.
final class UnlockPanelVm extends Equatable {
  const UnlockPanelVm({
    required this.title,
    required this.subtitle,
    required this.account,
    required this.glyph,
    required this.unlockLabel,
    required this.note,
    required this.passwordLabel,
    required this.another,
    required this.footer,
    required this.version,
    this.notice,
    this.password = false,
    this.checking = false,
    this.usePassword,
    this.reEnable,
    this.footerTone = Tone.good,
  });

  /// `Welcome back` / `Log in`.
  final String title;

  /// `Unlock to open the tree of <site>.` / `to <site>’s gateway.`
  final String subtitle;
  final UnlockNoticeVm? notice;
  final UnlockAccountVm account;

  /// The password form instead of the round button.
  final bool password;

  final BiometricGlyph glyph;

  /// `Unlock with <name>`.
  final String unlockLabel;

  /// `Or press Enter` / `Checking the key with <site>…`.
  final String note;

  /// The gateway checks the key: the ring turns.
  final bool checking;

  /// `Password for <user>`.
  final String passwordLabel;

  /// `Turn <name> on again after I log in`; null hides it.
  final String? reEnable;

  /// `Use the password` (shown with the round button only).
  final String? usePassword;
  final String another;

  /// `Key in <store> · added <date>` or the TLS line.
  final String footer;
  final Tone footerTone;
  final String version;

  @override
  List<Object?> get props => [
    title,
    subtitle,
    notice,
    account,
    password,
    glyph,
    unlockLabel,
    note,
    checking,
    passwordLabel,
    reEnable,
    usePassword,
    another,
    footer,
    footerTone,
    version,
  ];
}

/// The unlock form: title, the notice, the account card, the round button
/// (or the password for the same user), the links and the footer. Enter
/// unlocks while the round button shows.
class UnlockPanel extends StatefulWidget {
  const UnlockPanel({
    required this.vm,
    required this.passwordField,
    required this.onUnlock,
    required this.onLogIn,
    required this.onAnother,
    this.onUsePassword,
    this.reEnableField,
    this.busy = false,
    this.wrong = false,
    this.unreachable,
    this.onRetry,
    this.onUseStandby,
    super.key,
  });

  final UnlockPanelVm vm;
  final FieldVm<String?> passwordField;
  final FieldVm<bool>? reEnableField;

  /// Null while the key cannot be tried (no answer from the gateway).
  final VoidCallback? onUnlock;
  final VoidCallback onLogIn;
  final VoidCallback onAnother;
  final VoidCallback? onUsePassword;

  /// A password log-in is in flight.
  final bool busy;

  /// The gateway refused the password.
  final bool wrong;
  final UnreachableAlertVm? unreachable;
  final VoidCallback? onRetry;
  final VoidCallback? onUseStandby;

  @override
  State<UnlockPanel> createState() => _UnlockPanelState();
}

class _UnlockPanelState extends State<UnlockPanel> {
  final _focus = FocusNode(debugLabel: 'unlock');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    final link = TextStyle(
      fontSize: 13,
      color: c.text2,
      decoration: .underline,
      decorationColor: c.text2,
    );
    final body = Column(
      crossAxisAlignment: .stretch,
      spacing: 22,
      children: [
        Rise(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 6,
            children: [
              Text(
                vm.title,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: .w600,
                  letterSpacing: -.26,
                  color: c.text1,
                ),
              ),
              Text(vm.subtitle, style: TextStyle(fontSize: 14, color: c.text3)),
            ],
          ),
        ),
        if (widget.unreachable case final alert?)
          Rise(
            child: UnreachableAlert(
              vm: alert,
              onRetry: widget.onRetry ?? () {},
              onStandby: widget.onUseStandby,
            ),
          ),
        if (vm.notice case final n?) Rise(child: UnlockNotice(vm: n)),
        Rise(order: 1, child: _AccountCard(vm: vm.account)),
        if (vm.password)
          Rise(order: 2, child: _password(context))
        else
          Rise(order: 2, child: _bio(context)),
        Rise(
          order: 3,
          child: Wrap(
            alignment: .center,
            spacing: 20,
            runSpacing: 8,
            children: [
              if (!vm.password && vm.usePassword != null)
                InkWell(
                  onTap: widget.onUsePassword,
                  child: Text(vm.usePassword!, style: link),
                ),
              InkWell(
                onTap: widget.onAnother,
                child: Text(vm.another, style: link),
              ),
            ],
          ),
        ),
        Rise(order: 4, child: _footer(context)),
      ],
    );
    if (vm.password) {
      return body;
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            widget.onUnlock?.call(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            widget.onUnlock?.call(),
      },
      child: Focus(autofocus: true, focusNode: _focus, child: body),
    );
  }

  Widget _bio(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        spacing: 14,
        children: [
          UnlockButton(
            glyph: vm.glyph,
            label: vm.unlockLabel,
            busy: vm.checking,
            onPressed: widget.onUnlock,
          ),
          Text(
            vm.unlockLabel,
            style: TextStyle(fontSize: 15, fontWeight: .w600, color: c.text1),
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              vm.note,
              style: TextStyle(fontSize: 12, color: c.text4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _password(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    return BaseForm(
      builder: (context, form) {
        void submit() {
          if (!widget.busy && form.validateAndSave()) {
            widget.onLogIn();
          }
        }

        return Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            Shake(
              trigger: widget.wrong ? true : null,
              child: BoxedFormField(
                vm: widget.passwordField,
                label: vm.passwordLabel,
                obscure: true,
                alert: widget.wrong,
                border: c.emberLine,
                keyboardType: .visiblePassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: .done,
                onSubmitted: (_) => submit(),
              ),
            ),
            if (vm.reEnable case final label?)
              if (widget.reEnableField case final f?)
                CheckRow(vm: f, label: label),
            LogInButton(onPressed: submit, busy: widget.busy),
          ],
        );
      },
    );
  }

  Widget _footer(BuildContext context) {
    final c = context.colors;
    final note = TextStyle(fontSize: 12, color: c.text4);
    final lock = switch (widget.vm.footerTone) {
      .warn => c.warn,
      .bad => c.bad,
      _ => c.good,
    };
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.ground3)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: .center,
        alignment: .spaceBetween,
        children: [
          Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              CustomPaint(
                size: const Size.square(13),
                painter: LockGlyph(lock),
              ),
              Text(widget.vm.footer, style: note),
            ],
          ),
          Text(widget.vm.version, style: note),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.vm});

  final UnlockAccountVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = switch (vm.tone) {
      .good => c.good,
      .bad => c.bad,
      _ => c.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.ground1,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: c.line1),
      ),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.emberTint,
              shape: BoxShape.circle,
            ),
            alignment: .center,
            child: Text(
              vm.initials,
              style: TextStyle(
                fontSize: 15,
                fontWeight: .w600,
                color: c.emberSoft,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 3,
              children: [
                Text.rich(
                  TextSpan(
                    text: vm.user,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                    children: [
                      if (vm.role.isNotEmpty)
                        TextSpan(
                          text: ' ${vm.role}',
                          style: TextStyle(
                            fontWeight: .w400,
                            color: c.text3,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
                Row(
                  spacing: 6,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        vm.host,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: c.text4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            vm.last,
            textAlign: .right,
            style: TextStyle(fontSize: 12, color: c.text4),
          ),
        ],
      ),
    );
  }
}

/// The boards' lock: `M6 11h12v9H6z M8 11V7a4 4 0 0 1 8 0v4`, stroke 2.
class LockGlyph extends CustomPainter {
  LockGlyph(this.color, {this.stroke = 2});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas
      ..save()
      ..scale(k)
      ..drawPath(
        Path()
          ..addRect(const Rect.fromLTWH(6, 11, 12, 9))
          ..moveTo(8, 11)
          ..lineTo(8, 7)
          ..arcToPoint(const Offset(16, 7), radius: const Radius.circular(4))
          ..lineTo(16, 11),
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = stroke
          ..strokeCap = .round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(LockGlyph old) => old.color != color;
}
