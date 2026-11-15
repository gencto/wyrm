import 'dart:async';

import 'package:equatable/equatable.dart';

import '../forms/action_form.dart';

/// A form's submit and whether it runs: [busy] is drawn and in [props];
/// [onSubmit] is behaviour and is not (the rule of `value_changed.dart`).
final class SubmitVm extends Equatable {
  const SubmitVm({required this.onSubmit, this.busy = false});

  // Written out, not [FormSubmit]: `frx doctor` reads only Flutter's own
  // callback typedefs as behaviour in a view-model.
  final FutureOr<FieldRefusal?> Function(Map<String, Object?> values) onSubmit;
  final bool busy;

  @override
  List<Object?> get props => [busy];
}
