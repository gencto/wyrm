import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/device_os.dart';
import '../indicators/refusal_reason.dart';
import '../indicators/unlock_method.dart';
import '../models/change_words.dart';
import 'step_up_dialog.dart';

/// Why the last try of the step-up failed.
sealed class StepUpProblem extends Equatable {
  const StepUpProblem();

  /// The gateway refused the password.
  const factory StepUpProblem.wrongPassword() = StepUpWrongPasswordProblem;

  /// The OS prompt gave no signature.
  const factory StepUpProblem.stopped() = StepUpStoppedProblem;

  /// The key no longer opens.
  const factory StepUpProblem.keyGone() = StepUpKeyGoneProblem;

  /// A refusal the gateway named.
  const factory StepUpProblem.refused(RefusalReason reason) =
      StepUpRefusedProblem;

  /// A refusal it did not name, or the OS's failure: its message as it is.
  const factory StepUpProblem.said(String text) = StepUpSaidProblem;

  /// Its words, with the [site] and the unlock [method].
  String words(String site, UnlockMethod method) => switch (this) {
    StepUpWrongPasswordProblem() => S.current.lockWrongPassword,
    StepUpStoppedProblem() => S.current.stepUpStopped(method.label),
    StepUpKeyGoneProblem() => S.current.stepUpKeyGone(site),
    StepUpRefusedProblem(:final reason) => S.current.stepUpRefused(
      site,
      reason.text,
    ),
    StepUpSaidProblem(:final said) => S.current.stepUpRefused(site, said),
  };
}

final class StepUpWrongPasswordProblem extends StepUpProblem {
  const StepUpWrongPasswordProblem();
  @override
  List<Object?> get props => const [];
}

final class StepUpStoppedProblem extends StepUpProblem {
  const StepUpStoppedProblem();
  @override
  List<Object?> get props => const [];
}

final class StepUpKeyGoneProblem extends StepUpProblem {
  const StepUpKeyGoneProblem();
  @override
  List<Object?> get props => const [];
}

final class StepUpRefusedProblem extends StepUpProblem {
  const StepUpRefusedProblem(this.reason);
  final RefusalReason reason;
  @override
  List<Object?> get props => [reason];
}

final class StepUpSaidProblem extends StepUpProblem {
  const StepUpSaidProblem(this.said);
  final String said;
  @override
  List<Object?> get props => [said];
}

/// One change the step-up confirms.
final class StepUpLineData extends Equatable {
  const StepUpLineData({
    required this.level,
    required this.deed,
    this.key = '',
  });

  final StepUpLevel level;

  /// What it does.
  final StepUpDeedVm deed;
  final String key;

  @override
  List<Object?> get props => [level, deed, key];
}

/// The step-up as typed values (ADR 0050 §1.3, board `UnlockStepUp`).
final class StepUpScreenVm extends Equatable {
  const StepUpScreenVm({
    required this.site,
    required this.user,
    required this.lines,
    required this.method,
    required this.os,
    this.busy = false,
    this.problem,
    this.passwordOnly = false,
  });

  final String site;
  final String user;
  final List<StepUpLineData> lines;
  final UnlockMethod method;

  /// The computer Studio runs on.
  final DeviceOs os;
  final bool busy;
  final StepUpProblem? problem;

  /// No key here: the password at once.
  final bool passwordOnly;

  @override
  List<Object?> get props => [
    site,
    user,
    lines,
    method,
    os,
    busy,
    problem,
    passwordOnly,
  ];
}

/// The step-up from typed values: it words them and draws them with
/// [StepUpDialog].
class StepUpScreen extends StatelessWidget {
  const StepUpScreen({
    required this.vm,
    required this.onDevice,
    required this.onPassword,
    required this.onCancel,
    super.key,
  });

  final StepUpScreenVm vm;
  final VoidCallback onDevice;
  final ValueChanged<String> onPassword;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final name = vm.method.label;
    return StepUpDialog(
      vm: StepUpDialogVm(
        title: s.stepUpTitle,
        lead: s.stepUpLead(vm.lines.length, vm.site),
        lines: [
          for (final l in vm.lines)
            StepUpLineVm(level: l.level, text: l.deed.text, key: l.key),
        ],
        glyph: vm.method.glyph,
        device: vm.busy
            ? s.stepUpWaiting(name)
            : s.stepUpDevice(name, vm.site, vm.os.device),
        confirm: s.stepUpConfirmWith(name),
        passwordConfirm: s.stepUpConfirm,
        usePassword: s.unlockUsePassword,
        cancel: s.cancel,
        passwordLabel: s.unlockPasswordFor(vm.user),
        busy: vm.busy,
        error: vm.problem?.words(vm.site, vm.method),
        passwordOnly: vm.passwordOnly,
      ),
      onDevice: onDevice,
      onPassword: onPassword,
      onCancel: onCancel,
    );
  }
}
