import 'package:freezed_annotation/freezed_annotation.dart';

import 'manifest_problem.dart';
import 'package_manifest.dart';

part 'package_manifest_read.freezed.dart';

/// What reading the bytes of a `wyrm-link.json` gives.
@freezed
sealed class PackageManifestRead with _$PackageManifestRead {
  /// The manifest, with each field the checks look at.
  const factory PackageManifestRead.read(PackageManifest manifest) =
      PackageManifestWasRead;

  /// The bytes are no manifest: not JSON, or JSON that is no object.
  const factory PackageManifestRead.unreadable(ManifestProblem problem) =
      PackageManifestUnreadable;
}
