import 'package:freezed_annotation/freezed_annotation.dart';

import 'change_op.dart';
import 'change_side.dart';

part 'step_up_deed.freezed.dart';

/// What one line of a step-up does (board `UnlockStepUp`): named by
/// `business` where the refused request is known, said by `ui`.
@freezed
sealed class StepUpDeed with _$StepUpDeed {
  /// A `set` of the value [name].
  const factory StepUpDeed.set(String name) = StepUpDeedSet;

  /// An `invoke` of the action [name] (its wire name, as data).
  const factory StepUpDeed.action(String name) = StepUpDeedAction;

  /// A staged change being applied: [op] of [field] to [to].
  const factory StepUpDeed.change({
    required ChangeOp op,
    required String field,
    required ChangeSide to,
  }) = StepUpDeedChange;

  const factory StepUpDeed.addUser(String name) = StepUpDeedAddUser;

  const factory StepUpDeed.removeUser(String name) = StepUpDeedRemoveUser;

  const factory StepUpDeed.setRoles(String name) = StepUpDeedSetRoles;

  const factory StepUpDeed.setPassword(String name) = StepUpDeedSetPassword;

  const factory StepUpDeed.disableUser(String name) = StepUpDeedDisableUser;

  const factory StepUpDeed.enableUser(String name) = StepUpDeedEnableUser;

  const factory StepUpDeed.removeDevice() = StepUpDeedRemoveDevice;
}
