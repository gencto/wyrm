import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

/// What a staged change does, as its card names it.
enum ChangeOpTag {
  edit,
  add,
  remove;

  String get label => switch (this) {
    edit => S.current.changeOpEdit,
    add => S.current.changeOpAdd,
    remove => S.current.changeOpRemove,
  };
}

/// One side of a staged change (what was there, what will be) as its
/// review card shows it: data as it is, or Studio's own words for it.
sealed class ChangeSideVm extends Equatable {
  const ChangeSideVm();

  /// Data as it is: a value, a wire name, a list of them.
  const factory ChangeSideVm.text(String text) = ChangeSideTextVm;

  /// Nothing to show.
  const factory ChangeSideVm.none() = ChangeSideNoneVm;

  /// The revision [rev] of a link's params.
  const factory ChangeSideVm.rev(int rev) = ChangeSideRevVm;

  /// Some params of a link as they are on this side, of the revision
  /// [rev] when the side is what was there.
  const factory ChangeSideVm.params(List<ParamSideVm> values, {int? rev}) =
      ChangeSideParamsVm;

  /// A switch: on or off.
  const factory ChangeSideVm.flag({required bool on}) = ChangeSideFlagVm;

  /// A JSON object of [count] top-level keys.
  const factory ChangeSideVm.keys(int count) = ChangeSideKeysVm;

  /// What the card writes.
  String get text;
}

final class ChangeSideTextVm extends ChangeSideVm {
  const ChangeSideTextVm(this.text);

  @override
  final String text;

  @override
  List<Object?> get props => [text];
}

final class ChangeSideNoneVm extends ChangeSideVm {
  const ChangeSideNoneVm();

  @override
  String get text => '—';

  @override
  List<Object?> get props => const [];
}

final class ChangeSideRevVm extends ChangeSideVm {
  const ChangeSideRevVm(this.rev);

  final int rev;

  @override
  String get text => S.current.changeRev(rev);

  @override
  List<Object?> get props => [rev];
}

/// One param on one side of a change: its wire name and what it holds: a
/// text, a list, or neither (not set).
final class ParamSideVm extends Equatable {
  const ParamSideVm(this.name, {this.value, this.list});

  final String name;
  final String? value;
  final List<String>? list;

  /// `require_approval write`, `allowed_prefixes A, B`, `x []`, `y —`.
  String get text => switch ((value, list)) {
    (final v?, _) => '$name $v',
    (null, final l?) => '$name ${l.isEmpty ? '[]' : l.join(', ')}',
    (null, null) => '$name —',
  };

  @override
  List<Object?> get props => [name, value, list];
}

final class ChangeSideParamsVm extends ChangeSideVm {
  const ChangeSideParamsVm(this.values, {this.rev});

  final List<ParamSideVm> values;
  final int? rev;

  /// The names of the params that change: `require_approval, x`.
  String get names => [for (final v in values) v.name].join(', ');

  @override
  String get text {
    final detail = [for (final v in values) v.text].join('; ');
    return switch (rev) {
      final r? => S.current.changeRevOf(r, detail),
      null => detail,
    };
  }

  @override
  List<Object?> get props => [values, rev];
}

final class ChangeSideFlagVm extends ChangeSideVm {
  const ChangeSideFlagVm({required this.on});

  final bool on;

  @override
  String get text => on ? S.current.changeOn : S.current.changeOff;

  @override
  List<Object?> get props => [on];
}

final class ChangeSideKeysVm extends ChangeSideVm {
  const ChangeSideKeysVm(this.count);

  final int count;

  @override
  String get text => S.current.changeKeys(count);

  @override
  List<Object?> get props => [count];
}

/// What one line of a step-up does (board `UnlockStepUp`), said in the
/// language shown. A name (a value, an action, a user) is data.
sealed class StepUpDeedVm extends Equatable {
  const StepUpDeedVm();

  /// A `set` of the value [name].
  const factory StepUpDeedVm.set(String name) = StepUpSetVm;

  /// An action, by its own name.
  const factory StepUpDeedVm.action(String name) = StepUpActionVm;

  /// A staged change being applied.
  const factory StepUpDeedVm.change({
    required ChangeOpTag op,
    required String field,
    required ChangeSideVm to,
  }) = StepUpChangeVm;

  /// A change of the gateway's users or devices.
  const factory StepUpDeedVm.account(StepUpAccount what, [String name]) =
      StepUpAccountVm;

  /// What the line says.
  String get text;
}

final class StepUpSetVm extends StepUpDeedVm {
  const StepUpSetVm(this.name);

  final String name;

  @override
  String get text => S.current.stepUpSet(name);

  @override
  List<Object?> get props => [name];
}

final class StepUpActionVm extends StepUpDeedVm {
  const StepUpActionVm(this.name);

  final String name;

  @override
  String get text => name;

  @override
  List<Object?> get props => [name];
}

final class StepUpChangeVm extends StepUpDeedVm {
  const StepUpChangeVm({
    required this.op,
    required this.field,
    required this.to,
  });

  final ChangeOpTag op;
  final String field;
  final ChangeSideVm to;

  @override
  String get text =>
      S.current.stepUpChange(op.label.toLowerCase(), field, to.text);

  @override
  List<Object?> get props => [op, field, to];
}

/// A change of the gateway's users or devices a step-up confirms.
enum StepUpAccount {
  addUser,
  removeUser,
  setRoles,
  setPassword,
  disableUser,
  enableUser,
  removeDevice,
}

final class StepUpAccountVm extends StepUpDeedVm {
  const StepUpAccountVm(this.what, [this.name = '']);

  final StepUpAccount what;

  /// The user it is about; empty for a device.
  final String name;

  @override
  String get text => switch (what) {
    StepUpAccount.addUser => S.current.stepUpAddUser(name),
    StepUpAccount.removeUser => S.current.stepUpRemoveUser(name),
    StepUpAccount.setRoles => S.current.stepUpSetRoles(name),
    StepUpAccount.setPassword => S.current.stepUpSetPassword(name),
    StepUpAccount.disableUser => S.current.stepUpDisableUser(name),
    StepUpAccount.enableUser => S.current.stepUpEnableUser(name),
    StepUpAccount.removeDevice => S.current.stepUpRemoveDevice,
  };

  @override
  List<Object?> get props => [what, name];
}
