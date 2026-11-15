import 'package:models/catalog_item.dart';
import 'package:models/install_block.dart';
import 'package:models/install_field.dart';
import 'package:models/install_name_problem.dart';
import 'package:models/install_path.dart';
import 'package:models/install_phase.dart';
import 'package:models/install_step.dart';
import 'package:models/install_target.dart';
import 'package:models/link_mode.dart';
import 'package:models/package_check.dart';
import 'package:models/package_check_result.dart';
import 'package:models/package_method.dart';
import 'package:models/requested_right.dart';
import 'package:ui/containers/catalog_card.dart';
import 'package:ui/indicators/check_list.dart';
import 'package:ui/models/link_run_mode.dart';
import 'package:ui/pages/link_install_data.dart';
import 'package:wyrm_client/wyrm_client.dart';

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
  CheckRowVm get row => CheckRowVm(
    title: title,
    detail: detail,
    result: switch (result) {
      PackageCheckResult.ok => CheckResult.ok,
      PackageCheckResult.failed => CheckResult.failed,
      PackageCheckResult.skipped => CheckResult.skipped,
    },
  );
}

extension RequestedRightUi on RequestedRight {
  InstallRightVm get ui => switch (this) {
    RightNetwork(:final hosts) => NetworkRightVm(hosts),
    RightStore(:final mib) => SizeRightVm(mib, store: true),
    RightMemory(:final mib) => SizeRightVm(mib, store: false),
    RightCall(:final ms) => CallRightVm(ms),
    RightGrant(:final level, :final path) => GrantRightVm(level.ui, path),
  };
}

extension PermGrantUi on Perm {
  InstallGrantLevel get ui => switch (this) {
    Perm.none => InstallGrantLevel.none,
    Perm.list => InstallGrantLevel.list,
    Perm.read => InstallGrantLevel.read,
    Perm.write => InstallGrantLevel.write,
    Perm.config => InstallGrantLevel.config,
  };
}

extension CatalogItemUi on CatalogItem {
  /// Its card, [selected] when it is the item picked.
  CatalogCardVm card({required bool selected}) => CatalogCardVm(
    id: id,
    tag: tag,
    name: name,
    description: description,
    builtIn: builtIn,
    modes: [for (final m in modes) m.ui],
    existing: existing,
    version: version,
    official: official,
    selected: selected,
  );
}

extension InstallTargetUi on InstallTarget {
  /// Its card; [here] when it is the site Studio is signed in to.
  InstallBrokerVm broker({required bool here}) =>
      InstallBrokerVm(site: site, here: here, host: host, refused: refused);
}
