import 'package:freezed_annotation/freezed_annotation.dart';

part 'approval_refusal.freezed.dart';

/// Why the last approval of a task's plan was refused; the task still
/// waits. Kept for its card (`assistant.refusals`); `ui` says it.
@freezed
sealed class ApprovalRefusal with _$ApprovalRefusal {
  /// Studio sent nothing: the plan or its ticks changed after they were
  /// shown, and the person approves what is shown.
  const factory ApprovalRefusal.changed() = ApprovalRefusalChanged;

  /// Studio sent nothing: the arguments of step [step] are masked (their
  /// schema is not known) and were not looked at.
  const factory ApprovalRefusal.unseen(int step) = ApprovalRefusalUnseen;

  /// The gateway or the link refused, in its own words ([message]).
  const factory ApprovalRefusal.said(String message) = ApprovalRefusalSaid;
}
