import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../containers/catalog_card.dart';
import '../indicators/check_list.dart';
import '../models/link_run_mode.dart';
import '../shell/window_bar.dart';

/// Where a new link comes from, as drawn: a card of Choose, the rail's
/// label and the answer *From*.
enum InstallFrom {
  official,
  custom,
  backup;

  String get title => switch (this) {
    official => S.current.officialList,
    custom => S.current.customPackage,
    backup => S.current.fromBackup,
  };

  String get detail => switch (this) {
    official => S.current.officialListNote,
    custom => S.current.customPackageNote,
    backup => S.current.fromBackupNote,
  };

  /// The label above the steps.
  String get rail => switch (this) {
    official => S.current.fromTheOfficialList,
    custom => S.current.aCustomPackage,
    backup => S.current.fromBackup,
  };

  /// The one tab of Bring for a link backup, and its file box's words.
  static const backupTab = '.wyrm-link';
  static String get backupHint => S.current.chooseBackupFile;
}

/// How a custom package is brought, as drawn: a tab of Bring, the file
/// box's words before a file is picked, and the fields it asks for.
enum InstallMethod {
  zip,
  url,
  git,
  wasm;

  String get label => switch (this) {
    zip => S.current.zipFile,
    url => 'URL',
    git => 'Git',
    wasm => '.wasm',
  };

  /// What the file box says before a file is picked; null: no file is
  /// asked for.
  String? get fileHint => switch (this) {
    zip => S.current.chooseZip,
    wasm => S.current.chooseWasm,
    url || git => null,
  };

  /// The text fields it asks for.
  List<InstallText> get fields => switch (this) {
    url => const [InstallText.url],
    git => const [InstallText.git, InstallText.ref],
    zip || wasm => const [],
  };
}

/// A text field of Add a link: its label and placeholder. [key] keys it in
/// its form (a field is seeded once per key).
enum InstallText {
  url('url'),
  git('git'),
  ref('ref'),
  name('name'),
  passphrase('passphrase');

  const InstallText(this.key);

  final String key;

  String get label => switch (this) {
    url => S.current.packageUrl,
    git => S.current.gitRepository,
    ref => S.current.gitRef,
    name => S.current.linkName,
    passphrase => S.current.backupPassphrase,
  };

  String? get hint => switch (this) {
    url => 'https://example.com/link.zip',
    git => 'https://git.example.com/link.git',
    ref => S.current.branchOrTag,
    name || passphrase => null,
  };
}

/// A step of Add a link, as drawn.
enum InstallStepKey {
  choose,
  check,
  run,
  result;

  /// Its title in the rail; Choose is *Bring* off the official list.
  String title({required bool official}) => switch (this) {
    choose => official ? S.current.stepChoose : S.current.stepBring,
    check => S.current.stepCheck,
    run => S.current.stepWhere,
    result => S.current.stepInstall,
  };
}

/// Where the install is, as drawn on the last step.
enum InstallResult { installing, done, failed }

/// A button under the result of an install.
enum InstallResultAction {
  explorer,
  links,
  again,
  back;

  String get label => switch (this) {
    explorer => S.current.openInExplorer,
    links => S.current.backToLinks,
    again => S.current.addAnother,
    back => S.current.changeAnswers,
  };

  /// The buttons under [result]: after an install, the new link, Links or
  /// another install; after a refusal, back to the answers or to Links.
  static List<InstallResultAction> of(InstallResult? result) =>
      switch (result) {
        InstallResult.done => const [explorer, links, again],
        InstallResult.failed => const [back, links],
        InstallResult.installing || null => const [],
      };
}

/// What is wrong with the link's name, as said under it; a refusal says
/// the broker's own words instead.
enum InstallNameError { rule, taken, refused }

/// Why *Continue* (or *Install*) is not offered on the step.
enum InstallHold {
  pickOne,
  bringOne,
  checkFailed,
  nameIt,
  nameProblem,
  acceptFirst,
  needsConfig,
}

/// A level a package's grant asks for.
enum InstallGrantLevel {
  none('none'),
  list('list'),
  read('read'),
  write('write'),
  config('config');

  const InstallGrantLevel(this.code);

  /// The level's own name, as the manifest writes it.
  final String code;
}

/// One right a custom package asks for, as typed values; the rights card
/// says each as its kind and what it covers, in the manifest's own terms
/// (`network` `10.0.5.0/24:502`, `read` `on wy/{site}/…`).
sealed class InstallRightVm extends Equatable {
  const InstallRightVm();

  /// The kind, in the manifest's own word.
  String get kind;

  /// What it covers.
  String get detail;

  @override
  List<Object?> get props => [kind, detail];
}

/// The hosts and nets it may reach.
final class NetworkRightVm extends InstallRightVm {
  const NetworkRightVm(this.hosts);

  final List<String> hosts;

  @override
  String get kind => 'network';

  @override
  String get detail => hosts.join(', ');
}

/// A size in MiB: its store ([store]) or its memory.
final class SizeRightVm extends InstallRightVm {
  const SizeRightVm(this.mib, {required this.store});

  final int mib;
  final bool store;

  @override
  String get kind => store ? 'store' : 'memory';

  @override
  String get detail => '$mib MiB';
}

/// The time of one call, in ms.
final class CallRightVm extends InstallRightVm {
  const CallRightVm(this.ms);

  final int ms;

  @override
  String get kind => 'call';

  @override
  String get detail => '$ms ms';
}

/// A grant: [level] on the keys of [path].
final class GrantRightVm extends InstallRightVm {
  const GrantRightVm(this.level, this.path);

  final InstallGrantLevel level;
  final String path;

  @override
  String get kind => level.code;

  @override
  String get detail => 'on $path';
}

/// A broker a link can go to: the site, its host when known, and why it
/// cannot take the link (null: it can).
final class InstallBrokerVm extends Equatable {
  const InstallBrokerVm({
    required this.site,
    required this.here,
    this.host,
    this.refused,
  });

  final String site;

  /// The site Studio is signed in to.
  final bool here;
  final String? host;
  final String? refused;

  @override
  List<Object?> get props => [site, here, host, refused];
}

/// Everything Add a link draws, as typed values: `LinkInstallPage` words
/// them in the language on screen.
final class LinkInstallVm extends Equatable {
  const LinkInstallVm({
    required this.site,
    required this.from,
    required this.steps,
    required this.step,
    required this.broker,
    required this.mode,
    this.window = const WindowBarVm(),
    this.itemName,
    this.itemBuiltIn = true,
    this.sourceName,
    this.name,
    this.checkFailed = false,
    this.needsRights = false,
    this.offersAccept = false,
    this.accepted = false,
    this.categories = const [],
    this.category,
    this.query,
    this.cards = const [],
    this.method = InstallMethod.zip,
    this.file,
    this.url,
    this.ref,
    this.refused,
    this.refusedSaid,
    this.checks = const [],
    this.manifest,
    this.brokers = const [],
    this.modes = const [],
    this.nameError,
    this.replaces = false,
    this.rights = const [],
    this.result,
    this.message,
    this.hold,
    this.configReason,
    this.canPickStep = true,
  });

  /// The frameless window's side of the top bar.
  final WindowBarVm window;

  /// The site on screen.
  final String site;
  final InstallFrom from;
  final List<InstallStepKey> steps;
  final InstallStepKey step;

  /// The item of the official list picked: its name, and whether it is
  /// built into wyrmd.
  final String? itemName;
  final bool itemBuiltIn;

  /// What was brought: a file's name, a URL.
  final String? sourceName;

  /// The broker the link goes to, and how it runs there.
  final String broker;
  final LinkRunMode mode;
  final String? name;
  final bool checkFailed;

  /// The rights must be accepted ([needsRights]); *Accept* is offered
  /// ([offersAccept]); it is ticked ([accepted]).
  final bool needsRights;
  final bool offersAccept;
  final bool accepted;

  /// Choose: the categories (null [category]: all), the words searched
  /// for and the cards shown.
  final List<String> categories;
  final String? category;
  final String? query;
  final List<CatalogCardVm> cards;

  /// Bring: the method, the picked file's name, the URL and ref, the field
  /// the broker refused and its words.
  final InstallMethod method;
  final String? file;
  final String? url;
  final String? ref;
  final InstallText? refused;
  final String? refusedSaid;

  /// Check: the checks and the manifest.
  final List<CheckRowVm> checks;
  final String? manifest;

  /// Where it runs: the brokers, the modes offered, what is wrong with the
  /// name, whether a link of that id is replaced, and the rights asked.
  final List<InstallBrokerVm> brokers;
  final List<LinkRunMode> modes;
  final InstallNameError? nameError;
  final bool replaces;
  final List<InstallRightVm> rights;

  /// The last step: where the install is, and the broker's words.
  final InstallResult? result;
  final String? message;

  /// Why the step offers no *Continue*, and why the user may not install
  /// on the broker ([InstallHold.needsConfig]).
  final InstallHold? hold;
  final String? configReason;

  /// A done step of the rail can be picked (not after an install).
  final bool canPickStep;

  @override
  List<Object?> get props => [
    window,
    site,
    from,
    steps,
    step,
    itemName,
    itemBuiltIn,
    sourceName,
    broker,
    mode,
    name,
    checkFailed,
    needsRights,
    offersAccept,
    accepted,
    categories,
    category,
    query,
    cards,
    method,
    file,
    url,
    ref,
    refused,
    refusedSaid,
    checks,
    manifest,
    brokers,
    modes,
    nameError,
    replaces,
    rights,
    result,
    message,
    hold,
    configReason,
    canPickStep,
  ];
}
