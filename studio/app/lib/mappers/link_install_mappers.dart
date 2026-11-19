import 'package:business/wyrm/catalog.dart';
import 'package:business/wyrm/search.dart';
import 'package:models/catalog_category.dart';
import 'package:models/catalog_item.dart';
import 'package:models/install_block.dart';
import 'package:models/install_field.dart';
import 'package:models/install_name_problem.dart';
import 'package:models/install_path.dart';
import 'package:models/install_phase.dart';
import 'package:models/install_step.dart';
import 'package:models/known_link.dart';
import 'package:models/link_category.dart';
import 'package:models/link_mode.dart';
import 'package:models/manifest_fault.dart';
import 'package:models/manifest_problem.dart';
import 'package:models/package_check.dart';
import 'package:models/package_check_result.dart';
import 'package:models/package_finding.dart';
import 'package:models/package_method.dart';
import 'package:models/requested_right.dart';
import 'package:ui/containers/catalog_card.dart';
import 'package:ui/containers/catalog_words.dart';
import 'package:ui/indicators/check_list.dart';
import 'package:ui/models/broker_said.dart';
import 'package:ui/models/link_run_mode.dart';
import 'package:ui/pages/install_checks.dart';
import 'package:ui/pages/link_install_data.dart';

import 'backup_mappers.dart';
import 'rights_mappers.dart';

// Add a link: one exhaustive map per domain enum to the `ui` enum that
// draws it, both ways where a control reports a `ui` value back
// (studio-rules §3).

extension InstallPathUi on InstallPath {
  InstallFrom get ui => switch (this) {
    InstallPath.official => InstallFrom.official,
    InstallPath.custom => InstallFrom.custom,
    InstallPath.backup => InstallFrom.backup,
  };
}

extension InstallFromDomain on InstallFrom {
  InstallPath get domain => switch (this) {
    InstallFrom.official => InstallPath.official,
    InstallFrom.custom => InstallPath.custom,
    InstallFrom.backup => InstallPath.backup,
  };
}

extension PackageMethodUi on PackageMethod {
  InstallMethod get ui => switch (this) {
    PackageMethod.zip => InstallMethod.zip,
    PackageMethod.url => InstallMethod.url,
    PackageMethod.git => InstallMethod.git,
    PackageMethod.wasm => InstallMethod.wasm,
  };
}

extension InstallMethodDomain on InstallMethod {
  PackageMethod get domain => switch (this) {
    InstallMethod.zip => PackageMethod.zip,
    InstallMethod.url => PackageMethod.url,
    InstallMethod.git => PackageMethod.git,
    InstallMethod.wasm => PackageMethod.wasm,
  };
}

extension InstallStepUi on InstallStep {
  InstallStepKey get ui => switch (this) {
    InstallStep.choose => InstallStepKey.choose,
    InstallStep.check => InstallStepKey.check,
    InstallStep.run => InstallStepKey.run,
    InstallStep.result => InstallStepKey.result,
  };
}

extension InstallStepKeyDomain on InstallStepKey {
  InstallStep get domain => switch (this) {
    InstallStepKey.choose => InstallStep.choose,
    InstallStepKey.check => InstallStep.check,
    InstallStepKey.run => InstallStep.run,
    InstallStepKey.result => InstallStep.result,
  };
}

extension LinkModeUi on LinkMode {
  LinkRunMode get ui => switch (this) {
    LinkMode.embedded => LinkRunMode.embedded,
    LinkMode.process => LinkRunMode.process,
    LinkMode.external => LinkRunMode.external,
    LinkMode.wasm => LinkRunMode.wasm,
  };
}

extension LinkRunModeDomain on LinkRunMode {
  LinkMode get domain => switch (this) {
    LinkRunMode.embedded => LinkMode.embedded,
    LinkRunMode.process => LinkMode.process,
    LinkRunMode.external => LinkMode.external,
    LinkRunMode.wasm => LinkMode.wasm,
  };
}

extension InstallPhaseUi on InstallPhase {
  InstallResult get ui => switch (this) {
    InstallPhase.installing => InstallResult.installing,
    InstallPhase.done => InstallResult.done,
    InstallPhase.failed => InstallResult.failed,
  };
}

extension InstallFieldUi on InstallField {
  InstallText get ui => switch (this) {
    InstallField.name => InstallText.name,
    InstallField.url => InstallText.url,
    InstallField.git => InstallText.git,
    InstallField.ref => InstallText.ref,
  };
}

extension InstallNameProblemUi on InstallNameProblem {
  InstallNameError get ui => switch (this) {
    InstallNameProblem.rule => InstallNameError.rule,
    InstallNameProblem.taken => InstallNameError.taken,
    InstallNameProblem.refused => InstallNameError.refused,
  };
}

extension InstallBlockUi on InstallBlock {
  InstallHold get ui => switch (this) {
    InstallBlock.pickOne => InstallHold.pickOne,
    InstallBlock.bringOne => InstallHold.bringOne,
    InstallBlock.checkFailed => InstallHold.checkFailed,
    InstallBlock.nameIt => InstallHold.nameIt,
    InstallBlock.nameProblem => InstallHold.nameProblem,
    InstallBlock.acceptFirst => InstallHold.acceptFirst,
    InstallBlock.needsConfig => InstallHold.needsConfig,
  };
}

extension PackageCheckUi on PackageCheck {
  InstallCheckVm get row => InstallCheckVm(
    finding: finding.ui,
    result: switch (result) {
      PackageCheckResult.ok => CheckResult.ok,
      PackageCheckResult.failed => CheckResult.failed,
      PackageCheckResult.skipped => CheckResult.skipped,
    },
  );
}

extension ManifestProblemUi on ManifestProblem {
  /// The problem of the manifest [file] as `ui` says it.
  ManifestProblemVm ui(String file) => ManifestProblemVm(
    kind: fault.ui,
    file: file,
    field: field,
    found: found,
    offset: offset,
  );
}

extension PackageFindingUi on PackageFinding {
  /// The finding as `ui` names and says it.
  CheckFinding get ui => switch (this) {
    FindingTooLarge(:final mib, :final limitMib, :final zipped) =>
      TooLargeFinding(mib: mib, limitMib: limitMib, zipped: zipped),
    FindingNotZip() => const NotZipFinding(),
    FindingTooManyFiles(
      :final files,
      :final mib,
      :final maxFiles,
      :final maxMib,
    ) =>
      TooManyFilesFinding(
        files: files,
        mib: mib,
        maxFiles: maxFiles,
        maxMib: maxMib,
      ),
    FindingSizeAndFiles(:final kib, :final files) => SizeAndFilesFinding(
      kib: kib,
      files: files,
    ),
    FindingSize(:final kib) => SizeFinding(kib: kib),
    FindingArchiveEntries(:final count) => ArchiveEntriesFinding(count),
    FindingPathNotRelative(:final path) => PathsFinding(notRelative: path),
    FindingSymbolicLink(:final name) => PathsFinding(symbolicLink: name),
    FindingPathsOk() => const PathsFinding(),
    FindingNoManifest(:final file) => NoManifestFinding(file),
    FindingManifestProblem(:final problem, :final file) =>
      ManifestProblemFinding(problem.ui(file)),
    FindingUnknownFields(:final fields) => ManifestFieldsFinding(
      fields.unlock,
      unknown: true,
    ),
    FindingMissingFields(:final fields) => ManifestFieldsFinding(
      fields.unlock,
      unknown: false,
    ),
    FindingManifestOk(:final file) => ManifestOkFinding(file),
    FindingProtocol(:final found, :final speak, :final matches) =>
      ProtocolFinding(found: found, speak: speak, matches: matches),
    FindingNameVersion(:final name, :final version, :final ok) =>
      NameVersionFinding(name: name, version: version, ok: ok),
    FindingEntryMissing(:final hosts) => BinariesFinding(
      missing: hosts.unlock,
    ),
    FindingHosts(:final hosts) => BinariesFinding(hosts: hosts.unlock),
    FindingNeedsEntries() => const BinariesFinding(),
    FindingHost(:final host, :final present) => HostFinding(
      host,
      present: present,
    ),
    FindingComponent(:final entry, :final found, :final wasm) =>
      ComponentFinding(entry: entry, found: found, wasm: wasm),
    FindingWorldByBroker() => const WorldByBrokerFinding(),
    FindingRights(:final rights) => RightsFinding([
      for (final x in rights) x.ui,
    ]),
    FindingRightsProblem(:final problem, :final file) => ManifestProblemFinding(
      problem.ui(file),
      ofRights: true,
    ),
    FindingOtherKind(:final kind) => OtherKindFinding(kind),
    FindingLink(:final link) => LinkFinding(
      BackupLinkVm(
        id: link.id,
        mode: link.mode.ui,
        driver: link.driver,
        site: link.site,
        broker: link.broker,
        created: link.created,
      ),
    ),
    FindingPackageOfLink(:final name, :final version, :final inFile) =>
      PackageOfLinkFinding(name: name, version: version, inFile: inFile),
    FindingSecrets(:final sealed, :final site) => SecretsFinding(
      sealed.seal,
      site,
    ),
    FindingSections(:final sections) => SectionsFinding([
      for (final s in sections) s.part,
    ]),
    FindingCheckedAsNewLink() => const CheckedAsNewLinkFinding(),
    FindingNotReadHere(:final mib) => NotReadHereFinding(mib: mib),
    FindingFetchedByBroker(:final what) => FetchedByBrokerFinding(what),
    FindingCheckedAfterDownload() => const CheckedAfterDownloadFinding(),
  };
}

extension ManifestFaultUi on ManifestFault {
  ManifestFaultKind get ui => switch (this) {
    ManifestFault.notJson => ManifestFaultKind.notJson,
    ManifestFault.tooDeep => ManifestFaultKind.tooDeep,
    ManifestFault.notObject => ManifestFaultKind.notObject,
    ManifestFault.unknownField => ManifestFaultKind.unknownField,
    ManifestFault.missing => ManifestFaultKind.missing,
    ManifestFault.wrongForm => ManifestFaultKind.wrongForm,
    ManifestFault.unknownName => ManifestFaultKind.unknownName,
  };
}

extension RequestedRightUi on RequestedRight {
  InstallRightVm get ui => switch (this) {
    RightNetwork(:final hosts) => NetworkRightVm(hosts),
    RightStore(:final mib) => SizeRightVm(mib, store: true),
    RightMemory(:final mib) => SizeRightVm(mib, store: false),
    RightCall(:final ms) => CallRightVm(ms),
    RightGrant(:final level, :final path) => GrantRightVm(level.access, path),
  };
}

extension KnownLinkWords on KnownLink {
  /// The driver as `ui` words it.
  LinkWords get words => switch (this) {
    KnownLink.modbus => .modbus,
    KnownLink.opcua => .opcua,
    KnownLink.bacnet => .bacnet,
    KnownLink.s7 => .s7,
    KnownLink.snmp => .snmp,
    KnownLink.mqtt => .mqtt,
    KnownLink.http => .http,
    KnownLink.prometheus => .prometheus,
    KnownLink.dlms => .dlms,
    KnownLink.mock => .mock,
    KnownLink.mockdev => .mockdev,
    KnownLink.s3 => .s3,
    KnownLink.gdrive => .gdrive,
    KnownLink.webdav => .webdav,
    KnownLink.localfs => .localfs,
    KnownLink.agent => .agent,
    KnownLink.postgres => .postgres,
    KnownLink.influxdb => .influxdb,
    KnownLink.mongodb => .mongodb,
    KnownLink.mysql => .mysql,
    KnownLink.dynamodb => .dynamodb,
    KnownLink.scheduler => .scheduler,
    KnownLink.alarm => .alarm,
    KnownLink.dql => .dql,
    KnownLink.uplink => .uplink,
  };
}

extension LinkCategoryUi on LinkCategory {
  LinkCategoryTag get tag => switch (this) {
    LinkCategory.equipment => .equipment,
    LinkCategory.apps => .apps,
    LinkCategory.fileStores => .fileStores,
    LinkCategory.historySync => .historySync,
    LinkCategory.messaging => .messaging,
    LinkCategory.test => .test,
    LinkCategory.packages => .packages,
  };
}

extension LinkCategoryTagDomain on LinkCategoryTag {
  LinkCategory get domain => switch (this) {
    LinkCategoryTag.equipment => .equipment,
    LinkCategoryTag.apps => .apps,
    LinkCategoryTag.fileStores => .fileStores,
    LinkCategoryTag.historySync => .historySync,
    LinkCategoryTag.messaging => .messaging,
    LinkCategoryTag.test => .test,
    LinkCategoryTag.packages => .packages,
  };
}

extension CatalogCategoryUi on CatalogCategory {
  /// The category as its chip.
  CatalogCategoryVm get ui => switch (this) {
    CatalogCategoryKnown(:final category) => CatalogCategoryKnownVm(
      category.tag,
    ),
    CatalogCategoryNamed(:final name) => CatalogCategoryNamedVm(name),
  };
}

extension CatalogCategoryVmDomain on CatalogCategoryVm {
  /// The category a picked chip names.
  CatalogCategory get domain => switch (this) {
    CatalogCategoryKnownVm(:final tag) => CatalogCategory.known(tag.domain),
    CatalogCategoryNamedVm(:final name) => CatalogCategory.named(name),
  };
}

extension CatalogItemUi on CatalogItem {
  /// Its title: the broker's, or Studio's words for a driver it knows.
  CatalogTitleVm get title => CatalogTitleVm(
    name: name,
    titled: titled?.words,
    process: processForm,
  );

  /// Its card, [selected] when it is the item picked.
  CatalogCardVm card({required bool selected}) => CatalogCardVm(
    id: id,
    tag: tag,
    code: code,
    title: title,
    description: description,
    described: described?.words,
    builtIn: builtIn,
    modes: [for (final m in modes) m.ui],
    existing: existing,
    version: version,
    official: official,
    selected: selected,
  );
}

extension InstallBrokerUi on InstallBroker {
  /// Its card.
  InstallBrokerVm get ui => InstallBrokerVm(
    site: target.site,
    here: here,
    host: target.host,
    refused: refused?.disabled,
  );
}

/// The cards of [items] that the words searched for ([query]) leave; the
/// one picked ([picked]) is marked. A card is matched by what the broker
/// says of its item and by what it reads on screen (its title and line as
/// `ui` words them, in the language shown): the rule is `business`'s
/// ([catalogHit]), the words are the card's.
List<CatalogCardVm> catalogCards(
  Iterable<CatalogItem> items,
  String? query,
  String? picked,
) => [
  for (final item in items)
    if (item.card(selected: item.id == picked) case final card
        when catalogHit(item, query, [card.name, card.summary]))
      card,
];

/// What the broker said of the install: its [message], after the [status]
/// of its refusal when it refused; null when it said nothing.
BrokerSaidVm? brokerSaid(String? status, String? message) =>
    status == null && message == null
    ? null
    : BrokerSaidVm(status: status, message: message);
