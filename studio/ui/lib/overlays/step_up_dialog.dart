import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/rise.dart';
import '../indicators/biometric_icon.dart';
import '../inputs/boxed_form_field.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One change the step-up confirms: its level badge, what it does, its key.
final class StepUpLineVm extends Equatable {
  const StepUpLineVm({
    required this.level,
    required this.text,
    this.key = '',
  });

  /// `config` (coral badge) or `write` (grey).
  final String level;
  final String text;
  final String key;

  @override
  List<Object?> get props => [level, text, key];
}

/// What the step-up dialog says (board `UnlockStepUp`), resolved.
final class StepUpDialogVm extends Equatable {
  const StepUpDialogVm({
    required this.title,
    required this.lead,
    required this.lines,
    required this.glyph,
    required this.device,
    required this.confirm,
    required this.usePassword,
    required this.cancel,
    required this.passwordLabel,
    this.busy = false,
    this.error,
    this.passwordOnly = false,
    this.passwordConfirm = 'Confirm',
  });

  /// `Confirm it is you`.
  final String title;

  /// `Apply 3 changes on plant. … asks for a fresh confirmation …`
  final String lead;
  final List<StepUpLineVm> lines;
  final BiometricGlyph glyph;

  /// The device row's line: what the key signs, or `Waiting for <name>…`.
  final String device;

  /// `Confirm with <name>`.
  final String confirm;
  final String usePassword;
  final String cancel;
  final String passwordLabel;

  /// The confirm button under the password.
  final String passwordConfirm;
  final bool busy;
  final String? error;

  /// No key here: the password at once.
  final bool passwordOnly;

  @override
  List<Object?> get props => [
    title,
    lead,
    lines,
    glyph,
    device,
    confirm,
    usePassword,
    cancel,
    passwordLabel,
    passwordConfirm,
    busy,
    error,
    passwordOnly,
  ];
}

/// The step-up (ADR 0050 §1.3, board `UnlockStepUp`): what is being
/// applied with level badges, the device row, `Use the password`, `Cancel`
/// and `Confirm with <name>`. 520 wide, radius 14, `ground1` on `line2`.
class StepUpDialog extends StatefulWidget {
  const StepUpDialog({
    required this.vm,
    required this.onDevice,
    required this.onPassword,
    required this.onCancel,
    super.key,
  });

  final StepUpDialogVm vm;
  final VoidCallback onDevice;
  final ValueChanged<String> onPassword;
  final VoidCallback onCancel;

  /// The board's dimmer under the dialog.
  static const barrier = Color.fromRGBO(8, 10, 11, 0.6);

  @override
  State<StepUpDialog> createState() => _StepUpDialogState();
}

class _StepUpDialogState extends State<StepUpDialog> {
  var _password = false;
  String? _typed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    final password = _password || vm.passwordOnly;
    void submit() {
      if (password) {
        final p = _typed ?? '';
        if (p.isNotEmpty) {
          widget.onPassword(p);
        }
      } else {
        widget.onDevice();
      }
    }

    return Rise(
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: vm.title,
        child: Material(
          color: c.ground1,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            side: BorderSide(color: c.line2),
          ),
          elevation: 24,
          shadowColor: const Color(0x80000000),
          clipBehavior: .antiAlias,
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 6,
                    children: [
                      Text(
                        vm.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: .w600,
                          color: c.text1,
                        ),
                      ),
                      Text(
                        vm.lead,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: c.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(24, 10, 24, 10),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    border: Border.all(color: c.ground3),
                  ),
                  child: Column(
                    children: [
                      for (final (i, l) in vm.lines.indexed)
                        _Line(vm: l, first: i == 0),
                    ],
                  ),
                ),
                if (password)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                    child: BoxedFormField(
                      vm: FieldVm(
                        value: _typed,
                        onChanged: (v) => _typed = v,
                        error: vm.error,
                        enabled: !vm.busy,
                      ),
                      label: vm.passwordLabel,
                      obscure: true,
                      border: c.emberLine,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: .done,
                      onSubmitted: (_) => submit(),
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.emberFill,
                      borderRadius: const BorderRadius.all(Radius.circular(10)),
                      border: Border.all(color: c.emberLine),
                    ),
                    child: Row(
                      spacing: 14,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: vm.busy ? c.ember : c.emberLine,
                              width: 1.5,
                            ),
                          ),
                          alignment: .center,
                          child: BiometricIcon(
                            glyph: vm.glyph,
                            size: 26,
                            compact: true,
                            color: c.emberSoft,
                          ),
                        ),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              vm.error ?? vm.device,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: vm.error == null ? c.text2 : c.badText,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.ground3)),
                  ),
                  child: Row(
                    spacing: 10,
                    children: [
                      if (!password)
                        InkWell(
                          onTap: vm.busy
                              ? null
                              : () => setState(() => _password = true),
                          child: Text(
                            vm.usePassword,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.text2,
                              decoration: .underline,
                              decorationColor: c.text2,
                            ),
                          ),
                        ),
                      const Spacer(),
                      _Button(
                        label: vm.cancel,
                        onPressed: widget.onCancel,
                        border: c.line3,
                        ink: c.text1,
                      ),
                      _Button(
                        label: password ? vm.passwordConfirm : vm.confirm,
                        onPressed: vm.busy ? null : submit,
                        fill: c.ember,
                        ink: c.onEmber,
                        strong: true,
                      ),
                    ],
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

class _Line extends StatelessWidget {
  const _Line({required this.vm, required this.first});

  final StepUpLineVm vm;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final config = vm.level == 'config';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.ground3)),
      ),
      child: Row(
        spacing: 10,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: config ? c.badTint : c.ground4,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
            child: Text(
              vm.level,
              style: TextStyle(
                fontSize: 11,
                color: config ? c.badText : c.text3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              vm.text,
              style: TextStyle(fontSize: 13, color: c.text1),
            ),
          ),
          if (vm.key.isNotEmpty)
            Flexible(
              child: Text(
                vm.key,
                maxLines: 1,
                overflow: .ellipsis,
                textAlign: .right,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: c.text4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onPressed,
    required this.ink,
    this.fill,
    this.border,
    this.strong = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color ink;
  final Color? fill;
  final Color? border;
  final bool strong;

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
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: .center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: strong ? .w600 : .w400,
            color: ink,
          ),
        ),
      ),
    ),
  );
}
