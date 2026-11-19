import 'package:freezed_annotation/freezed_annotation.dart';

import 'manifest_problem.dart';
import 'profile_draft.dart';

part 'profile_read.freezed.dart';

/// What reading the bytes of a profile's JSON file gives.
@freezed
sealed class ProfileRead with _$ProfileRead {
  /// The profile, each field of its type.
  const factory ProfileRead.read(ProfileDraft draft) = ProfileWasRead;

  /// The file is no profile, and why: which field, which name.
  const factory ProfileRead.unreadable(ManifestProblem problem) =
      ProfileUnreadable;
}
