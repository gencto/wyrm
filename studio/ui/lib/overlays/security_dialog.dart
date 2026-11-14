import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/rise.dart';
import '../inputs/boxed_form_field.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';

/// One device of *Your devices on `<site>`*.
final class SecurityDeviceVm extends Equatable {
  const SecurityDeviceVm({
    required this.id,
    required this.os,
    required this.name,
    required this.detail,
    required this.action,
    this.tag,
    this.tagTone = Tone.neutral,
    this.own = false,
  });

  final String id;

  /// The tile's word: `mac`, `iOS`, `win`, `and`.
  final String os;
  final String name;

  /// `this device`, `password due in 4 days`, `removed by ivan`.
  final String? tag;
  final Tone tagTone;

  /// `Touch ID · used now · added 3 Nov`.
  final String detail;

  /// `Turn off`, `Remove` or `Forget`.
  final String action;

  /// This computer's own device (its button is not coral).
  final bool own;

  @override
  List<Object?> get props => [id, os, name, tag, tagTone, detail, action, own];
}

/// Account › Security (board `UnlockApp`), resolved.
final class SecurityDialogVm extends Equatable {
  const SecurityDialogVm({
    required this.title,
    required this.subtitle,
    required this.onThis,
    required this.unlockTitle,
    required this.unlockText,
    required this.lockTitle,
    required this.lockText,
    required this.lockAfter,
    required this.lockChoices,
    required this.confirmTitle,
    required this.confirmText,
    required this.devicesTitle,
    required this.devices,
    required this.policy,
    required this.signOut,
    this.unlockOn = false,
    this.unlockEnabled = true,
    this.confirmOn = false,
    this.busy = false,
    this.passwordLabel,
    this.passwordError,
    this.turnOn = 'Turn on',
    this.empty,
  });

  final String title;

  /// `olena · plant`.
  final String subtitle;

  /// `On this Mac`.
  final String onThis;
  final String unlockTitle;
  final String unlockText;
  final bool unlockOn;

  /// A biometric is here: the switch can be used.
  final bool unlockEnabled;
  final String lockTitle;
  final String lockText;

  /// Minutes; 0 is off.
  final int lockAfter;

  /// The choices and their words, in order (`0` → `Off`).
  final List<(int, String)> lockChoices;
  final String confirmTitle;
  final String confirmText;

  /// The gateway asks for a confirmation; the switch is read-only.
  final bool confirmOn;
  final String devicesTitle;
  final List<SecurityDeviceVm> devices;

  /// `No devices yet.`
  final String? empty;
  final String policy;
  final String signOut;
  final bool busy;

  /// The gateway asks for the password before a new key: its label, and
  /// the last refusal.
  final String? passwordLabel;
  final String? passwordError;
  final String turnOn;

  @override
  List<Object?> get props => [
    title,
    subtitle,
    onThis,
    unlockTitle,
    unlockText,
    unlockOn,
    unlockEnabled,
    lockTitle,
    lockText,
    lockAfter,
    lockChoices,
    confirmTitle,
    confirmText,
    confirmOn,
    devicesTitle,
    devices,
    empty,
    policy,
    signOut,
    busy,
    passwordLabel,
    passwordError,
    turnOn,
  ];
}

/// Account › Security: *On this `<device>`* (the unlock switch, the lock
/// delay, `Confirm before config changes` read-only), *Your devices on
/// `<site>`* with their tags and buttons, the policy line and `Sign out
/// everywhere`. 680 wide, radius 14.
class SecurityDialog extends StatefulWidget {
  const SecurityDialog({
    required this.vm,
    required this.onUnlock,
    required this.onPassword,
    required this.onLockAfter,
    required this.onDevice,
    required this.onSignOut,
    required this.onClose,
    super.key,
  });

  final SecurityDialogVm vm;
  final ValueChanged<bool> onUnlock;
  final ValueChanged<String> onPassword;
  final ValueChanged<int> onLockAfter;

  /// A device's button, by its id.
  final ValueChanged<String> onDevice;
  final VoidCallback onSignOut;
  final VoidCallback onClose;

  @override
  State<SecurityDialog> createState() => _SecurityDialogState();
}

class _SecurityDialogState extends State<SecurityDialog> {
  String? _typed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    Widget section(String text, {double top = 0}) => Padding(
      padding: EdgeInsets.only(top: top),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, letterSpacing: 0.72, color: c.text4),
      ),
    );
    final lockWord = [
      for (final (m, w) in vm.lockChoices)
        if (m == vm.lockAfter) w,
    ].firstOrNull;
    return Rise(
      child: Material(
        color: c.ground1,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: c.line2),
        ),
        elevation: 24,
        shadowColor: const Color(0x80000000),
        clipBehavior: .antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 900),
          child: SizedBox(
            width: 680,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.ground3)),
                  ),
                  child: Row(
                    spacing: 12,
                    children: [
                      Text(
                        vm.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: .w600,
                          color: c.text1,
                        ),
                      ),
                      Text(vm.subtitle, style: TextStyle(color: c.text4)),
                      const Spacer(),
                      InkWell(
                        onTap: widget.onClose,
                        child: Text(
                          '×',
                          style: TextStyle(fontSize: 18, color: c.text4),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      spacing: 14,
                      children: [
                        section(vm.onThis),
                        _Option(
                          title: vm.unlockTitle,
                          text: vm.unlockText,
                          trailing: _Switch(
                            on: vm.unlockOn,
                            onChanged: vm.unlockEnabled && !vm.busy
                                ? widget.onUnlock
                                : null,
                          ),
                          below: vm.passwordLabel == null
                              ? null
                              : Row(
                                  crossAxisAlignment: .end,
                                  spacing: 10,
                                  children: [
                                    Expanded(
                                      child: BoxedFormField(
                                        vm: FieldVm(
                                          value: _typed,
                                          onChanged: (v) => _typed = v,
                                          error: vm.passwordError,
                                        ),
                                        label: vm.passwordLabel!,
                                        obscure: true,
                                        textInputAction: .done,
                                        onSubmitted: (_) => _submit(),
                                      ),
                                    ),
                                    _SmallButton(
                                      label: vm.turnOn,
                                      ink: c.onEmber,
                                      fill: c.ember,
                                      height: 46,
                                      onPressed: vm.busy ? null : _submit,
                                    ),
                                  ],
                                ),
                        ),
                        _Option(
                          title: vm.lockTitle,
                          text: vm.lockText,
                          trailing: PopupMenuButton<int>(
                            tooltip: vm.lockTitle,
                            onSelected: widget.onLockAfter,
                            color: c.ground2,
                            itemBuilder: (_) => [
                              for (final (m, w) in vm.lockChoices)
                                PopupMenuItem(value: m, child: Text(w)),
                            ],
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(8),
                                ),
                                border: Border.all(color: c.line2),
                              ),
                              child: Row(
                                mainAxisSize: .min,
                                spacing: 8,
                                children: [
                                  Text(
                                    lockWord ?? '${vm.lockAfter}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: c.text1,
                                    ),
                                  ),
                                  Text('▾', style: TextStyle(color: c.text4)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _Option(
                          title: vm.confirmTitle,
                          text: vm.confirmText,
                          // The gateway decides; Studio shows it (ADR 0050
                          // decision 9): read-only either way.
                          trailing: _Switch(on: vm.confirmOn, locked: true),
                        ),
                        section(vm.devicesTitle, top: 6),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(10),
                            ),
                            border: Border.all(color: c.ground3),
                          ),
                          child: Column(
                            crossAxisAlignment: .stretch,
                            children: [
                              if (vm.devices.isEmpty && vm.empty != null)
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Text(
                                    vm.empty!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: c.text4,
                                    ),
                                  ),
                                ),
                              for (final (i, d) in vm.devices.indexed)
                                _Device(
                                  vm: d,
                                  first: i == 0,
                                  onPressed: () => widget.onDevice(d.id),
                                ),
                            ],
                          ),
                        ),
                        Row(
                          spacing: 12,
                          children: [
                            Expanded(
                              child: Text(
                                vm.policy,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: c.text4,
                                ),
                              ),
                            ),
                            _SmallButton(
                              label: vm.signOut,
                              ink: c.badText,
                              border: c.badLine,
                              height: 32,
                              onPressed: vm.busy ? null : widget.onSignOut,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final p = _typed ?? '';
    if (p.isNotEmpty) {
      widget.onPassword(p);
    }
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.text,
    required this.trailing,
    this.below,
  });

  final String title;
  final String text;
  final Widget trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.ground0,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(color: c.ground3),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 14,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 3,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14, color: c.text1)),
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: c.text4,
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
          ?below,
        ],
      ),
    );
  }
}

/// The board's switch: 40 × 22, radius 11, `ember` on / `line3` off, a
/// knob 16 in `text1`; read-only at 55 %.
class _Switch extends StatelessWidget {
  const _Switch({required this.on, this.onChanged, this.locked = false});

  final bool on;
  final ValueChanged<bool>? onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      toggled: on,
      enabled: onChanged != null && !locked,
      child: Opacity(
        opacity: locked ? 0.55 : 1,
        child: GestureDetector(
          onTap: locked || onChanged == null ? null : () => onChanged!(!on),
          child: Container(
            width: 40,
            height: 22,
            decoration: BoxDecoration(
              color: on ? c.ember : c.line3,
              borderRadius: const BorderRadius.all(Radius.circular(11)),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 3,
                  left: on ? 21 : 3,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: c.text1,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Device extends StatelessWidget {
  const _Device({
    required this.vm,
    required this.first,
    required this.onPressed,
  });

  final SecurityDeviceVm vm;
  final bool first;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tag = switch (vm.tagTone) {
      .good => c.good,
      .warn => c.warn,
      .bad => c.bad,
      _ => c.text4,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.ground3)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.ground3,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            alignment: .center,
            child: Text(vm.os, style: TextStyle(fontSize: 11, color: c.text2)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text.rich(
                  TextSpan(
                    text: vm.name,
                    style: TextStyle(fontSize: 14, color: c.text1),
                    children: [
                      if (vm.tag case final t?)
                        TextSpan(
                          text: ' $t',
                          style: TextStyle(fontSize: 12, color: tag),
                        ),
                    ],
                  ),
                ),
                Text(
                  vm.detail,
                  style: TextStyle(fontSize: 12, color: c.text4),
                ),
              ],
            ),
          ),
          _SmallButton(
            label: vm.action,
            ink: vm.own ? c.text1 : c.badText,
            border: c.line3,
            height: 30,
            fontSize: 12,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.ink,
    required this.height,
    required this.onPressed,
    this.fill,
    this.border,
    this.fontSize = 12,
  });

  final String label;
  final Color ink;
  final Color? fill;
  final Color? border;
  final double height;
  final double fontSize;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: fill ?? Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      side: border == null ? BorderSide.none : BorderSide(color: border!),
    ),
    clipBehavior: .antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: .center,
        child: Text(
          label,
          style: TextStyle(fontSize: fontSize, color: ink),
        ),
      ),
    ),
  );
}
