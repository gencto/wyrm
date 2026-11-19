import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'manifest_problem.dart';
import 'package_kind.dart';
import 'requested_right.dart';
import 'stated.dart';

part 'package_manifest.freezed.dart';

@freezed
abstract class PackageManifest with _$PackageManifest {
  /// The manifest of a package (`wyrm-link.json`), read once for the
  /// checks of docs/links.md §4: each field the checks look at with its
  /// type, so a check says what is wrong with the file instead of reading
  /// it again.
  const factory PackageManifest({
    /// The manifest as indented JSON.
    required String pretty,

    /// The fields the format does not have.
    required IList<String> unknown,
    required Stated<String> name,
    required Stated<String> version,

    /// `wyrm_link`.
    required Stated<int> protocol,

    /// `process` or `wasm`; any other name is wrong.
    required Stated<PackageKind> kind,

    /// `entry` of a WASM package.
    required Stated<String> entry,

    /// `entries` of a process package: the file of each host (`os-arch`),
    /// null for an entry that is not a text. Null when the manifest has no
    /// map of entries.
    IMap<String, String?>? entries,

    /// What the package asks for (`capabilities`, `requester`); empty
    /// when [rightsProblem] says they could not be read.
    @Default(IListConst([])) IList<RequestedRight> rights,
    ManifestProblem? rightsProblem,
  }) = _PackageManifest;
}
