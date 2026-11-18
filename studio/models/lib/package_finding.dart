import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'backup_link_facts.dart';
import 'backup_sealed.dart';
import 'backup_section.dart';
import 'manifest_problem.dart';
import 'requested_right.dart';

part 'package_finding.freezed.dart';

/// What one check of a package, a component or a link backup found
/// (docs/links.md §4), as facts: which check it is and what it saw. `ui`
/// says each in the language on screen; nothing here is worded.
@freezed
sealed class PackageFinding with _$PackageFinding {
  /// The file is larger than the limit ([zipped]: a zip, measured packed).
  const factory PackageFinding.tooLarge({
    required int mib,
    required int limitMib,
    required bool zipped,
  }) = FindingTooLarge;

  /// The file is no zip; [error] is the reader's own word of it, if any.
  const factory PackageFinding.notZip({String? error}) = FindingNotZip;

  /// More files or more bytes unpacked than a package may have.
  const factory PackageFinding.tooManyFiles({
    required int files,
    required int mib,
    required int maxFiles,
    required int maxMib,
  }) = FindingTooManyFiles;

  /// The zip's size and how many files it holds.
  const factory PackageFinding.sizeAndFiles({
    required int kib,
    required int files,
  }) = FindingSizeAndFiles;

  /// The size of one file.
  const factory PackageFinding.size({required int kib}) = FindingSize;

  /// The archive opened: how many entries it has.
  const factory PackageFinding.archiveEntries(int count) =
      FindingArchiveEntries;

  /// A path of the zip is not relative.
  const factory PackageFinding.pathNotRelative(String path) =
      FindingPathNotRelative;

  /// The zip holds a symbolic link.
  const factory PackageFinding.symbolicLink(String name) = FindingSymbolicLink;

  /// Every path is relative, and none is a link.
  const factory PackageFinding.pathsOk() = FindingPathsOk;

  /// The archive has no manifest [file].
  const factory PackageFinding.noManifest(String file) = FindingNoManifest;

  /// The manifest [file] cannot be read.
  const factory PackageFinding.manifestProblem(
    ManifestProblem problem,
    String file,
  ) = FindingManifestProblem;

  /// The manifest has fields the format does not.
  const factory PackageFinding.unknownFields(IList<String> fields) =
      FindingUnknownFields;

  /// Fields the format needs are missing or of another form.
  const factory PackageFinding.missingFields(IList<String> fields) =
      FindingMissingFields;

  /// The manifest [file] is of its form.
  const factory PackageFinding.manifestOk(String file) = FindingManifestOk;

  /// The link protocol the manifest names ([found]: as the file writes
  /// it, null when it names none) against the one the brokers [speak].
  const factory PackageFinding.protocol({
    required String? found,
    required int speak,
    required bool matches,
  }) = FindingProtocol;

  /// The package's name and version, and whether both are of their form.
  const factory PackageFinding.nameVersion({
    required String name,
    required String? version,
    required bool ok,
  }) = FindingNameVersion;

  /// The hosts whose entry file is not in the zip.
  const factory PackageFinding.entryMissing(IList<String> hosts) =
      FindingEntryMissing;

  /// The hosts the package has binaries for.
  const factory PackageFinding.hosts(IList<String> hosts) = FindingHosts;

  /// A process package without entries per host.
  const factory PackageFinding.needsEntries() = FindingNeedsEntries;

  /// Whether the package has an entry for the broker's [host].
  const factory PackageFinding.host(String host, {required bool present}) =
      FindingHost;

  /// The component of a WASM package ([entry]: its file, null for a bare
  /// component or when the manifest names none): whether it is in the
  /// zip, and whether it is WebAssembly.
  const factory PackageFinding.component({
    required String? entry,
    required bool found,
    required bool wasm,
  }) = FindingComponent;

  /// The world is read from the component by the broker.
  const factory PackageFinding.worldByBroker() = FindingWorldByBroker;

  /// The rights the package asks for.
  const factory PackageFinding.rights(IList<RequestedRight> rights) =
      FindingRights;

  /// The rights of the manifest [file] cannot be read.
  const factory PackageFinding.rightsProblem(
    ManifestProblem problem,
    String file,
  ) = FindingRightsProblem;

  /// A backup that is not of one link, by its `kind`.
  const factory PackageFinding.otherKind(String kind) = FindingOtherKind;

  /// The link of a link backup, and where and when it was made.
  const factory PackageFinding.link(BackupLinkFacts link) = FindingLink;

  /// The package the link runs, and whether the file carries it.
  const factory PackageFinding.packageOfLink({
    required String name,
    required String version,
    required bool inFile,
  }) = FindingPackageOfLink;

  /// How the secrets of the backup are sealed ([site]: the site a
  /// broker's seal is for).
  const factory PackageFinding.secrets(BackupSealed sealed, String site) =
      FindingSecrets;

  /// The sections of the backup.
  const factory PackageFinding.sections(IList<BackupSection> sections) =
      FindingSections;

  /// The definition, the grants and the package files are checked by the
  /// broker as a new link.
  const factory PackageFinding.checkedAsNewLink() = FindingCheckedAsNewLink;

  /// The file is too large to read here: the broker alone checks it.
  const factory PackageFinding.notReadHere({required int mib}) =
      FindingNotReadHere;

  /// What is fetched by the broker ([what]: its address; null when the
  /// source names none).
  const factory PackageFinding.fetchedByBroker(String? what) =
      FindingFetchedByBroker;

  /// The archive, the manifest and the binaries are checked by the broker
  /// after the download.
  const factory PackageFinding.checkedAfterDownload() =
      FindingCheckedAfterDownload;
}
