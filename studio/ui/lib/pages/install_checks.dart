import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../models/link_run_mode.dart';
import '../overlays/backup_data.dart';
import 'link_install_data.dart';

// What one check of a package, a component or a link backup found, as
// `ui` draws it: each finding names its check ([CheckFinding.title]) and
// says what it saw ([CheckFinding.line]) in the language on screen, from
// typed values. Nothing arrives here as a sentence.

/// The kinds of fault of a manifest a person brought.
enum ManifestFaultKind { notJson, notObject, missing, wrongForm, unknownName }

/// What is wrong with a manifest: the kind, the [file] it is of, the
/// field at fault (empty: the file itself) and what the file holds there.
final class ManifestProblemVm extends Equatable {
  const ManifestProblemVm({
    required this.kind,
    required this.file,
    this.field = '',
    this.found,
  });

  final ManifestFaultKind kind;
  final String file;
  final String field;
  final String? found;

  /// The sentence of the check.
  String get line => switch (kind) {
    ManifestFaultKind.notJson => S.current.chkNotJson(file),
    ManifestFaultKind.notObject =>
      field.isEmpty
          ? S.current.chkNotObject(file)
          : S.current.chkWrongForm(field),
    ManifestFaultKind.missing => S.current.chkMissing(field),
    ManifestFaultKind.wrongForm => S.current.chkWrongForm(field),
    ManifestFaultKind.unknownName => S.current.chkUnknownName(
      field,
      found ?? '',
    ),
  };

  @override
  List<Object?> get props => [kind, file, field, found];
}

/// The link of a link backup, and where and when the backup was made.
final class BackupLinkVm extends Equatable {
  const BackupLinkVm({
    required this.id,
    required this.mode,
    required this.driver,
    required this.site,
    required this.broker,
    required this.created,
  });

  final String id;
  final LinkRunMode mode;
  final String driver;
  final String site;
  final String broker;
  final DateTime created;

  /// The sentence of the check.
  String get line => S.current.chkLinkFrom(
    id,
    mode.label,
    driver,
    site,
    broker,
    Formats.dateTime(created),
  );

  @override
  List<Object?> get props => [id, mode, driver, site, broker, created];
}

/// What a check found.
sealed class CheckFinding extends Equatable {
  const CheckFinding();

  /// The name of the check.
  String get title;

  /// What it found.
  String get line;
}

final class TooLargeFinding extends CheckFinding {
  const TooLargeFinding({
    required this.mib,
    required this.limitMib,
    required this.zipped,
  });

  final int mib;
  final int limitMib;
  final bool zipped;

  @override
  String get title => S.current.chkSize;

  @override
  String get line => zipped
      ? S.current.chkTooLargeZipped(mib, limitMib)
      : S.current.chkTooLarge(mib, limitMib);

  @override
  List<Object?> get props => [mib, limitMib, zipped];
}

final class NotZipFinding extends CheckFinding {
  const NotZipFinding({this.error});

  final String? error;

  @override
  String get title => S.current.chkArchive;

  @override
  String get line => switch (error) {
    final e? => S.current.chkNotZipBecause(e),
    null => S.current.chkNotZip,
  };

  @override
  List<Object?> get props => [error];
}

final class TooManyFilesFinding extends CheckFinding {
  const TooManyFilesFinding({
    required this.files,
    required this.mib,
    required this.maxFiles,
    required this.maxMib,
  });

  final int files;
  final int mib;
  final int maxFiles;
  final int maxMib;

  @override
  String get title => S.current.chkSizeAndFiles;

  @override
  String get line => S.current.chkTooManyFiles(files, mib, maxFiles, maxMib);

  @override
  List<Object?> get props => [files, mib, maxFiles, maxMib];
}

final class SizeAndFilesFinding extends CheckFinding {
  const SizeAndFilesFinding({required this.kib, required this.files});

  final int kib;
  final int files;

  @override
  String get title => S.current.chkSizeAndFiles;

  @override
  String get line => S.current.chkKibAndFiles(kib, files);

  @override
  List<Object?> get props => [kib, files];
}

final class SizeFinding extends CheckFinding {
  const SizeFinding({required this.kib});

  final int kib;

  @override
  String get title => S.current.chkSize;

  @override
  String get line => S.current.chkKib(kib);

  @override
  List<Object?> get props => [kib];
}

final class ArchiveEntriesFinding extends CheckFinding {
  const ArchiveEntriesFinding(this.count);

  final int count;

  @override
  String get title => S.current.chkArchive;

  @override
  String get line => S.current.chkEntries(count);

  @override
  List<Object?> get props => [count];
}

/// The paths of a zip: one that is not relative, a symbolic link, or
/// neither.
final class PathsFinding extends CheckFinding {
  const PathsFinding({this.notRelative, this.symbolicLink});

  final String? notRelative;
  final String? symbolicLink;

  @override
  String get title => S.current.chkPaths;

  @override
  String get line => switch ((notRelative, symbolicLink)) {
    (final p?, _) => S.current.chkPathNotRelative(p),
    (null, final l?) => S.current.chkSymbolicLink(l),
    (null, null) => S.current.chkPathsOk,
  };

  @override
  List<Object?> get props => [notRelative, symbolicLink];
}

final class NoManifestFinding extends CheckFinding {
  const NoManifestFinding(this.file);

  final String file;

  @override
  String get title => S.current.chkManifest;

  @override
  String get line => S.current.chkNoManifest(file);

  @override
  List<Object?> get props => [file];
}

/// A manifest, or the rights it asks for ([ofRights]), that cannot be
/// read.
final class ManifestProblemFinding extends CheckFinding {
  const ManifestProblemFinding(this.problem, {this.ofRights = false});

  final ManifestProblemVm problem;
  final bool ofRights;

  @override
  String get title =>
      ofRights ? S.current.chkRightsAsked : S.current.chkManifest;

  @override
  String get line => problem.line;

  @override
  List<Object?> get props => [problem, ofRights];
}

/// Fields of a manifest the format does not have ([unknown]), or that it
/// needs and are missing or of another form.
final class ManifestFieldsFinding extends CheckFinding {
  const ManifestFieldsFinding(this.fields, {required this.unknown});

  final List<String> fields;
  final bool unknown;

  @override
  String get title => S.current.chkManifest;

  @override
  String get line => unknown
      ? S.current.chkUnknownFields(fields.join(', '))
      : S.current.chkMissingFields(fields.join(', '));

  @override
  List<Object?> get props => [fields, unknown];
}

final class ManifestOkFinding extends CheckFinding {
  const ManifestOkFinding(this.file);

  final String file;

  @override
  String get title => S.current.chkManifest;

  /// The name of the file is not a word of any language.
  @override
  String get line => file;

  @override
  List<Object?> get props => [file];
}

final class ProtocolFinding extends CheckFinding {
  const ProtocolFinding({
    required this.found,
    required this.speak,
    required this.matches,
  });

  final String? found;
  final int speak;
  final bool matches;

  @override
  String get title => S.current.chkProtocol;

  @override
  String get line => matches
      ? S.current.chkProtocolOk(speak)
      : S.current.chkProtocolOther(found ?? S.current.chkNone, speak);

  @override
  List<Object?> get props => [found, speak, matches];
}

final class NameVersionFinding extends CheckFinding {
  const NameVersionFinding({
    required this.name,
    required this.version,
    required this.ok,
  });

  final String name;
  final String? version;
  final bool ok;

  @override
  String get title => S.current.chkNameVersion;

  @override
  String get line => ok
      ? '$name $version'
      : S.current.chkNameVersionBad(name, version ?? S.current.chkNone);

  @override
  List<Object?> get props => [name, version, ok];
}

/// The binaries of a process package: the hosts it has them for, those
/// whose entry file is [missing], or no entries at all (both empty).
final class BinariesFinding extends CheckFinding {
  const BinariesFinding({this.hosts = const [], this.missing = const []});

  final List<String> hosts;
  final List<String> missing;

  @override
  String get title => S.current.chkBinaries;

  @override
  String get line => missing.isNotEmpty
      ? S.current.chkEntryMissing(missing.join(', '))
      : (hosts.isEmpty ? S.current.chkNeedsEntries : hosts.join(', '));

  @override
  List<Object?> get props => [hosts, missing];
}

final class HostFinding extends CheckFinding {
  const HostFinding(this.host, {required this.present});

  final String host;
  final bool present;

  @override
  String get title => S.current.chkThisHost;

  @override
  String get line => present ? host : S.current.chkNoEntryFor(host);

  @override
  List<Object?> get props => [host, present];
}

final class ComponentFinding extends CheckFinding {
  const ComponentFinding({
    required this.entry,
    required this.found,
    required this.wasm,
  });

  /// The component's file; null for a bare component, or when the
  /// manifest names none.
  final String? entry;
  final bool found;
  final bool wasm;

  @override
  String get title => S.current.chkComponent;

  @override
  String get line {
    if (!found) {
      return S.current.chkComponentMissing(entry ?? S.current.chkNone);
    }
    return switch ((entry, wasm)) {
      (final e?, true) => e,
      (null, true) => S.current.chkWasm,
      (final e?, false) => S.current.chkNotWasmFile(e),
      (null, false) => S.current.chkNotWasm,
    };
  }

  @override
  List<Object?> get props => [entry, found, wasm];
}

final class WorldByBrokerFinding extends CheckFinding {
  const WorldByBrokerFinding();

  @override
  String get title => S.current.chkWorld;

  @override
  String get line => S.current.chkWorldByBroker;

  @override
  List<Object?> get props => [];
}

final class RightsFinding extends CheckFinding {
  const RightsFinding(this.rights);

  final List<InstallRightVm> rights;

  @override
  String get title => S.current.chkRightsAsked;

  @override
  String get line => rights.isEmpty
      ? S.current.rightsNone
      : [for (final x in rights) x.line].join('; ');

  @override
  List<Object?> get props => [rights];
}

final class OtherKindFinding extends CheckFinding {
  const OtherKindFinding(this.kind);

  /// The broker's name of the kind of the backup.
  final String kind;

  @override
  String get title => S.current.chkKind;

  @override
  String get line => S.current.chkOtherKind(kind);

  @override
  List<Object?> get props => [kind];
}

final class LinkFinding extends CheckFinding {
  const LinkFinding(this.link);

  final BackupLinkVm link;

  @override
  String get title => S.current.chkLink;

  @override
  String get line => link.line;

  @override
  List<Object?> get props => [link];
}

final class PackageOfLinkFinding extends CheckFinding {
  const PackageOfLinkFinding({
    required this.name,
    required this.version,
    required this.inFile,
  });

  final String name;
  final String version;
  final bool inFile;

  @override
  String get title => S.current.chkPackage;

  @override
  String get line => inFile
      ? S.current.chkPackageInFile(name, version)
      : S.current.chkPackageNotInFile(name, version);

  @override
  List<Object?> get props => [name, version, inFile];
}

final class SecretsFinding extends CheckFinding {
  const SecretsFinding(this.seal, this.site);

  final BackupSeal seal;
  final String site;

  @override
  String get title => S.current.chkSecrets;

  @override
  String get line => switch (seal) {
    BackupSeal.passphrase => S.current.chkSealedPassphrase,
    BackupSeal.broker => S.current.chkSealedForSite(site),
    BackupSeal.none => S.current.chkNoSecrets,
  };

  @override
  List<Object?> get props => [seal, site];
}

final class SectionsFinding extends CheckFinding {
  const SectionsFinding(this.sections);

  final List<BackupPart> sections;

  @override
  String get title => S.current.chkSections;

  @override
  String get line => [for (final s in sections) s.label].join(', ');

  @override
  List<Object?> get props => [sections];
}

final class CheckedAsNewLinkFinding extends CheckFinding {
  const CheckedAsNewLinkFinding();

  @override
  String get title => S.current.chkLinkParts;

  @override
  String get line => S.current.chkAsNewLink;

  @override
  List<Object?> get props => [];
}

final class NotReadHereFinding extends CheckFinding {
  const NotReadHereFinding({required this.mib});

  final int mib;

  @override
  String get title => S.current.chkBackupParts;

  @override
  String get line => S.current.chkNotReadHere(mib);

  @override
  List<Object?> get props => [mib];
}

final class FetchedByBrokerFinding extends CheckFinding {
  const FetchedByBrokerFinding(this.what);

  /// The address; null when the source names none.
  final String? what;

  @override
  String get title => S.current.chkDownload;

  @override
  String get line => switch (what) {
    final w? => S.current.chkFetched(w),
    null => S.current.chkFetchedIt,
  };

  @override
  List<Object?> get props => [what];
}

final class CheckedAfterDownloadFinding extends CheckFinding {
  const CheckedAfterDownloadFinding();

  @override
  String get title => S.current.chkRemoteParts;

  @override
  String get line => S.current.chkAfterDownload;

  @override
  List<Object?> get props => [];
}
