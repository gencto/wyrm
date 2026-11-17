import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'backup_link_facts.dart';
import 'backup_sealed.dart';
import 'backup_section.dart';
import 'manifest_problem.dart';

part 'backup_manifest.freezed.dart';

/// What the `manifest.json` of a backup file says it is.
@freezed
sealed class BackupManifest with _$BackupManifest {
  /// The manifest of a link backup (`.wyrm-link`, ADR 0048 §3.1,
  /// `Manifest` of `wyrm-admin`): what Studio shows of it before the
  /// broker checks all of it.
  const factory BackupManifest.link({
    /// `wyrm_backup`: the version of the format.
    required int format,

    /// The link, and where and when the backup was made.
    required BackupLinkFacts link,
    required BackupSealed sealed,

    /// The package the link runs (empty: a built-in driver) and its
    /// version.
    required String package,
    required String version,
    required IList<BackupSection> sections,

    /// The manifest as indented JSON, without its files and seals: its
    /// `link` as the file writes it.
    required String pretty,
  }) = LinkBackupManifest;

  /// A backup that is not of one link (a broker backup): its `kind`.
  const factory BackupManifest.other(String kind) = OtherBackupManifest;

  /// A manifest Studio cannot read: a field that is missing or of another
  /// form, or a mode, a seal or a section it does not know.
  const factory BackupManifest.unreadable(ManifestProblem problem) =
      UnreadableBackupManifest;
}
