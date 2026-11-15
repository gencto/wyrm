import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/rise.dart';
import '../indicators/device_os.dart';
import '../indicators/unlock_method.dart';
import '../inputs/boxed_form_field.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/shades.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// The tag after a device's name, and its colour.
enum SecurityTag {
  /// This computer's own device.
  thisDevice(Tone.good),

  /// Removed by an administrator ([SecurityDeviceVm.removedBy]).
  removed(Tone.bad),

  /// Ended by `Sign out everywhere`.
  signedOut(Tone.neutral),

  /// The password is due within a week ([SecurityDeviceVm.dueDays]).
  passwordDue(Tone.warn);

  const SecurityTag(this.tone);

  final Tone tone;
}

/// One device of *Your devices on `<site>`*: typed values, worded here.
final class SecurityDeviceVm extends Equatable {
  const SecurityDeviceVm({
    required this.id,
    required this.os,
    required this.name,
    this.tag,
    this.removedBy = '',
    this.dueDays = 0,
    this.lastUsed,
    this.usedNow = false,
    this.added,
    this.own = false,
  });

  final String id;

  /// Its platform: the tile word and the unlock method.
  final DeviceOs os;
  final String name;
  final SecurityTag? tag;

  /// Who removed it, for [SecurityTag.removed].
  final String removedBy;

  /// Days until the password is due, for [SecurityTag.passwordDue].
  final int dueDays;

  /// Last used; null when never.
  final DateTime? lastUsed;

  /// This computer's device, used within the last minute.
  final bool usedNow;

  /// Added; null when not known.
  final DateTime? added;

  /// This computer's own device (its button is not coral).
  final bool own;

  bool get removed => tag == SecurityTag.removed;

  /// `this device`, `password due in 4 days`, `removed by ivan`.
  String? get tagLabel => switch (tag) {
    null => null,
    SecurityTag.thisDevice => S.current.securityThisDevice,
    SecurityTag.removed => S.current.securityRemovedBy(removedBy),
    SecurityTag.signedOut => S.current.securitySignedOut,
    SecurityTag.passwordDue => S.current.securityDue(dueDays),
  };

  /// `Touch ID · used now · added 3 Nov`.
  String get detail => removed
      ? [os.method, S.current.securityRemoved].join(' · ')
      : [
          os.method,
          if (usedNow)
            S.current.securityUsedNow
          else if (lastUsed case final t?)
            Formats.ago(t, nowWord: S.current.unlockAgoNow),
          if (added case final a?)
            S.current.securityAdded(Formats.shortDate(a)),
        ].join(' · ');

  /// `Turn off`, `Forget` or `Remove`.
  String get action => own
      ? S.current.securityTurnOff
      : removed
      ? S.current.securityForget
      : S.current.securityRemove;

  @override
  List<Object?> get props => [
    id,
    os,
    name,
    tag,
    removedBy,
    dueDays,
    lastUsed,
    usedNow,
    added,
    own,
  ];
}

/// Account › Security (board `UnlockApp`) as typed values: the dialog says
/// them in the current language itself (studio-rules §5).
final class SecurityDialogVm extends Equatable {
  const SecurityDialogVm({
    required this.user,
    required this.site,
    required this.os,
    required this.method,
    required this.devices,
    this.biometricHere = true,
    this.unlockOn = false,
    this.unlockEnabled = true,
    this.keyAdded,
    this.lockAfter = 0,
    this.lockMax = 30,
    this.confirmOn = false,
    this.policyOn = false,
    this.maxPerUser = 5,
    this.passwordEveryDays = 30,
    this.busy = false,
    this.askPassword = false,
    this.passwordWrong = false,
  });

  final String user;
  final String site;

  /// This computer: `On this Mac`, where its key lives.
  final DeviceOs os;

  /// What unlocks the key here: `Unlock with Touch ID`.
  final UnlockMethod method;
  final List<SecurityDeviceVm> devices;

  /// A biometric is here; without one the unlock says it asks for the
  /// password.
  final bool biometricHere;
  final bool unlockOn;

  /// The switch can be used.
  final bool unlockEnabled;

  /// When this computer's key was made.
  final DateTime? keyAdded;

  /// Minutes; 0 is off.
  final int lockAfter;

  /// The longest lock delay the site allows, in minutes.
  final int lockMax;

  /// The gateway asks for a confirmation; the switch is read-only.
  final bool confirmOn;

  /// The site's device policy: devices on, at most [maxPerUser] each, a
  /// password every [passwordEveryDays] days.
  final bool policyOn;
  final int maxPerUser;
  final int passwordEveryDays;
  final bool busy;

  /// The gateway asks for the password before a new key.
  final bool askPassword;

  /// The last password was wrong.
  final bool passwordWrong;

  @override
  List<Object?> get props => [
    user,
    site,
    os,
    method,
    devices,
    biometricHere,
    unlockOn,
    unlockEnabled,
    keyAdded,
    lockAfter,
    lockMax,
    confirmOn,
    policyOn,
    maxPerUser,
    passwordEveryDays,
    busy,
    askPassword,
    passwordWrong,
  ];
}

/// The unlock switch was turned, or the password asked for it was given:
/// the words of the system prompt come with it, in the current language.
final class UnlockRequest extends Equatable {
  const UnlockRequest({required this.on, required this.reason, this.password});

  final bool on;

  /// What the system prompt says (`turn on unlocking plant as olena`).
  final String reason;
  final String? password;

  @override
  List<Object?> get props => [on, reason, password];
}

/// Account › Security: *On this `<device>`* (the unlock switch, the lock
/// delay, `Confirm before config changes` read-only), *Your devices on
/// `<site>`* with their tags and buttons, the policy line and `Sign out
/// everywhere`. 680 wide, radius 14.
class SecurityDialog extends StatefulWidget {
  const SecurityDialog({
    required this.vm,
    required this.onUnlock,
    required this.onLockAfter,
    required this.onDevice,
    required this.onSignOut,
    required this.onClose,
    super.key,
  });

  final SecurityDialogVm vm;
  final ValueChanged<UnlockRequest> onUnlock;
  final ValueChanged<int> onLockAfter;

  /// A device's button, by its id.
  final ValueChanged<String> onDevice;
  final VoidCallback onSignOut;
  final VoidCallback onClose;

  @override
  State<SecurityDialog> createState() => _SecurityDialogState();
}

class _SecurityDialogState extends State<SecurityDialog> {
  /// The lock delays the board offers, in minutes, up to the site's most.
  static const _lockMinutes = [5, 15, 30];

  String? _typed;

  String get _reason =>
      S.current.unlockEnablePrompt(widget.vm.site, widget.vm.user);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = S.current;
    final vm = widget.vm;
    final store = vm.os.store;
    final lockChoices = [
      (0, s.securityLockOff),
      for (final m in _lockMinutes)
        if (m <= vm.lockMax) (m, s.securityMinutes(m)),
    ];
    Widget section(String text, {double top = AppSpacing.none}) => Padding(
      padding: EdgeInsets.only(top: top),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: FontSizes.sm,
          letterSpacing: 0.72,
          color: c.text4,
        ),
      ),
    );
    final lockWord = [
      for (final (m, w) in lockChoices)
        if (m == vm.lockAfter) w,
    ].firstOrNull;
    return Rise(
      child: Material(
        color: c.ground1,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.dialog,
          side: BorderSide(color: c.line2),
        ),
        elevation: 24,
        shadowColor: Shades.dialogShadow,
        clipBehavior: .antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.dialog,
            maxHeight: AppSizes.dialogMaxHeight,
          ),
          child: SizedBox(
            width: AppSizes.dialog,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.ground3)),
                  ),
                  child: Row(
                    spacing: 12,
                    children: [
                      Text(
                        s.securityTitle,
                        style: TextStyle(
                          fontSize: FontSizes.panelTitle,
                          fontWeight: .w600,
                          color: c.text1,
                        ),
                      ),
                      Text(
                        '${vm.user} · ${vm.site}',
                        style: TextStyle(color: c.text4),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: widget.onClose,
                        child: Text(
                          '×',
                          style: TextStyle(
                            fontSize: 18,
                            color: c.text4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      spacing: 14,
                      children: [
                        section(s.securityOn(vm.os.device)),
                        _Option(
                          title: s.unlockWith(vm.method.label),
                          text: !vm.biometricHere
                              ? s.securityNoBio
                              : vm.unlockOn
                              ? s.securityUnlockDesc(
                                  store,
                                  switch (vm.keyAdded) {
                                    final a? => Formats.shortDate(a),
                                    null => '',
                                  },
                                  vm.os.device,
                                )
                              : s.securityUnlockOffDesc(store),
                          trailing: _Switch(
                            on: vm.unlockOn,
                            onChanged: vm.unlockEnabled && !vm.busy
                                ? (on) => widget.onUnlock(
                                    UnlockRequest(on: on, reason: _reason),
                                  )
                                : null,
                          ),
                          below: !vm.askPassword
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
                                          error: vm.passwordWrong
                                              ? s.lockWrongPassword
                                              : null,
                                        ),
                                        label: s.securityPasswordNeeded(
                                          vm.site,
                                        ),
                                        obscure: true,
                                        textInputAction: .done,
                                        onSubmitted: (_) => _submit(),
                                      ),
                                    ),
                                    _SmallButton(
                                      label: s.securityTurnOn,
                                      ink: c.onEmber,
                                      fill: c.ember,
                                      height: AppSizes.fieldButton,
                                      onPressed: vm.busy ? null : _submit,
                                    ),
                                  ],
                                ),
                        ),
                        _Option(
                          title: s.securityLockAfter,
                          text: s.securityLockDesc(vm.site, vm.lockMax),
                          trailing: PopupMenuButton<int>(
                            tooltip: s.securityLockAfter,
                            onSelected: widget.onLockAfter,
                            color: c.ground2,
                            itemBuilder: (_) => [
                              for (final (m, w) in lockChoices)
                                PopupMenuItem(value: m, child: Text(w)),
                            ],
                            child: Container(
                              height: AppSizes.smallButton,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: Radii.control,
                                border: Border.all(color: c.line2),
                              ),
                              child: Row(
                                mainAxisSize: .min,
                                spacing: AppSpacing.sm,
                                children: [
                                  Text(
                                    lockWord ?? '${vm.lockAfter}',
                                    style: TextStyle(
                                      fontSize: FontSizes.md,
                                      color: c.text1,
                                    ),
                                  ),
                                  // The board's ▾ (the bundled fonts have no
                                  // such glyph).
                                  CustomPaint(
                                    size: AppSizes.caret,
                                    painter: _Caret(c.text4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _Option(
                          title: s.securityConfirm,
                          text: vm.confirmOn
                              ? s.securityConfirmForced(vm.site)
                              : s.securityConfirmNone(vm.site),
                          // The gateway decides; Studio shows it (ADR 0050
                          // decision 9): read-only either way.
                          trailing: _Switch(on: vm.confirmOn, locked: true),
                        ),
                        section(
                          s.securityDevicesOn(vm.site),
                          top: 6,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: Radii.card,
                            border: Border.all(color: c.ground3),
                          ),
                          child: Column(
                            crossAxisAlignment: .stretch,
                            children: [
                              if (vm.devices.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Text(
                                    s.securityNoDevices,
                                    style: TextStyle(
                                      fontSize: FontSizes.md,
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
                                s.securityPolicy(
                                  vm.site,
                                  vm.policyOn
                                      ? s.securityPolicyOn
                                      : s.securityPolicyOff,
                                  vm.maxPerUser,
                                  vm.passwordEveryDays,
                                  vm.confirmOn ? s.securityPolicyConfirm : '',
                                ),
                                style: TextStyle(
                                  fontSize: FontSizes.sm,
                                  height: 1.5,
                                  color: c.text4,
                                ),
                              ),
                            ),
                            _SmallButton(
                              label: s.securitySignOutAll,
                              ink: c.badText,
                              border: c.badLine,
                              height: AppSizes.smallButton,
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
      widget.onUnlock(UnlockRequest(on: true, reason: _reason, password: p));
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
      padding: Insets.card,
      decoration: BoxDecoration(
        color: c.ground0,
        borderRadius: Radii.card,
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
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: FontSizes.lg,
                        color: c.text1,
                      ),
                    ),
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: FontSizes.sm,
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

  /// The knob's gap to the track's edge.
  static const double _knobInset =
      (AppSizes.switchHeight - AppSizes.switchKnob) / 2;

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
            width: AppSizes.switchWidth,
            height: AppSizes.switchHeight,
            decoration: BoxDecoration(
              color: on ? c.ember : c.line3,
              borderRadius: Radii.toggle,
            ),
            child: Stack(
              children: [
                Positioned(
                  top: _knobInset,
                  left: on
                      ? AppSizes.switchWidth - AppSizes.switchKnob - _knobInset
                      : _knobInset,
                  child: Container(
                    width: AppSizes.switchKnob,
                    height: AppSizes.switchKnob,
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
    final tag = switch (vm.tag?.tone) {
      Tone.good => c.good,
      Tone.warn => c.warn,
      Tone.bad => c.bad,
      Tone.ember || Tone.neutral || null => c.text4,
    };
    return Container(
      padding: Insets.card,
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.ground3)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: AppSizes.deviceTile,
            height: AppSizes.deviceTile,
            decoration: BoxDecoration(
              color: c.ground3,
              borderRadius: Radii.control,
            ),
            alignment: .center,
            child: Text(
              vm.os.tile,
              style: AppText.xs.copyWith(color: c.text2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text.rich(
                  TextSpan(
                    text: vm.name,
                    style: AppText.lg.copyWith(color: c.text1),
                    children: [
                      if (vm.tagLabel case final t?)
                        TextSpan(
                          text: ' $t',
                          style: TextStyle(
                            fontSize: FontSizes.sm,
                            color: tag,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  vm.detail,
                  style: AppText.sm.copyWith(color: c.text4),
                ),
              ],
            ),
          ),
          _SmallButton(
            label: vm.action,
            ink: vm.own ? c.text1 : c.badText,
            border: c.line3,
            height: AppSizes.rowButton,
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
  });

  final String label;
  final Color ink;
  final Color? fill;
  final Color? border;
  final double height;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: fill ?? Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: Radii.control,
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
          style: AppText.sm.copyWith(color: ink),
        ),
      ),
    ),
  );
}

class _Caret extends CustomPainter {
  _Caret(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close(),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_Caret old) => old.color != color;
}
