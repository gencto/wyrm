// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'intl/messages_all.dart';

// **************************************************************************
// Generator: Flutter Intl IDE plugin
// Made by Localizely
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars
// ignore_for_file: join_return_with_assignment, prefer_final_in_for_each
// ignore_for_file: avoid_redundant_argument_values, avoid_escaping_inner_quotes

class S {
  S();

  static S? _current;

  static S get current {
    assert(
      _current != null,
      'No instance of S was loaded. Try to initialize the S delegate before accessing S.current.',
    );
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<S> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return initializeMessages(localeName).then((_) {
      Intl.defaultLocale = localeName;
      final instance = S();
      S._current = instance;

      return instance;
    });
  }

  static S of(BuildContext context) {
    final instance = S.maybeOf(context);
    assert(
      instance != null,
      'No instance of S present in the widget tree. Did you add S.delegate in localizationsDelegates?',
    );
    return instance!;
  }

  static S? maybeOf(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  /// `en`
  String get _locale {
    return Intl.message('en', name: '_locale', desc: '', args: []);
  }

  /// `WYRM Studio`
  String get appTitle {
    return Intl.message('WYRM Studio', name: 'appTitle', desc: '', args: []);
  }

  /// `OK`
  String get ok {
    return Intl.message('OK', name: 'ok', desc: '', args: []);
  }

  /// `Cancel`
  String get cancel {
    return Intl.message('Cancel', name: 'cancel', desc: '', args: []);
  }

  /// `Log in`
  String get logIn {
    return Intl.message('Log in', name: 'logIn', desc: '', args: []);
  }

  /// `Sign in to a WYRM gateway.`
  String get logInSubtitle {
    return Intl.message(
      'Sign in to a WYRM gateway.',
      name: 'logInSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Password`
  String get password {
    return Intl.message('Password', name: 'password', desc: '', args: []);
  }

  /// `Dark theme`
  String get darkTheme {
    return Intl.message('Dark theme', name: 'darkTheme', desc: '', args: []);
  }

  /// `Light theme`
  String get lightTheme {
    return Intl.message('Light theme', name: 'lightTheme', desc: '', args: []);
  }

  /// `Couldn't connect to internet.`
  String get couldNotConnectToInternet {
    return Intl.message(
      'Couldn\'t connect to internet.',
      name: 'couldNotConnectToInternet',
      desc: '',
      args: [],
    );
  }

  /// `Please check your network settings.`
  String get pleaseCheckYourNetworkSettings {
    return Intl.message(
      'Please check your network settings.',
      name: 'pleaseCheckYourNetworkSettings',
      desc: '',
      args: [],
    );
  }

  /// `Required field`
  String get requiredField {
    return Intl.message(
      'Required field',
      name: 'requiredField',
      desc: '',
      args: [],
    );
  }

  /// `Log out`
  String get logOut {
    return Intl.message('Log out', name: 'logOut', desc: '', args: []);
  }

  /// `Something went wrong`
  String get somethingWentWrong {
    return Intl.message(
      'Something went wrong',
      name: 'somethingWentWrong',
      desc: '',
      args: [],
    );
  }

  /// `Please try again later.`
  String get tryAgainLater {
    return Intl.message(
      'Please try again later.',
      name: 'tryAgainLater',
      desc: '',
      args: [],
    );
  }

  /// `Session expired`
  String get sessionExpired {
    return Intl.message(
      'Session expired',
      name: 'sessionExpired',
      desc: '',
      args: [],
    );
  }

  /// `Please log in again.`
  String get pleaseLogInAgain {
    return Intl.message(
      'Please log in again.',
      name: 'pleaseLogInAgain',
      desc: '',
      args: [],
    );
  }

  /// `Connection problem`
  String get networkError {
    return Intl.message(
      'Connection problem',
      name: 'networkError',
      desc: '',
      args: [],
    );
  }

  /// `Check your connection and try again.`
  String get checkYourConnection {
    return Intl.message(
      'Check your connection and try again.',
      name: 'checkYourConnection',
      desc: '',
      args: [],
    );
  }

  /// `Gateway URL`
  String get gatewayUrl {
    return Intl.message('Gateway URL', name: 'gatewayUrl', desc: '', args: []);
  }

  /// `http://host:8445, or several separated by commas`
  String get gatewayUrlHint {
    return Intl.message(
      'http://host:8445, or several separated by commas',
      name: 'gatewayUrlHint',
      desc: '',
      args: [],
    );
  }

  /// `User`
  String get user {
    return Intl.message('User', name: 'user', desc: '', args: []);
  }

  /// `Not a gateway URL (http:// or https:// and a host)`
  String get invalidGatewayUrl {
    return Intl.message(
      'Not a gateway URL (http:// or https:// and a host)',
      name: 'invalidGatewayUrl',
      desc: '',
      args: [],
    );
  }

  /// `Cannot reach the gateway`
  String get cannotReachGateway {
    return Intl.message(
      'Cannot reach the gateway',
      name: 'cannotReachGateway',
      desc: '',
      args: [],
    );
  }

  /// `Explorer`
  String get wsExplorer {
    return Intl.message('Explorer', name: 'wsExplorer', desc: '', args: []);
  }

  /// `Links`
  String get wsLinks {
    return Intl.message('Links', name: 'wsLinks', desc: '', args: []);
  }

  /// `Flows`
  String get wsFlows {
    return Intl.message('Flows', name: 'wsFlows', desc: '', args: []);
  }

  /// `History`
  String get wsHistory {
    return Intl.message('History', name: 'wsHistory', desc: '', args: []);
  }

  /// `Access`
  String get wsAccess {
    return Intl.message('Access', name: 'wsAccess', desc: '', args: []);
  }

  /// `Sites`
  String get wsSites {
    return Intl.message('Sites', name: 'wsSites', desc: '', args: []);
  }

  /// `Assistant`
  String get wsAssistant {
    return Intl.message('Assistant', name: 'wsAssistant', desc: '', args: []);
  }

  /// `System`
  String get wsSystem {
    return Intl.message('System', name: 'wsSystem', desc: '', args: []);
  }

  /// `More`
  String get more {
    return Intl.message('More', name: 'more', desc: '', args: []);
  }

  /// `Go to a node, action or link`
  String get searchHint {
    return Intl.message(
      'Go to a node, action or link',
      name: 'searchHint',
      desc: '',
      args: [],
    );
  }

  /// `Review and apply`
  String get reviewAndApply {
    return Intl.message(
      'Review and apply',
      name: 'reviewAndApply',
      desc: '',
      args: [],
    );
  }

  /// `Review`
  String get review {
    return Intl.message('Review', name: 'review', desc: '', args: []);
  }

  /// `The gateway connection is lost. Reconnecting; values on screen are the last ones received.`
  String get offline {
    return Intl.message(
      'The gateway connection is lost. Reconnecting; values on screen are the last ones received.',
      name: 'offline',
      desc: '',
      args: [],
    );
  }

  /// `this broker`
  String get thisBroker {
    return Intl.message('this broker', name: 'thisBroker', desc: '', args: []);
  }

  /// `via {site}`
  String viaSite(Object site) {
    return Intl.message('via $site', name: 'viaSite', desc: '', args: [site]);
  }

  /// `upstream`
  String get upstream {
    return Intl.message('upstream', name: 'upstream', desc: '', args: []);
  }

  /// `Go to {key}`
  String goTo(Object key) {
    return Intl.message('Go to $key', name: 'goTo', desc: '', args: [key]);
  }

  /// `{count, plural, =0{No staged changes} =1{1 staged change} other{{count} staged changes}}`
  String stagedChanges(num count) {
    return Intl.plural(
      count,
      zero: 'No staged changes',
      one: '1 staged change',
      other: '$count staged changes',
      name: 'stagedChanges',
      desc: '',
      args: [count],
    );
  }

  /// `Nothing is written until you apply. Each change runs with your own rights.`
  String get stagedNote {
    return Intl.message(
      'Nothing is written until you apply. Each change runs with your own rights.',
      name: 'stagedNote',
      desc: '',
      args: [],
    );
  }

  /// `Apply`
  String get apply {
    return Intl.message('Apply', name: 'apply', desc: '', args: []);
  }

  /// `Discard`
  String get discard {
    return Intl.message('Discard', name: 'discard', desc: '', args: []);
  }

  /// `Nothing staged. Edit a value or a parameter to stage it.`
  String get nothingStaged {
    return Intl.message(
      'Nothing staged. Edit a value or a parameter to stage it.',
      name: 'nothingStaged',
      desc: '',
      args: [],
    );
  }

  /// `The broker refused a change; the ones after it were not applied.`
  String get brokerRefused {
    return Intl.message(
      'The broker refused a change; the ones after it were not applied.',
      name: 'brokerRefused',
      desc: '',
      args: [],
    );
  }

  /// `Needs {level} · you have it`
  String needsLevelYouHaveIt(Object level) {
    return Intl.message(
      'Needs $level · you have it',
      name: 'needsLevelYouHaveIt',
      desc: '',
      args: [level],
    );
  }

  /// `Needs {level} · you have {have}`
  String needsLevelYouHave(Object level, Object have) {
    return Intl.message(
      'Needs $level · you have $have',
      name: 'needsLevelYouHave',
      desc: '',
      args: [level, have],
    );
  }

  /// `Design gallery`
  String get designGallery {
    return Intl.message(
      'Design gallery',
      name: 'designGallery',
      desc: '',
      args: [],
    );
  }

  /// `Comes with wyrmd`
  String get actComesWithWyrmd {
    return Intl.message(
      'Comes with wyrmd',
      name: 'actComesWithWyrmd',
      desc: '',
      args: [],
    );
  }

  /// `A built-in driver updates with the broker.`
  String get actComesWithWyrmdNote {
    return Intl.message(
      'A built-in driver updates with the broker.',
      name: 'actComesWithWyrmdNote',
      desc: '',
      args: [],
    );
  }

  /// `Deauthorize`
  String get actDeauthorize {
    return Intl.message(
      'Deauthorize',
      name: 'actDeauthorize',
      desc: '',
      args: [],
    );
  }

  /// `Block it now: its rights are cut and its next connection waits in quarantine. Its tree stays.`
  String get actDeauthorizeNote {
    return Intl.message(
      'Block it now: its rights are cut and its next connection waits in quarantine. Its tree stays.',
      name: 'actDeauthorizeNote',
      desc: '',
      args: [],
    );
  }

  /// `Edit params`
  String get actEditParams {
    return Intl.message(
      'Edit params',
      name: 'actEditParams',
      desc: '',
      args: [],
    );
  }

  /// `Link-wide parameters. Saved as a new revision.`
  String get actEditParamsNote {
    return Intl.message(
      'Link-wide parameters. Saved as a new revision.',
      name: 'actEditParamsNote',
      desc: '',
      args: [],
    );
  }

  /// `Grant access`
  String get actGrant {
    return Intl.message('Grant access', name: 'actGrant', desc: '', args: []);
  }

  /// `Read or write outside its own branch.`
  String get actGrantNote {
    return Intl.message(
      'Read or write outside its own branch.',
      name: 'actGrantNote',
      desc: '',
      args: [],
    );
  }

  /// `Grants`
  String get actGrants {
    return Intl.message('Grants', name: 'actGrants', desc: '', args: []);
  }

  /// `Only its own branch. Add read or write elsewhere.`
  String get actGrantsNote {
    return Intl.message(
      'Only its own branch. Add read or write elsewhere.',
      name: 'actGrantsNote',
      desc: '',
      args: [],
    );
  }

  /// `Params history`
  String get actParamsHistory {
    return Intl.message(
      'Params history',
      name: 'actParamsHistory',
      desc: '',
      args: [],
    );
  }

  /// `The revisions of its parameters; roll back to any.`
  String get actParamsHistoryNote {
    return Intl.message(
      'The revisions of its parameters; roll back to any.',
      name: 'actParamsHistoryNote',
      desc: '',
      args: [],
    );
  }

  /// `Remove for good`
  String get actRemoveForGood {
    return Intl.message(
      'Remove for good',
      name: 'actRemoveForGood',
      desc: '',
      args: [],
    );
  }

  /// `Retire the id: this certificate never gets rights again. A new device needs a new certificate.`
  String get actRemoveForGoodNote {
    return Intl.message(
      'Retire the id: this certificate never gets rights again. A new device needs a new certificate.',
      name: 'actRemoveForGoodNote',
      desc: '',
      args: [],
    );
  }

  /// `Remove link`
  String get actRemoveLink {
    return Intl.message(
      'Remove link',
      name: 'actRemoveLink',
      desc: '',
      args: [],
    );
  }

  /// `Stops it and deletes its tree.`
  String get actRemoveLinkNote {
    return Intl.message(
      'Stops it and deletes its tree.',
      name: 'actRemoveLinkNote',
      desc: '',
      args: [],
    );
  }

  /// `Secrets`
  String get actSecrets {
    return Intl.message('Secrets', name: 'actSecrets', desc: '', args: []);
  }

  /// `Passwords and keys, sealed; never shown again.`
  String get actSecretsNote {
    return Intl.message(
      'Passwords and keys, sealed; never shown again.',
      name: 'actSecretsNote',
      desc: '',
      args: [],
    );
  }

  /// `Start`
  String get actStart {
    return Intl.message('Start', name: 'actStart', desc: '', args: []);
  }

  /// `Run it again with its last parameters.`
  String get actStartNote {
    return Intl.message(
      'Run it again with its last parameters.',
      name: 'actStartNote',
      desc: '',
      args: [],
    );
  }

  /// `Start, stop, restart`
  String get actStartStopRestart {
    return Intl.message(
      'Start, stop, restart',
      name: 'actStartStopRestart',
      desc: '',
      args: [],
    );
  }

  /// `Stop`
  String get actStop {
    return Intl.message('Stop', name: 'actStop', desc: '', args: []);
  }

  /// `Stays installed; its points go bad until you start it.`
  String get actStopNote {
    return Intl.message(
      'Stays installed; its points go bad until you start it.',
      name: 'actStopNote',
      desc: '',
      args: [],
    );
  }

  /// `Upgrade`
  String get actUpgrade {
    return Intl.message('Upgrade', name: 'actUpgrade', desc: '', args: []);
  }

  /// `Install a newer version of its package.`
  String get actUpgradeNote {
    return Intl.message(
      'Install a newer version of its package.',
      name: 'actUpgradeNote',
      desc: '',
      args: [],
    );
  }

  /// `Upgrade, params, log`
  String get actUpgradeParamsLog {
    return Intl.message(
      'Upgrade, params, log',
      name: 'actUpgradeParamsLog',
      desc: '',
      args: [],
    );
  }

  /// `View log`
  String get actViewLog {
    return Intl.message('View log', name: 'actViewLog', desc: '', args: []);
  }

  /// `Its last lines and its own log level.`
  String get actViewLogNote {
    return Intl.message(
      'Its last lines and its own log level.',
      name: 'actViewLogNote',
      desc: '',
      args: [],
    );
  }

  /// `Add a link`
  String get addALink {
    return Intl.message('Add a link', name: 'addALink', desc: '', args: []);
  }

  /// `{n} d ago`
  String agoDays(Object n) {
    return Intl.message('$n d ago', name: 'agoDays', desc: '', args: [n]);
  }

  /// `{n} h ago`
  String agoHours(Object n) {
    return Intl.message('$n h ago', name: 'agoHours', desc: '', args: [n]);
  }

  /// `{n} min ago`
  String agoMinutes(Object n) {
    return Intl.message('$n min ago', name: 'agoMinutes', desc: '', args: [n]);
  }

  /// `just now`
  String get agoNow {
    return Intl.message('just now', name: 'agoNow', desc: '', args: []);
  }

  /// `Allow all links`
  String get allowAllLinks {
    return Intl.message(
      'Allow all links',
      name: 'allowAllLinks',
      desc: '',
      args: [],
    );
  }

  /// `Every new CN from this CA becomes a link at once, no approval. A leaked certificate gets in.`
  String get allowAllLinksNote {
    return Intl.message(
      'Every new CN from this CA becomes a link at once, no approval. A leaked certificate gets in.',
      name: 'allowAllLinksNote',
      desc: '',
      args: [],
    );
  }

  /// `Approve`
  String get approve {
    return Intl.message('Approve', name: 'approve', desc: '', args: []);
  }

  /// `Approve admits it as a downstream broker with the relays above. Compare the key with its sys/upstream/<this site>/key first.`
  String get approveBrokerNote {
    return Intl.message(
      'Approve admits it as a downstream broker with the relays above. Compare the key with its sys/upstream/<this site>/key first.',
      name: 'approveBrokerNote',
      desc: '',
      args: [],
    );
  }

  /// `Approve makes it an external link with its own branch and a link token; copy the token to the device. The router reloads for about a second. Reject refuses this CN from now on.`
  String get approveLinkNote {
    return Intl.message(
      'Approve makes it an external link with its own branch and a link token; copy the token to the device. The router reloads for about a second. Reject refuses this CN from now on.',
      name: 'approveLinkNote',
      desc: '',
      args: [],
    );
  }

  /// `asks to relay: {sites}`
  String asksToRelay(Object sites) {
    return Intl.message(
      'asks to relay: $sites',
      name: 'asksToRelay',
      desc: '',
      args: [sites],
    );
  }

  /// `built-in driver {driver}`
  String builtInDriver(Object driver) {
    return Intl.message(
      'built-in driver $driver',
      name: 'builtInDriver',
      desc: '',
      args: [driver],
    );
  }

  /// `CA-signed · {site} CA`
  String caSigned(Object site) {
    return Intl.message(
      'CA-signed · $site CA',
      name: 'caSigned',
      desc: '',
      args: [site],
    );
  }

  /// `nothing: no read, no write`
  String get canDoNothing {
    return Intl.message(
      'nothing: no read, no write',
      name: 'canDoNothing',
      desc: '',
      args: [],
    );
  }

  /// `Certificate`
  String get colCertificate {
    return Intl.message(
      'Certificate',
      name: 'colCertificate',
      desc: '',
      args: [],
    );
  }

  /// `From`
  String get colFrom {
    return Intl.message('From', name: 'colFrom', desc: '', args: []);
  }

  /// `Link`
  String get colLink {
    return Intl.message('Link', name: 'colLink', desc: '', args: []);
  }

  /// `Link · device`
  String get colLinkDevice {
    return Intl.message(
      'Link · device',
      name: 'colLinkDevice',
      desc: '',
      args: [],
    );
  }

  /// `Mode`
  String get colMode {
    return Intl.message('Mode', name: 'colMode', desc: '', args: []);
  }

  /// `Runs as`
  String get colRunsAs {
    return Intl.message('Runs as', name: 'colRunsAs', desc: '', args: []);
  }

  /// `State`
  String get colState {
    return Intl.message('State', name: 'colState', desc: '', args: []);
  }

  /// `Version · source`
  String get colVersionSource {
    return Intl.message(
      'Version · source',
      name: 'colVersionSource',
      desc: '',
      args: [],
    );
  }

  /// `Who`
  String get colWho {
    return Intl.message('Who', name: 'colWho', desc: '', args: []);
  }

  /// `Why here`
  String get colWhyHere {
    return Intl.message('Why here', name: 'colWhyHere', desc: '', args: []);
  }

  /// `Deauthorize {id}?`
  String deauthorizeTitle(Object id) {
    return Intl.message(
      'Deauthorize $id?',
      name: 'deauthorizeTitle',
      desc: '',
      args: [id],
    );
  }

  /// `decide in Sites`
  String get decideInSites {
    return Intl.message(
      'decide in Sites',
      name: 'decideInSites',
      desc: '',
      args: [],
    );
  }

  /// `It runs on {device}; the broker cannot start or stop it.`
  String doneOnTheDevice(Object device) {
    return Intl.message(
      'It runs on $device; the broker cannot start or stop it.',
      name: 'doneOnTheDevice',
      desc: '',
      args: [device],
    );
  }

  /// `Whoever runs the device updates it there; it reconnects with the same certificate.`
  String get doneOnTheDeviceUpgrade {
    return Intl.message(
      'Whoever runs the device updates it there; it reconnects with the same certificate.',
      name: 'doneOnTheDeviceUpgrade',
      desc: '',
      args: [],
    );
  }

  /// `downstream broker · over quic`
  String get downstreamBrokerQuic {
    return Intl.message(
      'downstream broker · over quic',
      name: 'downstreamBrokerQuic',
      desc: '',
      args: [],
    );
  }

  /// `Stage applies with the other changes; the link restarts with the new revision.`
  String get editParamsNote {
    return Intl.message(
      'Stage applies with the other changes; the link restarts with the new revision.',
      name: 'editParamsNote',
      desc: '',
      args: [],
    );
  }

  /// `Edit params of {id}`
  String editParamsOf(Object id) {
    return Intl.message(
      'Edit params of $id',
      name: 'editParamsOf',
      desc: '',
      args: [id],
    );
  }

  /// `Branch`
  String get factBranch {
    return Intl.message('Branch', name: 'factBranch', desc: '', args: []);
  }

  /// `Can do`
  String get factCanDo {
    return Intl.message('Can do', name: 'factCanDo', desc: '', args: []);
  }

  /// `Certificate`
  String get factCertificate {
    return Intl.message(
      'Certificate',
      name: 'factCertificate',
      desc: '',
      args: [],
    );
  }

  /// `Device`
  String get factDevice {
    return Intl.message('Device', name: 'factDevice', desc: '', args: []);
  }

  /// `From`
  String get factFrom {
    return Intl.message('From', name: 'factFrom', desc: '', args: []);
  }

  /// `Key`
  String get factKey {
    return Intl.message('Key', name: 'factKey', desc: '', args: []);
  }

  /// `Kind`
  String get factKind {
    return Intl.message('Kind', name: 'factKind', desc: '', args: []);
  }

  /// `Relays`
  String get factRelays {
    return Intl.message('Relays', name: 'factRelays', desc: '', args: []);
  }

  /// `Runs as`
  String get factRunsAs {
    return Intl.message('Runs as', name: 'factRunsAs', desc: '', args: []);
  }

  /// `Seen`
  String get factSeen {
    return Intl.message('Seen', name: 'factSeen', desc: '', args: []);
  }

  /// `Version`
  String get factVersion {
    return Intl.message('Version', name: 'factVersion', desc: '', args: []);
  }

  /// `first seen {when}`
  String firstSeen(Object when) {
    return Intl.message(
      'first seen $when',
      name: 'firstSeen',
      desc: '',
      args: [when],
    );
  }

  /// `from {address}`
  String fromAddress(Object address) {
    return Intl.message(
      'from $address',
      name: 'fromAddress',
      desc: '',
      args: [address],
    );
  }

  /// `Grant access to {id}`
  String grantFor(Object id) {
    return Intl.message(
      'Grant access to $id',
      name: 'grantFor',
      desc: '',
      args: [id],
    );
  }

  /// `Level`
  String get grantLevel {
    return Intl.message('Level', name: 'grantLevel', desc: '', args: []);
  }

  /// `Key or pattern`
  String get grantPath {
    return Intl.message(
      'Key or pattern',
      name: 'grantPath',
      desc: '',
      args: [],
    );
  }

  /// `Change`
  String get groupChange {
    return Intl.message('Change', name: 'groupChange', desc: '', args: []);
  }

  /// `Done on the device, not here`
  String get groupOnTheDevice {
    return Intl.message(
      'Done on the device, not here',
      name: 'groupOnTheDevice',
      desc: '',
      args: [],
    );
  }

  /// `Remove`
  String get groupRemove {
    return Intl.message('Remove', name: 'groupRemove', desc: '', args: []);
  }

  /// `Run`
  String get groupRun {
    return Intl.message('Run', name: 'groupRun', desc: '', args: []);
  }

  /// `Version`
  String get groupVersion {
    return Intl.message('Version', name: 'groupVersion', desc: '', args: []);
  }

  /// `What you control here`
  String get groupYouControl {
    return Intl.message(
      'What you control here',
      name: 'groupYouControl',
      desc: '',
      args: [],
    );
  }

  /// `Params history of {id}`
  String historyOf(Object id) {
    return Intl.message(
      'Params history of $id',
      name: 'historyOf',
      desc: '',
      args: [id],
    );
  }

  /// `Hold unknown connections here`
  String get holdUnknown {
    return Intl.message(
      'Hold unknown connections here',
      name: 'holdUnknown',
      desc: '',
      args: [],
    );
  }

  /// `Off (with Allow all links off too): unknown certificates are ignored.`
  String get holdUnknownNote {
    return Intl.message(
      'Off (with Allow all links off too): unknown certificates are ignored.',
      name: 'holdUnknownNote',
      desc: '',
      args: [],
    );
  }

  /// `Let it in`
  String get letItIn {
    return Intl.message('Let it in', name: 'letItIn', desc: '', args: []);
  }

  /// `Let the broker in`
  String get letTheBrokerIn {
    return Intl.message(
      'Let the broker in',
      name: 'letTheBrokerIn',
      desc: '',
      args: [],
    );
  }

  /// `link · over tls`
  String get linkOverTls {
    return Intl.message(
      'link · over tls',
      name: 'linkOverTls',
      desc: '',
      args: [],
    );
  }

  /// `Started and watched by {site}: built-in drivers and installed packages. You can stop, change, upgrade and remove them.`
  String linksLocalNote(Object site) {
    return Intl.message(
      'Started and watched by $site: built-in drivers and installed packages. You can stop, change, upgrade and remove them.',
      name: 'linksLocalNote',
      desc: '',
      args: [site],
    );
  }

  /// `Links on {site}`
  String linksOn(Object site) {
    return Intl.message(
      'Links on $site',
      name: 'linksOn',
      desc: '',
      args: [site],
    );
  }

  /// `Connections with a certificate from this site that no link is set up for. They can read and write nothing until you approve them.`
  String get linksQuarantineNote {
    return Intl.message(
      'Connections with a certificate from this site that no link is set up for. They can read and write nothing until you approve them.',
      name: 'linksQuarantineNote',
      desc: '',
      args: [],
    );
  }

  /// `They run on their own machines and connect with a certificate from this site. You decide what they may reach and whether they may stay; the device itself is updated where it runs.`
  String get linksRemoteNote {
    return Intl.message(
      'They run on their own machines and connect with a certificate from this site. You decide what they may reach and whether they may stay; the device itself is updated where it runs.',
      name: 'linksRemoteNote',
      desc: '',
      args: [],
    );
  }

  /// `Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.`
  String get linksSubtitle {
    return Intl.message(
      'Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.',
      name: 'linksSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Loading…`
  String get loading {
    return Intl.message('Loading…', name: 'loading', desc: '', args: []);
  }

  /// `No lines.`
  String get logEmpty {
    return Intl.message('No lines.', name: 'logEmpty', desc: '', args: []);
  }

  /// `Log of {id}`
  String logOf(Object id) {
    return Intl.message('Log of $id', name: 'logOf', desc: '', args: [id]);
  }

  /// `Embedded`
  String get modeEmbedded {
    return Intl.message('Embedded', name: 'modeEmbedded', desc: '', args: []);
  }

  /// `External`
  String get modeExternal {
    return Intl.message('External', name: 'modeExternal', desc: '', args: []);
  }

  /// `Process`
  String get modeProcess {
    return Intl.message('Process', name: 'modeProcess', desc: '', args: []);
  }

  /// `No links run on this broker yet. Add a link to connect a device.`
  String get noLocalLinks {
    return Intl.message(
      'No links run on this broker yet. Add a link to connect a device.',
      name: 'noLocalLinks',
      desc: '',
      args: [],
    );
  }

  /// `No device connects as an external link.`
  String get noRemoteLinks {
    return Intl.message(
      'No device connects as an external link.',
      name: 'noRemoteLinks',
      desc: '',
      args: [],
    );
  }

  /// `No revisions.`
  String get noRevisions {
    return Intl.message(
      'No revisions.',
      name: 'noRevisions',
      desc: '',
      args: [],
    );
  }

  /// `Nothing waits in quarantine.`
  String get nothingInQuarantine {
    return Intl.message(
      'Nothing waits in quarantine.',
      name: 'nothingInQuarantine',
      desc: '',
      args: [],
    );
  }

  /// `On other devices`
  String get onOtherDevices {
    return Intl.message(
      'On other devices',
      name: 'onOtherDevices',
      desc: '',
      args: [],
    );
  }

  /// `On this broker`
  String get onThisBroker {
    return Intl.message(
      'On this broker',
      name: 'onThisBroker',
      desc: '',
      args: [],
    );
  }

  /// `package {name}`
  String packageNamed(Object name) {
    return Intl.message(
      'package $name',
      name: 'packageNamed',
      desc: '',
      args: [name],
    );
  }

  /// `Parameters (revision {rev}, JSON)`
  String paramsJson(Object rev) {
    return Intl.message(
      'Parameters (revision $rev, JSON)',
      name: 'paramsJson',
      desc: '',
      args: [rev],
    );
  }

  /// `Quarantine`
  String get quarantine {
    return Intl.message('Quarantine', name: 'quarantine', desc: '', args: []);
  }

  /// `Refresh`
  String get refresh {
    return Intl.message('Refresh', name: 'refresh', desc: '', args: []);
  }

  /// `Reject`
  String get reject {
    return Intl.message('Reject', name: 'reject', desc: '', args: []);
  }

  /// `This certificate is refused from now on.`
  String get rejectNote {
    return Intl.message(
      'This certificate is refused from now on.',
      name: 'rejectNote',
      desc: '',
      args: [],
    );
  }

  /// `Reject {cn}?`
  String rejectTitle(Object cn) {
    return Intl.message(
      'Reject $cn?',
      name: 'rejectTitle',
      desc: '',
      args: [cn],
    );
  }

  /// `If the device is lost or stolen: Remove for good. Deauthorize is the pause: approve it again from quarantine and it keeps its name and tree.`
  String get remoteFooter {
    return Intl.message(
      'If the device is lost or stolen: Remove for good. Deauthorize is the pause: approve it again from quarantine and it keeps its name and tree.',
      name: 'remoteFooter',
      desc: '',
      args: [],
    );
  }

  /// `Remove`
  String get remove {
    return Intl.message('Remove', name: 'remove', desc: '', args: []);
  }

  /// `It stops, and its tree is deleted. The name can be used again.`
  String get removeDeletesTree {
    return Intl.message(
      'It stops, and its tree is deleted. The name can be used again.',
      name: 'removeDeletesTree',
      desc: '',
      args: [],
    );
  }

  /// `Remove {id}?`
  String removeLinkTitle(Object id) {
    return Intl.message(
      'Remove $id?',
      name: 'removeLinkTitle',
      desc: '',
      args: [id],
    );
  }

  /// `It stops, its tree is deleted, and its id is retired: it cannot be used again.`
  String get removeRetiresId {
    return Intl.message(
      'It stops, its tree is deleted, and its id is retired: it cannot be used again.',
      name: 'removeRetiresId',
      desc: '',
      args: [],
    );
  }

  /// `Revision {rev}`
  String revision(Object rev) {
    return Intl.message(
      'Revision $rev',
      name: 'revision',
      desc: '',
      args: [rev],
    );
  }

  /// `Revision {rev} · in use`
  String revisionNow(Object rev) {
    return Intl.message(
      'Revision $rev · in use',
      name: 'revisionNow',
      desc: '',
      args: [rev],
    );
  }

  /// `Roll back`
  String get rollBack {
    return Intl.message('Roll back', name: 'rollBack', desc: '', args: []);
  }

  /// `Its parameters become a new revision and the link restarts with them.`
  String get rollBackNote {
    return Intl.message(
      'Its parameters become a new revision and the link restarts with them.',
      name: 'rollBackNote',
      desc: '',
      args: [],
    );
  }

  /// `Roll back to revision {rev}?`
  String rollBackTo(Object rev) {
    return Intl.message(
      'Roll back to revision $rev?',
      name: 'rollBackTo',
      desc: '',
      args: [rev],
    );
  }

  /// `Runs on {site}`
  String runsOn(Object site) {
    return Intl.message(
      'Runs on $site',
      name: 'runsOn',
      desc: '',
      args: [site],
    );
  }

  /// `Runs on another device`
  String get runsOnAnotherDevice {
    return Intl.message(
      'Runs on another device',
      name: 'runsOnAnotherDevice',
      desc: '',
      args: [],
    );
  }

  /// `Name`
  String get secretName {
    return Intl.message('Name', name: 'secretName', desc: '', args: []);
  }

  /// `Value (empty deletes it)`
  String get secretValue {
    return Intl.message(
      'Value (empty deletes it)',
      name: 'secretValue',
      desc: '',
      args: [],
    );
  }

  /// `A secret is sealed by the broker and never shown again; the link reads it by name.`
  String get secretsNote {
    return Intl.message(
      'A secret is sealed by the broker and never shown again; the link reads it by name.',
      name: 'secretsNote',
      desc: '',
      args: [],
    );
  }

  /// `Set`
  String get setSecret {
    return Intl.message('Set', name: 'setSecret', desc: '', args: []);
  }

  /// `Stage`
  String get stage {
    return Intl.message('Stage', name: 'stage', desc: '', args: []);
  }

  /// `Connected`
  String get stateConnected {
    return Intl.message(
      'Connected',
      name: 'stateConnected',
      desc: '',
      args: [],
    );
  }

  /// `Failed`
  String get stateFailed {
    return Intl.message('Failed', name: 'stateFailed', desc: '', args: []);
  }

  /// `Installed`
  String get stateInstalled {
    return Intl.message(
      'Installed',
      name: 'stateInstalled',
      desc: '',
      args: [],
    );
  }

  /// `Offline`
  String get stateOffline {
    return Intl.message('Offline', name: 'stateOffline', desc: '', args: []);
  }

  /// `Starting`
  String get stateStarting {
    return Intl.message('Starting', name: 'stateStarting', desc: '', args: []);
  }

  /// `Stopped`
  String get stateStopped {
    return Intl.message('Stopped', name: 'stateStopped', desc: '', args: []);
  }

  /// `Stopping`
  String get stateStopping {
    return Intl.message('Stopping', name: 'stateStopping', desc: '', args: []);
  }

  /// `Waiting`
  String get stateWaiting {
    return Intl.message('Waiting', name: 'stateWaiting', desc: '', args: []);
  }

  /// `Waiting in quarantine`
  String get waitingInQuarantine {
    return Intl.message(
      'Waiting in quarantine',
      name: 'waitingInQuarantine',
      desc: '',
      args: [],
    );
  }

  /// `Broker`
  String get whyBroker {
    return Intl.message('Broker', name: 'whyBroker', desc: '', args: []);
  }

  /// `Deauthorized`
  String get whyDeauthorized {
    return Intl.message(
      'Deauthorized',
      name: 'whyDeauthorized',
      desc: '',
      args: [],
    );
  }

  /// `New`
  String get whyNew {
    return Intl.message('New', name: 'whyNew', desc: '', args: []);
  }

  /// `A custom package`
  String get aCustomPackage {
    return Intl.message(
      'A custom package',
      name: 'aCustomPackage',
      desc: '',
      args: [],
    );
  }

  /// `Accept the requested rights first.`
  String get acceptFirst {
    return Intl.message(
      'Accept the requested rights first.',
      name: 'acceptFirst',
      desc: '',
      args: [],
    );
  }

  /// `Accept requested rights`
  String get acceptRequestedRights {
    return Intl.message(
      'Accept requested rights',
      name: 'acceptRequestedRights',
      desc: '',
      args: [],
    );
  }

  /// `accepted`
  String get accepted {
    return Intl.message('accepted', name: 'accepted', desc: '', args: []);
  }

  /// `Add another`
  String get addAnother {
    return Intl.message('Add another', name: 'addAnother', desc: '', args: []);
  }

  /// `Broker`
  String get answerBroker {
    return Intl.message('Broker', name: 'answerBroker', desc: '', args: []);
  }

  /// `From`
  String get answerFrom {
    return Intl.message('From', name: 'answerFrom', desc: '', args: []);
  }

  /// `Link`
  String get answerLink {
    return Intl.message('Link', name: 'answerLink', desc: '', args: []);
  }

  /// `Name`
  String get answerName {
    return Intl.message('Name', name: 'answerName', desc: '', args: []);
  }

  /// `Rights`
  String get answerRights {
    return Intl.message('Rights', name: 'answerRights', desc: '', args: []);
  }

  /// `Runs`
  String get answerRuns {
    return Intl.message('Runs', name: 'answerRuns', desc: '', args: []);
  }

  /// `Back`
  String get back {
    return Intl.message('Back', name: 'back', desc: '', args: []);
  }

  /// `Back to Links`
  String get backToLinks {
    return Intl.message(
      'Back to Links',
      name: 'backToLinks',
      desc: '',
      args: [],
    );
  }

  /// `branch or tag`
  String get branchOrTag {
    return Intl.message(
      'branch or tag',
      name: 'branchOrTag',
      desc: '',
      args: [],
    );
  }

  /// `Choose a file or type where the package is.`
  String get bringOne {
    return Intl.message(
      'Choose a file or type where the package is.',
      name: 'bringOne',
      desc: '',
      args: [],
    );
  }

  /// `The broker says`
  String get brokerSays {
    return Intl.message(
      'The broker says',
      name: 'brokerSays',
      desc: '',
      args: [],
    );
  }

  /// `built in`
  String get builtIn {
    return Intl.message('built in', name: 'builtIn', desc: '', args: []);
  }

  /// `Built into wyrmd · nothing to download`
  String get builtInSummary {
    return Intl.message(
      'Built into wyrmd · nothing to download',
      name: 'builtInSummary',
      desc: '',
      args: [],
    );
  }

  /// `Built in: in wyrmd, nothing to download. Package: from the index in packages.repository, SHA-256 checked; a broker lists only packages it can install.`
  String get catalogNote {
    return Intl.message(
      'Built in: in wyrmd, nothing to download. Package: from the index in packages.repository, SHA-256 checked; a broker lists only packages it can install.',
      name: 'catalogNote',
      desc: '',
      args: [],
    );
  }

  /// `Change the answers`
  String get changeAnswers {
    return Intl.message(
      'Change the answers',
      name: 'changeAnswers',
      desc: '',
      args: [],
    );
  }

  /// `The package did not pass: bring another one.`
  String get checkFailed {
    return Intl.message(
      'The package did not pass: bring another one.',
      name: 'checkFailed',
      desc: '',
      args: [],
    );
  }

  /// `Checked here; the broker checks again before it installs.`
  String get checkedHere {
    return Intl.message(
      'Checked here; the broker checks again before it installs.',
      name: 'checkedHere',
      desc: '',
      args: [],
    );
  }

  /// `Choose a .wasm component`
  String get chooseWasm {
    return Intl.message(
      'Choose a .wasm component',
      name: 'chooseWasm',
      desc: '',
      args: [],
    );
  }

  /// `Choose a package .zip`
  String get chooseZip {
    return Intl.message(
      'Choose a package .zip',
      name: 'chooseZip',
      desc: '',
      args: [],
    );
  }

  /// `config allowed for this upstream`
  String get configAllowed {
    return Intl.message(
      'config allowed for this upstream',
      name: 'configAllowed',
      desc: '',
      args: [],
    );
  }

  /// `Continue`
  String get continueLabel {
    return Intl.message('Continue', name: 'continueLabel', desc: '', args: []);
  }

  /// `Custom package`
  String get customPackage {
    return Intl.message(
      'Custom package',
      name: 'customPackage',
      desc: '',
      args: [],
    );
  }

  /// `A package archive you bring: a zip, a URL, a Git repository or one .wasm. It is checked before install.`
  String get customPackageNote {
    return Intl.message(
      'A package archive you bring: a zip, a URL, a Git repository or one .wasm. It is checked before install.',
      name: 'customPackageNote',
      desc: '',
      args: [],
    );
  }

  /// `downstream`
  String get downstream {
    return Intl.message('downstream', name: 'downstream', desc: '', args: []);
  }

  /// `failed`
  String get failed {
    return Intl.message('failed', name: 'failed', desc: '', args: []);
  }

  /// `From the official list`
  String get fromTheOfficialList {
    return Intl.message(
      'From the official list',
      name: 'fromTheOfficialList',
      desc: '',
      args: [],
    );
  }

  /// `Ref`
  String get gitRef {
    return Intl.message('Ref', name: 'gitRef', desc: '', args: []);
  }

  /// `Git repository (HTTPS)`
  String get gitRepository {
    return Intl.message(
      'Git repository (HTTPS)',
      name: 'gitRepository',
      desc: '',
      args: [],
    );
  }

  /// `How it runs there`
  String get howItRunsThere {
    return Intl.message(
      'How it runs there',
      name: 'howItRunsThere',
      desc: '',
      args: [],
    );
  }

  /// `Install`
  String get install {
    return Intl.message('Install', name: 'install', desc: '', args: []);
  }

  /// `Installing needs config on sys (the admin role). Nothing is installed before you press Install.`
  String get installRailNote {
    return Intl.message(
      'Installing needs config on sys (the admin role). Nothing is installed before you press Install.',
      name: 'installRailNote',
      desc: '',
      args: [],
    );
  }

  /// `{name} is installed on {broker}.`
  String installedOn(Object name, Object broker) {
    return Intl.message(
      '$name is installed on $broker.',
      name: 'installedOn',
      desc: '',
      args: [name, broker],
    );
  }

  /// `Link name`
  String get linkName {
    return Intl.message('Link name', name: 'linkName', desc: '', args: []);
  }

  /// `{n, plural, =1{1 link already} other{{n} links already}}`
  String linksAlready(num n) {
    return Intl.plural(
      n,
      one: '1 link already',
      other: '$n links already',
      name: 'linksAlready',
      desc: '',
      args: [n],
    );
  }

  /// `Manifest`
  String get manifest {
    return Intl.message('Manifest', name: 'manifest', desc: '', args: []);
  }

  /// `Inside the broker: the lightest; it stops when the broker stops.`
  String get modeEmbeddedNote {
    return Intl.message(
      'Inside the broker: the lightest; it stops when the broker stops.',
      name: 'modeEmbeddedNote',
      desc: '',
      args: [],
    );
  }

  /// `On another machine: it connects with a certificate from this site.`
  String get modeExternalNote {
    return Intl.message(
      'On another machine: it connects with a certificate from this site.',
      name: 'modeExternalNote',
      desc: '',
      args: [],
    );
  }

  /// `Its own process on this host, watched and restarted by the broker.`
  String get modeProcessNote {
    return Intl.message(
      'Its own process on this host, watched and restarted by the broker.',
      name: 'modeProcessNote',
      desc: '',
      args: [],
    );
  }

  /// `Inside the broker, in the sandbox: no files, only the network it is allowed, memory and time limits. Set by the package kind.`
  String get modeWasmNote {
    return Intl.message(
      'Inside the broker, in the sandbox: no files, only the network it is allowed, memory and time limits. Set by the package kind.',
      name: 'modeWasmNote',
      desc: '',
      args: [],
    );
  }

  /// `Give the link a name.`
  String get nameIt {
    return Intl.message(
      'Give the link a name.',
      name: 'nameIt',
      desc: '',
      args: [],
    );
  }

  /// `Letters, digits, . _ - · not used by another link, a removed link or a site`
  String get nameRule {
    return Intl.message(
      'Letters, digits, . _ - · not used by another link, a removed link or a site',
      name: 'nameRule',
      desc: '',
      args: [],
    );
  }

  /// `Another link has this name.`
  String get nameTaken {
    return Intl.message(
      'Another link has this name.',
      name: 'nameTaken',
      desc: '',
      args: [],
    );
  }

  /// `Needs config on sys`
  String get needsConfigOnSys {
    return Intl.message(
      'Needs config on sys',
      name: 'needsConfigOnSys',
      desc: '',
      args: [],
    );
  }

  /// `none asked`
  String get noneAsked {
    return Intl.message('none asked', name: 'noneAsked', desc: '', args: []);
  }

  /// `The broker did not install it.`
  String get notInstalled {
    return Intl.message(
      'The broker did not install it.',
      name: 'notInstalled',
      desc: '',
      args: [],
    );
  }

  /// `now`
  String get now {
    return Intl.message('now', name: 'now', desc: '', args: []);
  }

  /// `Official list`
  String get officialList {
    return Intl.message(
      'Official list',
      name: 'officialList',
      desc: '',
      args: [],
    );
  }

  /// `Drivers built into wyrmd and packages from your repository. Pick one, choose where it runs, install.`
  String get officialListNote {
    return Intl.message(
      'Drivers built into wyrmd and packages from your repository. Pick one, choose where it runs, install.',
      name: 'officialListNote',
      desc: '',
      args: [],
    );
  }

  /// `On which broker`
  String get onWhichBroker {
    return Intl.message(
      'On which broker',
      name: 'onWhichBroker',
      desc: '',
      args: [],
    );
  }

  /// `Open in Explorer`
  String get openInExplorer {
    return Intl.message(
      'Open in Explorer',
      name: 'openInExplorer',
      desc: '',
      args: [],
    );
  }

  /// `package`
  String get package {
    return Intl.message('package', name: 'package', desc: '', args: []);
  }

  /// `Package from your repository · SHA-256 checked against the index on download`
  String get packageSummary {
    return Intl.message(
      'Package from your repository · SHA-256 checked against the index on download',
      name: 'packageSummary',
      desc: '',
      args: [],
    );
  }

  /// `Package URL (HTTPS)`
  String get packageUrl {
    return Intl.message(
      'Package URL (HTTPS)',
      name: 'packageUrl',
      desc: '',
      args: [],
    );
  }

  /// `passed`
  String get passed {
    return Intl.message('passed', name: 'passed', desc: '', args: []);
  }

  /// `Pick a link from the list.`
  String get pickOne {
    return Intl.message(
      'Pick a link from the list.',
      name: 'pickOne',
      desc: '',
      args: [],
    );
  }

  /// `The package did not pass`
  String get qCheckFailed {
    return Intl.message(
      'The package did not pass',
      name: 'qCheckFailed',
      desc: '',
      args: [],
    );
  }

  /// `The package looks right`
  String get qCheckOk {
    return Intl.message(
      'The package looks right',
      name: 'qCheckOk',
      desc: '',
      args: [],
    );
  }

  /// `What do you want to add?`
  String get qChoose {
    return Intl.message(
      'What do you want to add?',
      name: 'qChoose',
      desc: '',
      args: [],
    );
  }

  /// `The broker did not install it`
  String get qFailed {
    return Intl.message(
      'The broker did not install it',
      name: 'qFailed',
      desc: '',
      args: [],
    );
  }

  /// `{name} is installed`
  String qInstalled(Object name) {
    return Intl.message(
      '$name is installed',
      name: 'qInstalled',
      desc: '',
      args: [name],
    );
  }

  /// `Installing {name}…`
  String qInstalling(Object name) {
    return Intl.message(
      'Installing $name…',
      name: 'qInstalling',
      desc: '',
      args: [name],
    );
  }

  /// `Where should it run, and under what name?`
  String get qRun {
    return Intl.message(
      'Where should it run, and under what name?',
      name: 'qRun',
      desc: '',
      args: [],
    );
  }

  /// `Without this the broker installs nothing. Grants change later with Grant access; other values with the link's params.`
  String get rightsNote {
    return Intl.message(
      'Without this the broker installs nothing. Grants change later with Grant access; other values with the link\'s params.',
      name: 'rightsNote',
      desc: '',
      args: [],
    );
  }

  /// `The package asks for these rights`
  String get rightsTitle {
    return Intl.message(
      'The package asks for these rights',
      name: 'rightsTitle',
      desc: '',
      args: [],
    );
  }

  /// `Bring`
  String get stepBring {
    return Intl.message('Bring', name: 'stepBring', desc: '', args: []);
  }

  /// `Check`
  String get stepCheck {
    return Intl.message('Check', name: 'stepCheck', desc: '', args: []);
  }

  /// `Choose`
  String get stepChoose {
    return Intl.message('Choose', name: 'stepChoose', desc: '', args: []);
  }

  /// `Install`
  String get stepInstall {
    return Intl.message('Install', name: 'stepInstall', desc: '', args: []);
  }

  /// `Step {n} of {total}`
  String stepOf(Object n, Object total) {
    return Intl.message(
      'Step $n of $total',
      name: 'stepOf',
      desc: '',
      args: [n, total],
    );
  }

  /// `Where it runs`
  String get stepWhere {
    return Intl.message('Where it runs', name: 'stepWhere', desc: '', args: []);
  }

  /// `Studio is signed in here`
  String get studioSignedInHere {
    return Intl.message(
      'Studio is signed in here',
      name: 'studioSignedInHere',
      desc: '',
      args: [],
    );
  }

  /// `to accept`
  String get toAccept {
    return Intl.message('to accept', name: 'toAccept', desc: '', args: []);
  }

  /// `Bring your own package only when it is not in the official list. A zip, a URL or a Git repository with a built package, or one component.`
  String get whyBring {
    return Intl.message(
      'Bring your own package only when it is not in the official list. A zip, a URL or a Git repository with a built package, or one component.',
      name: 'whyBring',
      desc: '',
      args: [],
    );
  }

  /// `Before anything is installed, the archive and what is in it are checked: size, paths, the manifest and its fields, the protocol version, which hosts it has binaries for.`
  String get whyCheck {
    return Intl.message(
      'Before anything is installed, the archive and what is in it are checked: size, paths, the manifest and its fields, the protocol version, which hosts it has binaries for.',
      name: 'whyCheck',
      desc: '',
      args: [],
    );
  }

  /// `Most links come from the official list: a driver built into wyrmd or a package from your repository. Bring your own package only when it is not there.`
  String get whyChoose {
    return Intl.message(
      'Most links come from the official list: a driver built into wyrmd or a package from your repository. Bring your own package only when it is not there.',
      name: 'whyChoose',
      desc: '',
      args: [],
    );
  }

  /// `The broker answered success: false. Its message tells why.`
  String get whyFailed {
    return Intl.message(
      'The broker answered success: false. Its message tells why.',
      name: 'whyFailed',
      desc: '',
      args: [],
    );
  }

  /// `It runs, has its own identity and has declared its branch.`
  String get whyInstalled {
    return Intl.message(
      'It runs, has its own identity and has declared its branch.',
      name: 'whyInstalled',
      desc: '',
      args: [],
    );
  }

  /// `This takes a few seconds. You can leave; it continues.`
  String get whyInstalling {
    return Intl.message(
      'This takes a few seconds. You can leave; it continues.',
      name: 'whyInstalling',
      desc: '',
      args: [],
    );
  }

  /// `Choose the broker. Only brokers whose host the package was built for can take it; how it runs is set by the package kind.`
  String get whyRunCustom {
    return Intl.message(
      'Choose the broker. Only brokers whose host the package was built for can take it; how it runs is set by the package kind.',
      name: 'whyRunCustom',
      desc: '',
      args: [],
    );
  }

  /// `Choose the broker, then how the link runs on it. A built-in driver can run inside the broker, as its own process or on another machine.`
  String get whyRunOfficial {
    return Intl.message(
      'Choose the broker, then how the link runs on it. A built-in driver can run inside the broker, as its own process or on another machine.',
      name: 'whyRunOfficial',
      desc: '',
      args: [],
    );
  }

  /// `Your answers`
  String get yourAnswers {
    return Intl.message(
      'Your answers',
      name: 'yourAnswers',
      desc: '',
      args: [],
    );
  }

  /// `Your answers. Click a step on the left to change one.`
  String get yourAnswersNote {
    return Intl.message(
      'Your answers. Click a step on the left to change one.',
      name: 'yourAnswersNote',
      desc: '',
      args: [],
    );
  }

  /// `Zip file`
  String get zipFile {
    return Intl.message('Zip file', name: 'zipFile', desc: '', args: []);
  }

  /// `Search the list`
  String get searchLinks {
    return Intl.message(
      'Search the list',
      name: 'searchLinks',
      desc: '',
      args: [],
    );
  }

  /// `Point`
  String get colPoint {
    return Intl.message('Point', name: 'colPoint', desc: '', args: []);
  }

  /// `Quality`
  String get colQuality {
    return Intl.message('Quality', name: 'colQuality', desc: '', args: []);
  }

  /// `Time`
  String get colTime {
    return Intl.message('Time', name: 'colTime', desc: '', args: []);
  }

  /// `Type`
  String get colType {
    return Intl.message('Type', name: 'colType', desc: '', args: []);
  }

  /// `Value`
  String get colValue {
    return Intl.message('Value', name: 'colValue', desc: '', args: []);
  }

  /// `Write`
  String get colWrite {
    return Intl.message('Write', name: 'colWrite', desc: '', args: []);
  }

  /// `Configure · staged`
  String get configureStaged {
    return Intl.message(
      'Configure · staged',
      name: 'configureStaged',
      desc: '',
      args: [],
    );
  }

  /// `Staged with your other edits; applied in Review.`
  String get configureStagedNote {
    return Intl.message(
      'Staged with your other edits; applied in Review.',
      name: 'configureStagedNote',
      desc: '',
      args: [],
    );
  }

  /// `History`
  String get factHistory {
    return Intl.message('History', name: 'factHistory', desc: '', args: []);
  }

  /// `New value`
  String get newValue {
    return Intl.message('New value', name: 'newValue', desc: '', args: []);
  }

  /// `No recorded values in this range. A watch in sys/history records a point.`
  String get noHistory {
    return Intl.message(
      'No recorded values in this range. A watch in sys/history records a point.',
      name: 'noHistory',
      desc: '',
      args: [],
    );
  }

  /// `No values here. Open a branch in the tree.`
  String get noPoints {
    return Intl.message(
      'No values here. Open a branch in the tree.',
      name: 'noPoints',
      desc: '',
      args: [],
    );
  }

  /// `no value`
  String get noValue {
    return Intl.message('no value', name: 'noValue', desc: '', args: []);
  }

  /// `not recorded`
  String get notRecorded {
    return Intl.message(
      'not recorded',
      name: 'notRecorded',
      desc: '',
      args: [],
    );
  }

  /// `Read only: the driver does not take a value here.`
  String get notWritable {
    return Intl.message(
      'Read only: the driver does not take a value here.',
      name: 'notWritable',
      desc: '',
      args: [],
    );
  }

  /// `Operate · runs now`
  String get operateRunsNow {
    return Intl.message(
      'Operate · runs now',
      name: 'operateRunsNow',
      desc: '',
      args: [],
    );
  }

  /// `Runs on the device with your rights and is written to the audit.`
  String get operateRunsNowNote {
    return Intl.message(
      'Runs on the device with your rights and is written to the audit.',
      name: 'operateRunsNowNote',
      desc: '',
      args: [],
    );
  }

  /// `{n, plural, =0{no parameters} =1{1 parameter} other{{n} parameters}}`
  String paramCount(num n) {
    return Intl.plural(
      n,
      zero: 'no parameters',
      one: '1 parameter',
      other: '$n parameters',
      name: 'paramCount',
      desc: '',
      args: [n],
    );
  }

  /// `The node's ~meta as the broker declares it: its profile, cfg and attr.`
  String get paramsNote {
    return Intl.message(
      'The node\'s ~meta as the broker declares it: its profile, cfg and attr.',
      name: 'paramsNote',
      desc: '',
      args: [],
    );
  }

  /// `Values update live. Edits are staged in this session; nothing is written to the device until you apply.`
  String get pointsNote {
    return Intl.message(
      'Values update live. Edits are staged in this session; nothing is written to the device until you apply.',
      name: 'pointsNote',
      desc: '',
      args: [],
    );
  }

  /// `recorded`
  String get recorded {
    return Intl.message('recorded', name: 'recorded', desc: '', args: []);
  }

  /// `Result · {action}`
  String resultOf(Object action) {
    return Intl.message(
      'Result · $action',
      name: 'resultOf',
      desc: '',
      args: [action],
    );
  }

  /// `returns {what}`
  String returns(Object what) {
    return Intl.message(
      'returns $what',
      name: 'returns',
      desc: '',
      args: [what],
    );
  }

  /// `{n, plural, =1{1 row} other{{n} rows}}`
  String rowsAnswered(num n) {
    return Intl.plural(
      n,
      one: '1 row',
      other: '$n rows',
      name: 'rowsAnswered',
      desc: '',
      args: [n],
    );
  }

  /// `Run now`
  String get runNow {
    return Intl.message('Run now', name: 'runNow', desc: '', args: []);
  }

  /// `Runs as {user}. Nothing else in the tree changes unless the result is used.`
  String runNowNote(Object user) {
    return Intl.message(
      'Runs as $user. Nothing else in the tree changes unless the result is used.',
      name: 'runNowNote',
      desc: '',
      args: [user],
    );
  }

  /// `Same call from the CLI`
  String get sameCallCli {
    return Intl.message(
      'Same call from the CLI',
      name: 'sameCallCli',
      desc: '',
      args: [],
    );
  }

  /// `Select a node in the tree.`
  String get selectANode {
    return Intl.message(
      'Select a node in the tree.',
      name: 'selectANode',
      desc: '',
      args: [],
    );
  }

  /// `Set value`
  String get setValue {
    return Intl.message('Set value', name: 'setValue', desc: '', args: []);
  }

  /// `Stage puts it into Review and apply with your other edits.`
  String get stagedActionNote {
    return Intl.message(
      'Stage puts it into Review and apply with your other edits.',
      name: 'stagedActionNote',
      desc: '',
      args: [],
    );
  }

  /// `Actions`
  String get tabActions {
    return Intl.message('Actions', name: 'tabActions', desc: '', args: []);
  }

  /// `History`
  String get tabHistory {
    return Intl.message('History', name: 'tabHistory', desc: '', args: []);
  }

  /// `Parameters`
  String get tabParameters {
    return Intl.message(
      'Parameters',
      name: 'tabParameters',
      desc: '',
      args: [],
    );
  }

  /// `Points`
  String get tabPoints {
    return Intl.message('Points', name: 'tabPoints', desc: '', args: []);
  }

  /// `needs {level}`
  String tagNeeds(Object level) {
    return Intl.message(
      'needs $level',
      name: 'tagNeeds',
      desc: '',
      args: [level],
    );
  }

  /// `runs now`
  String get tagRunsNow {
    return Intl.message('runs now', name: 'tagRunsNow', desc: '', args: []);
  }

  /// `staged`
  String get tagStaged {
    return Intl.message('staged', name: 'tagStaged', desc: '', args: []);
  }

  /// `Tree · {site}`
  String treeOf(Object site) {
    return Intl.message('Tree · $site', name: 'treeOf', desc: '', args: [site]);
  }

  /// `was {value}`
  String wasValue(Object value) {
    return Intl.message(
      'was $value',
      name: 'wasValue',
      desc: '',
      args: [value],
    );
  }

  /// `asks to join`
  String get asksToJoin {
    return Intl.message('asks to join', name: 'asksToJoin', desc: '', args: []);
  }

  /// `asks to join · relays {n}`
  String asksToJoinRelays(Object n) {
    return Intl.message(
      'asks to join · relays $n',
      name: 'asksToJoinRelays',
      desc: '',
      args: [n],
    );
  }

  /// `Broker waiting`
  String get brokerWaiting {
    return Intl.message(
      'Broker waiting',
      name: 'brokerWaiting',
      desc: '',
      args: [],
    );
  }

  /// `{brokers} brokers · {devices} devices`
  String brokersDevices(Object brokers, Object devices) {
    return Intl.message(
      '$brokers brokers · $devices devices',
      name: 'brokersDevices',
      desc: '',
      args: [brokers, devices],
    );
  }

  /// `Connect`
  String get connect {
    return Intl.message('Connect', name: 'connect', desc: '', args: []);
  }

  /// `{site} dials out to it; it authorizes {site} there.`
  String connectNote(Object site) {
    return Intl.message(
      '$site dials out to it; it authorizes $site there.',
      name: 'connectNote',
      desc: '',
      args: [site],
    );
  }

  /// `Connect to an upstream`
  String get connectUpstream {
    return Intl.message(
      'Connect to an upstream',
      name: 'connectUpstream',
      desc: '',
      args: [],
    );
  }

  /// `Its rights here are cut now and its next connection waits in quarantine. Its sites stay below it.`
  String get deauthorizeBrokerNote {
    return Intl.message(
      'Its rights here are cut now and its next connection waits in quarantine. Its sites stay below it.',
      name: 'deauthorizeBrokerNote',
      desc: '',
      args: [],
    );
  }

  /// `Decide in Links`
  String get decideInLinks {
    return Intl.message(
      'Decide in Links',
      name: 'decideInLinks',
      desc: '',
      args: [],
    );
  }

  /// `A link in quarantine is approved or rejected in Links › Quarantine.`
  String get decideInLinksNote {
    return Intl.message(
      'A link in quarantine is approved or rejected in Links › Quarantine.',
      name: 'decideInLinksNote',
      desc: '',
      args: [],
    );
  }

  /// `Downstream broker`
  String get downstreamBroker {
    return Intl.message(
      'Downstream broker',
      name: 'downstreamBroker',
      desc: '',
      args: [],
    );
  }

  /// `Config from it`
  String get factAllowConfig {
    return Intl.message(
      'Config from it',
      name: 'factAllowConfig',
      desc: '',
      args: [],
    );
  }

  /// `Below`
  String get factBelow {
    return Intl.message('Below', name: 'factBelow', desc: '', args: []);
  }

  /// `Status`
  String get factStatus {
    return Intl.message('Status', name: 'factStatus', desc: '', args: []);
  }

  /// `Through`
  String get factThrough {
    return Intl.message('Through', name: 'factThrough', desc: '', args: []);
  }

  /// `Tree`
  String get factTree {
    return Intl.message('Tree', name: 'factTree', desc: '', args: []);
  }

  /// `Upstreams`
  String get factUpstreams {
    return Intl.message('Upstreams', name: 'factUpstreams', desc: '', args: []);
  }

  /// `Go up`
  String get goUp {
    return Intl.message('Go up', name: 'goUp', desc: '', args: []);
  }

  /// `Work with it`
  String get groupWork {
    return Intl.message('Work with it', name: 'groupWork', desc: '', args: []);
  }

  /// `Issue`
  String get issue {
    return Intl.message('Issue', name: 'issue', desc: '', args: []);
  }

  /// `connected`
  String get legendConnected {
    return Intl.message(
      'connected',
      name: 'legendConnected',
      desc: '',
      args: [],
    );
  }

  /// `offline`
  String get legendOffline {
    return Intl.message('offline', name: 'legendOffline', desc: '', args: []);
  }

  /// `platform`
  String get legendPlatform {
    return Intl.message('platform', name: 'legendPlatform', desc: '', args: []);
  }

  /// `waiting in quarantine`
  String get legendWaiting {
    return Intl.message(
      'waiting in quarantine',
      name: 'legendWaiting',
      desc: '',
      args: [],
    );
  }

  /// `Let others in`
  String get letOthersIn {
    return Intl.message(
      'Let others in',
      name: 'letOthersIn',
      desc: '',
      args: [],
    );
  }

  /// `new certificate`
  String get newCertificate {
    return Intl.message(
      'new certificate',
      name: 'newCertificate',
      desc: '',
      args: [],
    );
  }

  /// `no`
  String get no {
    return Intl.message('no', name: 'no', desc: '', args: []);
  }

  /// `none: {site} is the top`
  String noUpstream(Object site) {
    return Intl.message(
      'none: $site is the top',
      name: 'noUpstream',
      desc: '',
      args: [site],
    );
  }

  /// `Open in Links`
  String get openInLinks {
    return Intl.message(
      'Open in Links',
      name: 'openInLinks',
      desc: '',
      args: [],
    );
  }

  /// `Grants, deauthorize and remove are in Links › On other devices.`
  String get openInLinksNote {
    return Intl.message(
      'Grants, deauthorize and remove are in Links › On other devices.',
      name: 'openInLinksNote',
      desc: '',
      args: [],
    );
  }

  /// `Open its tree`
  String get openItsTree {
    return Intl.message(
      'Open its tree',
      name: 'openItsTree',
      desc: '',
      args: [],
    );
  }

  /// `Explorer shows wy/{site}.`
  String openItsTreeNote(Object site) {
    return Intl.message(
      'Explorer shows wy/$site.',
      name: 'openItsTreeNote',
      desc: '',
      args: [site],
    );
  }

  /// `Platform`
  String get platform {
    return Intl.message('Platform', name: 'platform', desc: '', args: []);
  }

  /// `Its settings and counters are under downstream/uplink.`
  String get platformNote {
    return Intl.message(
      'Its settings and counters are under downstream/uplink.',
      name: 'platformNote',
      desc: '',
      args: [],
    );
  }

  /// `Quarantine and admission`
  String get quarantineAndAdmission {
    return Intl.message(
      'Quarantine and admission',
      name: 'quarantineAndAdmission',
      desc: '',
      args: [],
    );
  }

  /// `Unknown certificates wait in Links › Quarantine.`
  String get quarantineAndAdmissionNote {
    return Intl.message(
      'Unknown certificates wait in Links › Quarantine.',
      name: 'quarantineAndAdmissionNote',
      desc: '',
      args: [],
    );
  }

  /// `Nothing to do from here: it came in with its relay. Deauthorize the relay to cut it off.`
  String get relayedFooter {
    return Intl.message(
      'Nothing to do from here: it came in with its relay. Deauthorize the relay to cut it off.',
      name: 'relayedFooter',
      desc: '',
      args: [],
    );
  }

  /// `{n, plural, =1{relays 1 site} other{relays {n} sites}}`
  String relaysSites(num n) {
    return Intl.plural(
      n,
      one: 'relays 1 site',
      other: 'relays $n sites',
      name: 'relaysSites',
      desc: '',
      args: [n],
    );
  }

  /// `Site relayed below`
  String get siteRelayedBelow {
    return Intl.message(
      'Site relayed below',
      name: 'siteRelayedBelow',
      desc: '',
      args: [],
    );
  }

  /// `Sites around {site}`
  String sitesAround(Object site) {
    return Intl.message(
      'Sites around $site',
      name: 'sitesAround',
      desc: '',
      args: [site],
    );
  }

  /// `What {site} connects to and what connects to it: brokers above and below, platforms it sends to, and devices whose links run outside any broker.`
  String sitesSubtitle(Object site) {
    return Intl.message(
      'What $site connects to and what connects to it: brokers above and below, platforms it sends to, and devices whose links run outside any broker.',
      name: 'sitesSubtitle',
      desc: '',
      args: [site],
    );
  }

  /// `Token for a site below`
  String get tokenForBelow {
    return Intl.message(
      'Token for a site below',
      name: 'tokenForBelow',
      desc: '',
      args: [],
    );
  }

  /// `Valid for hours`
  String get tokenHours {
    return Intl.message(
      'Valid for hours',
      name: 'tokenHours',
      desc: '',
      args: [],
    );
  }

  /// `One token admits a broker at once. It is shown once; set its uses and hours.`
  String get tokenNote {
    return Intl.message(
      'One token admits a broker at once. It is shown once; set its uses and hours.',
      name: 'tokenNote',
      desc: '',
      args: [],
    );
  }

  /// `Uses`
  String get tokenUses {
    return Intl.message('Uses', name: 'tokenUses', desc: '', args: []);
  }

  /// `Upstream broker`
  String get upstreamBroker {
    return Intl.message(
      'Upstream broker',
      name: 'upstreamBroker',
      desc: '',
      args: [],
    );
  }

  /// `An upstream configured in wyrmd.json5 is changed there; one added here is removed with sys/upstream/<name> ▸ Remove.`
  String get upstreamFooter {
    return Intl.message(
      'An upstream configured in wyrmd.json5 is changed there; one added here is removed with sys/upstream/<name> ▸ Remove.',
      name: 'upstreamFooter',
      desc: '',
      args: [],
    );
  }

  /// `{n} waiting to be let in: {who}`
  String waitingToBeLetIn(Object n, Object who) {
    return Intl.message(
      '$n waiting to be let in: $who',
      name: 'waitingToBeLetIn',
      desc: '',
      args: [n, who],
    );
  }

  /// `yes`
  String get yes {
    return Intl.message('yes', name: 'yes', desc: '', args: []);
  }

  /// `YOU`
  String get youTag {
    return Intl.message('YOU', name: 'youTag', desc: '', args: []);
  }

  /// `your upstream`
  String get yourUpstream {
    return Intl.message(
      'your upstream',
      name: 'yourUpstream',
      desc: '',
      args: [],
    );
  }

  /// `Block`
  String get block {
    return Intl.message('Block', name: 'block', desc: '', args: []);
  }

  /// `{n, plural, =1{1 block} other{{n} blocks}}`
  String blocksCount(num n) {
    return Intl.plural(
      n,
      one: '1 block',
      other: '$n blocks',
      name: 'blocksCount',
      desc: '',
      args: [n],
    );
  }

  /// `Deployed by`
  String get colDeployedBy {
    return Intl.message(
      'Deployed by',
      name: 'colDeployedBy',
      desc: '',
      args: [],
    );
  }

  /// `Flow`
  String get colFlow {
    return Intl.message('Flow', name: 'colFlow', desc: '', args: []);
  }

  /// `Reads → writes`
  String get colReadsWrites {
    return Intl.message(
      'Reads → writes',
      name: 'colReadsWrites',
      desc: '',
      args: [],
    );
  }

  /// `Dataflow`
  String get dataflow {
    return Intl.message('Dataflow', name: 'dataflow', desc: '', args: []);
  }

  /// `Deploy`
  String get deploy {
    return Intl.message('Deploy', name: 'deploy', desc: '', args: []);
  }

  /// `Deploying…`
  String get deploying {
    return Intl.message('Deploying…', name: 'deploying', desc: '', args: []);
  }

  /// `Draft · valid, not deployed`
  String get draftValid {
    return Intl.message(
      'Draft · valid, not deployed',
      name: 'draftValid',
      desc: '',
      args: [],
    );
  }

  /// `Edit dataflow`
  String get editDataflow {
    return Intl.message(
      'Edit dataflow',
      name: 'editDataflow',
      desc: '',
      args: [],
    );
  }

  /// `Open it in the editor; nothing changes until you deploy.`
  String get editDataflowNote {
    return Intl.message(
      'Open it in the editor; nothing changes until you deploy.',
      name: 'editDataflowNote',
      desc: '',
      args: [],
    );
  }

  /// `About`
  String get factAbout {
    return Intl.message('About', name: 'factAbout', desc: '', args: []);
  }

  /// `Blocks`
  String get factBlocks {
    return Intl.message('Blocks', name: 'factBlocks', desc: '', args: []);
  }

  /// `Problem`
  String get factProblem {
    return Intl.message('Problem', name: 'factProblem', desc: '', args: []);
  }

  /// `Running`
  String get factRunning {
    return Intl.message('Running', name: 'factRunning', desc: '', args: []);
  }

  /// `The draft does not validate.`
  String get fixFirst {
    return Intl.message(
      'The draft does not validate.',
      name: 'fixFirst',
      desc: '',
      args: [],
    );
  }

  /// `v{v} deployed`
  String flowDeployed(Object v) {
    return Intl.message(
      'v$v deployed',
      name: 'flowDeployed',
      desc: '',
      args: [v],
    );
  }

  /// `v{v} · error`
  String flowError(Object v) {
    return Intl.message('v$v · error', name: 'flowError', desc: '', args: [v]);
  }

  /// `Flow id`
  String get flowName {
    return Intl.message('Flow id', name: 'flowName', desc: '', args: []);
  }

  /// `Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.`
  String get flowPropertiesNote {
    return Intl.message(
      'Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.',
      name: 'flowPropertiesNote',
      desc: '',
      args: [],
    );
  }

  /// `v{v} stopped`
  String flowStopped(Object v) {
    return Intl.message(
      'v$v stopped',
      name: 'flowStopped',
      desc: '',
      args: [v],
    );
  }

  /// `Version {v}`
  String flowVersion(Object v) {
    return Intl.message('Version $v', name: 'flowVersion', desc: '', args: [v]);
  }

  /// `A deploy needs config on dataflows; the gateway adds your proofs for each target. Viewers can open a flow and only look.`
  String get flowsFooter {
    return Intl.message(
      'A deploy needs config on dataflows; the gateway adds your proofs for each target. Viewers can open a flow and only look.',
      name: 'flowsFooter',
      desc: '',
      args: [],
    );
  }

  /// `Flows on {site}`
  String flowsOn(Object site) {
    return Intl.message(
      'Flows on $site',
      name: 'flowsOn',
      desc: '',
      args: [site],
    );
  }

  /// `Each flow runs in the broker. You edit a draft; nothing changes until you deploy it.`
  String get flowsSubtitle {
    return Intl.message(
      'Each flow runs in the broker. You edit a draft; nothing changes until you deploy it.',
      name: 'flowsSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `New dataflow`
  String get newDataflow {
    return Intl.message(
      'New dataflow',
      name: 'newDataflow',
      desc: '',
      args: [],
    );
  }

  /// `No flows on this site yet.`
  String get noFlows {
    return Intl.message(
      'No flows on this site yet.',
      name: 'noFlows',
      desc: '',
      args: [],
    );
  }

  /// `not deployed`
  String get notDeployed {
    return Intl.message(
      'not deployed',
      name: 'notDeployed',
      desc: '',
      args: [],
    );
  }

  /// `Nothing to deploy`
  String get nothingToDeploy {
    return Intl.message(
      'Nothing to deploy',
      name: 'nothingToDeploy',
      desc: '',
      args: [],
    );
  }

  /// `Blocks`
  String get paletteBlocks {
    return Intl.message('Blocks', name: 'paletteBlocks', desc: '', args: []);
  }

  /// `Tree`
  String get paletteTree {
    return Intl.message('Tree', name: 'paletteTree', desc: '', args: []);
  }

  /// `Remove block`
  String get removeBlock {
    return Intl.message(
      'Remove block',
      name: 'removeBlock',
      desc: '',
      args: [],
    );
  }

  /// `Validate`
  String get validate {
    return Intl.message('Validate', name: 'validate', desc: '', args: []);
  }

  /// `Access on {site}`
  String accessOn(Object site) {
    return Intl.message(
      'Access on $site',
      name: 'accessOn',
      desc: '',
      args: [site],
    );
  }

  /// `Who may log in to this gateway, what each role may reach, and what was done.`
  String get accessSubtitle {
    return Intl.message(
      'Who may log in to this gateway, what each role may reach, and what was done.',
      name: 'accessSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Add a grant`
  String get addGrant {
    return Intl.message('Add a grant', name: 'addGrant', desc: '', args: []);
  }

  /// `Add a user`
  String get addUser {
    return Intl.message('Add a user', name: 'addUser', desc: '', args: []);
  }

  /// `Add a point`
  String get addWatchPath {
    return Intl.message(
      'Add a point',
      name: 'addWatchPath',
      desc: '',
      args: [],
    );
  }

  /// `Record one more point (a key under downstream, dataflows or storage).`
  String get addWatchPathNote {
    return Intl.message(
      'Record one more point (a key under downstream, dataflows or storage).',
      name: 'addWatchPathNote',
      desc: '',
      args: [],
    );
  }

  /// `Users are managed by the gateway's administrators.`
  String get adminsOnly {
    return Intl.message(
      'Users are managed by the gateway\'s administrators.',
      name: 'adminsOnly',
      desc: '',
      args: [],
    );
  }

  /// `Log`
  String get brokerLog {
    return Intl.message('Log', name: 'brokerLog', desc: '', args: []);
  }

  /// `Clear disconnected links`
  String get clearConns {
    return Intl.message(
      'Clear disconnected links',
      name: 'clearConns',
      desc: '',
      args: [],
    );
  }

  /// `Removes external links that are not connected; their ids are retired.`
  String get clearConnsNote {
    return Intl.message(
      'Removes external links that are not connected; their ids are retired.',
      name: 'clearConnsNote',
      desc: '',
      args: [],
    );
  }

  /// `Key`
  String get colKey {
    return Intl.message('Key', name: 'colKey', desc: '', args: []);
  }

  /// `Level`
  String get colLevel {
    return Intl.message('Level', name: 'colLevel', desc: '', args: []);
  }

  /// `Role`
  String get colRole {
    return Intl.message('Role', name: 'colRole', desc: '', args: []);
  }

  /// `Roles`
  String get colRoles {
    return Intl.message('Roles', name: 'colRoles', desc: '', args: []);
  }

  /// `Rows shown`
  String get colRows {
    return Intl.message('Rows shown', name: 'colRows', desc: '', args: []);
  }

  /// `From`
  String get colSource {
    return Intl.message('From', name: 'colSource', desc: '', args: []);
  }

  /// `User`
  String get colUser {
    return Intl.message('User', name: 'colUser', desc: '', args: []);
  }

  /// `Watch`
  String get colWatch {
    return Intl.message('Watch', name: 'colWatch', desc: '', args: []);
  }

  /// `Collecting values…`
  String get collecting {
    return Intl.message(
      'Collecting values…',
      name: 'collecting',
      desc: '',
      args: [],
    );
  }

  /// `connected`
  String get connected {
    return Intl.message('connected', name: 'connected', desc: '', args: []);
  }

  /// `Control plane`
  String get controlPlane {
    return Intl.message(
      'Control plane',
      name: 'controlPlane',
      desc: '',
      args: [],
    );
  }

  /// `data_dir {size}`
  String dataDir(Object size) {
    return Intl.message(
      'data_dir $size',
      name: 'dataDir',
      desc: '',
      args: [size],
    );
  }

  /// `Every part of the design system (development builds).`
  String get designGalleryNote {
    return Intl.message(
      'Every part of the design system (development builds).',
      name: 'designGalleryNote',
      desc: '',
      args: [],
    );
  }

  /// `Disable`
  String get disableUser {
    return Intl.message('Disable', name: 'disableUser', desc: '', args: []);
  }

  /// `A disabled user cannot log in; their roles stay.`
  String get disableUserNote {
    return Intl.message(
      'A disabled user cannot log in; their roles stay.',
      name: 'disableUserNote',
      desc: '',
      args: [],
    );
  }

  /// `Edit the group`
  String get editGroup {
    return Intl.message(
      'Edit the group',
      name: 'editGroup',
      desc: '',
      args: [],
    );
  }

  /// `How and how often its points are recorded.`
  String get editGroupNote {
    return Intl.message(
      'How and how often its points are recorded.',
      name: 'editGroupNote',
      desc: '',
      args: [],
    );
  }

  /// `Enable`
  String get enableUser {
    return Intl.message('Enable', name: 'enableUser', desc: '', args: []);
  }

  /// `every {s} s`
  String everySeconds(Object s) {
    return Intl.message(
      'every $s s',
      name: 'everySeconds',
      desc: '',
      args: [s],
    );
  }

  /// `Build`
  String get factBuild {
    return Intl.message('Build', name: 'factBuild', desc: '', args: []);
  }

  /// `Flush`
  String get factFlush {
    return Intl.message('Flush', name: 'factFlush', desc: '', args: []);
  }

  /// `Grants`
  String get factGrants {
    return Intl.message('Grants', name: 'factGrants', desc: '', args: []);
  }

  /// `Interval`
  String get factInterval {
    return Intl.message('Interval', name: 'factInterval', desc: '', args: []);
  }

  /// `Log level`
  String get factLogLevel {
    return Intl.message('Log level', name: 'factLogLevel', desc: '', args: []);
  }

  /// `Oldest day`
  String get factOldest {
    return Intl.message('Oldest day', name: 'factOldest', desc: '', args: []);
  }

  /// `Record`
  String get factRecord {
    return Intl.message('Record', name: 'factRecord', desc: '', args: []);
  }

  /// `Rows written`
  String get factRowsWritten {
    return Intl.message(
      'Rows written',
      name: 'factRowsWritten',
      desc: '',
      args: [],
    );
  }

  /// `Started`
  String get factStarted {
    return Intl.message('Started', name: 'factStarted', desc: '', args: []);
  }

  /// `Subject`
  String get factSubject {
    return Intl.message('Subject', name: 'factSubject', desc: '', args: []);
  }

  /// `Gateway user`
  String get gatewayUser {
    return Intl.message(
      'Gateway user',
      name: 'gatewayUser',
      desc: '',
      args: [],
    );
  }

  /// `raw kept {days} d`
  String historianKeep(Object days) {
    return Intl.message(
      'raw kept $days d',
      name: 'historianKeep',
      desc: '',
      args: [days],
    );
  }

  /// `{n} series`
  String historianSeries(Object n) {
    return Intl.message(
      '$n series',
      name: 'historianSeries',
      desc: '',
      args: [n],
    );
  }

  /// `Historian {size}`
  String historianSize(Object size) {
    return Intl.message(
      'Historian $size',
      name: 'historianSize',
      desc: '',
      args: [size],
    );
  }

  /// `Sync links read the historian's change journal, so nothing is lost while a database is down.`
  String get historyFooter {
    return Intl.message(
      'Sync links read the historian\'s change journal, so nothing is lost while a database is down.',
      name: 'historyFooter',
      desc: '',
      args: [],
    );
  }

  /// `lag {lag}`
  String lag(Object lag) {
    return Intl.message('lag $lag', name: 'lag', desc: '', args: [lag]);
  }

  /// `ACL denials`
  String get mAclDenials {
    return Intl.message('ACL denials', name: 'mAclDenials', desc: '', args: []);
  }

  /// `Audit records`
  String get mAuditRecords {
    return Intl.message(
      'Audit records',
      name: 'mAuditRecords',
      desc: '',
      args: [],
    );
  }

  /// `Free disk`
  String get mFreeDisk {
    return Intl.message('Free disk', name: 'mFreeDisk', desc: '', args: []);
  }

  /// `In quarantine`
  String get mInQuarantine {
    return Intl.message(
      'In quarantine',
      name: 'mInQuarantine',
      desc: '',
      args: [],
    );
  }

  /// `Links connected`
  String get mLinksConnected {
    return Intl.message(
      'Links connected',
      name: 'mLinksConnected',
      desc: '',
      args: [],
    );
  }

  /// `Memory`
  String get mMemory {
    return Intl.message('Memory', name: 'mMemory', desc: '', args: []);
  }

  /// `Sessions`
  String get mSessions {
    return Intl.message('Sessions', name: 'mSessions', desc: '', args: []);
  }

  /// `Standby`
  String get mStandby {
    return Intl.message('Standby', name: 'mStandby', desc: '', args: []);
  }

  /// `Upstreams / below`
  String get mUpDown {
    return Intl.message(
      'Upstreams / below',
      name: 'mUpDown',
      desc: '',
      args: [],
    );
  }

  /// `Router messages per second`
  String get messagesPerSecond {
    return Intl.message(
      'Router messages per second',
      name: 'messagesPerSecond',
      desc: '',
      args: [],
    );
  }

  /// `No audit records you may read.`
  String get noAudit {
    return Intl.message(
      'No audit records you may read.',
      name: 'noAudit',
      desc: '',
      args: [],
    );
  }

  /// `No grants you may read.`
  String get noGrants {
    return Intl.message(
      'No grants you may read.',
      name: 'noGrants',
      desc: '',
      args: [],
    );
  }

  /// `No users you may see.`
  String get noUsers {
    return Intl.message(
      'No users you may see.',
      name: 'noUsers',
      desc: '',
      args: [],
    );
  }

  /// `No watch groups yet. Add one to record points.`
  String get noWatchGroups {
    return Intl.message(
      'No watch groups yet. Add one to record points.',
      name: 'noWatchGroups',
      desc: '',
      args: [],
    );
  }

  /// `No points in this group.`
  String get noWatchPaths {
    return Intl.message(
      'No points in this group.',
      name: 'noWatchPaths',
      desc: '',
      args: [],
    );
  }

  /// `none`
  String get none {
    return Intl.message('none', name: 'none', desc: '', args: []);
  }

  /// `{n, plural, =1{1 point} other{{n} points}}`
  String pointsCount(num n) {
    return Intl.plural(
      n,
      one: '1 point',
      other: '$n points',
      name: 'pointsCount',
      desc: '',
      args: [n],
    );
  }

  /// `Purge a time range`
  String get purgeHistory {
    return Intl.message(
      'Purge a time range',
      name: 'purgeHistory',
      desc: '',
      args: [],
    );
  }

  /// `Deletes the recorded rows of a range, for every point.`
  String get purgeHistoryNote {
    return Intl.message(
      'Deletes the recorded rows of a range, for every point.',
      name: 'purgeHistoryNote',
      desc: '',
      args: [],
    );
  }

  /// `Remove the group`
  String get removeGroup {
    return Intl.message(
      'Remove the group',
      name: 'removeGroup',
      desc: '',
      args: [],
    );
  }

  /// `It stops recording; its rows stay unless you purge them.`
  String get removeGroupNote {
    return Intl.message(
      'It stops recording; its rows stay unless you purge them.',
      name: 'removeGroupNote',
      desc: '',
      args: [],
    );
  }

  /// `Remove user`
  String get removeUser {
    return Intl.message('Remove user', name: 'removeUser', desc: '', args: []);
  }

  /// `They cannot log in again; their sessions end.`
  String get removeUserNote {
    return Intl.message(
      'They cannot log in again; their sessions end.',
      name: 'removeUserNote',
      desc: '',
      args: [],
    );
  }

  /// `Remove {name}?`
  String removeUserTitle(Object name) {
    return Intl.message(
      'Remove $name?',
      name: 'removeUserTitle',
      desc: '',
      args: [name],
    );
  }

  /// `Running`
  String get running {
    return Intl.message('Running', name: 'running', desc: '', args: []);
  }

  /// `see Links`
  String get seeLinks {
    return Intl.message('see Links', name: 'seeLinks', desc: '', args: []);
  }

  /// `Log level {level}`
  String setLogLevel(Object level) {
    return Intl.message(
      'Log level $level',
      name: 'setLogLevel',
      desc: '',
      args: [level],
    );
  }

  /// `Takes effect at once, no restart. Staged with your other edits.`
  String get setLogLevelNote {
    return Intl.message(
      'Takes effect at once, no restart. Staged with your other edits.',
      name: 'setLogLevelNote',
      desc: '',
      args: [],
    );
  }

  /// `Set password`
  String get setPassword {
    return Intl.message(
      'Set password',
      name: 'setPassword',
      desc: '',
      args: [],
    );
  }

  /// `Their open sessions stay until they expire.`
  String get setPasswordNote {
    return Intl.message(
      'Their open sessions stay until they expire.',
      name: 'setPasswordNote',
      desc: '',
      args: [],
    );
  }

  /// `Set roles`
  String get setRoles {
    return Intl.message('Set roles', name: 'setRoles', desc: '', args: []);
  }

  /// `Roles decide what the user reaches (see Grants).`
  String get setRolesNote {
    return Intl.message(
      'Roles decide what the user reaches (see Grants).',
      name: 'setRolesNote',
      desc: '',
      args: [],
    );
  }

  /// `sys/**, admin only`
  String get sysAdminOnly {
    return Intl.message(
      'sys/**, admin only',
      name: 'sysAdminOnly',
      desc: '',
      args: [],
    );
  }

  /// `wyrmd.json5 states the intent at first start; everything changed here since lives in its write-ahead log.`
  String get systemFooter {
    return Intl.message(
      'wyrmd.json5 states the intent at first start; everything changed here since lives in its write-ahead log.',
      name: 'systemFooter',
      desc: '',
      args: [],
    );
  }

  /// `Audit`
  String get tabAudit {
    return Intl.message('Audit', name: 'tabAudit', desc: '', args: []);
  }

  /// `Grants`
  String get tabGrants {
    return Intl.message('Grants', name: 'tabGrants', desc: '', args: []);
  }

  /// `Users`
  String get tabUsers {
    return Intl.message('Users', name: 'tabUsers', desc: '', args: []);
  }

  /// `The point stops being recorded; its rows stay.`
  String get unsubscribeNote {
    return Intl.message(
      'The point stops being recorded; its rows stay.',
      name: 'unsubscribeNote',
      desc: '',
      args: [],
    );
  }

  /// `up {d}`
  String upFor(Object d) {
    return Intl.message('up $d', name: 'upFor', desc: '', args: [d]);
  }

  /// `Active`
  String get userActive {
    return Intl.message('Active', name: 'userActive', desc: '', args: []);
  }

  /// `Disabled`
  String get userDisabled {
    return Intl.message('Disabled', name: 'userDisabled', desc: '', args: []);
  }

  /// `Watch group`
  String get watchGroup {
    return Intl.message('Watch group', name: 'watchGroup', desc: '', args: []);
  }

  /// `Watch groups · {n}`
  String watchGroups(Object n) {
    return Intl.message(
      'Watch groups · $n',
      name: 'watchGroups',
      desc: '',
      args: [n],
    );
  }

  /// `wyrmd on {site}`
  String wyrmdOn(Object site) {
    return Intl.message(
      'wyrmd on $site',
      name: 'wyrmdOn',
      desc: '',
      args: [site],
    );
  }

  /// `New task`
  String get newTask {
    return Intl.message('New task', name: 'newTask', desc: '', args: []);
  }

  /// `Each task is a node: {agent}/tasks/<id>`
  String taskListNote(Object agent) {
    return Intl.message(
      'Each task is a node: $agent/tasks/<id>',
      name: 'taskListNote',
      desc: '',
      args: [agent],
    );
  }

  /// `Now`
  String get sectionNow {
    return Intl.message('Now', name: 'sectionNow', desc: '', args: []);
  }

  /// `Earlier`
  String get sectionEarlier {
    return Intl.message('Earlier', name: 'sectionEarlier', desc: '', args: []);
  }

  /// `planning`
  String get taskPlanning {
    return Intl.message('planning', name: 'taskPlanning', desc: '', args: []);
  }

  /// `awaiting approval`
  String get taskAwaiting {
    return Intl.message(
      'awaiting approval',
      name: 'taskAwaiting',
      desc: '',
      args: [],
    );
  }

  /// `running`
  String get taskRunning {
    return Intl.message('running', name: 'taskRunning', desc: '', args: []);
  }

  /// `done`
  String get taskDone {
    return Intl.message('done', name: 'taskDone', desc: '', args: []);
  }

  /// `failed or stopped`
  String get taskFailed {
    return Intl.message(
      'failed or stopped',
      name: 'taskFailed',
      desc: '',
      args: [],
    );
  }

  /// `Ask for a change, or a question about the network (Cmd+Enter)`
  String get askHint {
    return Intl.message(
      'Ask for a change, or a question about the network (Cmd+Enter)',
      name: 'askHint',
      desc: '',
      args: [],
    );
  }

  /// `Ask`
  String get askButton {
    return Intl.message('Ask', name: 'askButton', desc: '', args: []);
  }

  /// `This task`
  String get panelThisTask {
    return Intl.message('This task', name: 'panelThisTask', desc: '', args: []);
  }

  /// `What it may do`
  String get panelMayDo {
    return Intl.message(
      'What it may do',
      name: 'panelMayDo',
      desc: '',
      args: [],
    );
  }

  /// `Task`
  String get factTask {
    return Intl.message('Task', name: 'factTask', desc: '', args: []);
  }

  /// `State`
  String get factTaskState {
    return Intl.message('State', name: 'factTaskState', desc: '', args: []);
  }

  /// `Asked by`
  String get factAskedBy {
    return Intl.message('Asked by', name: 'factAskedBy', desc: '', args: []);
  }

  /// `Events`
  String get factEvents {
    return Intl.message('Events', name: 'factEvents', desc: '', args: []);
  }

  /// `What it read`
  String get whatItRead {
    return Intl.message('What it read', name: 'whatItRead', desc: '', args: []);
  }

  /// `Reading needs no approval. What it reads stays inside your rights and its own.`
  String get readsNote {
    return Intl.message(
      'Reading needs no approval. What it reads stays inside your rights and its own.',
      name: 'readsNote',
      desc: '',
      args: [],
    );
  }

  /// `These are the agent link's own settings. Change them in Links › Edit params.`
  String get mayDoNote {
    return Intl.message(
      'These are the agent link\'s own settings. Change them in Links › Edit params.',
      name: 'mayDoNote',
      desc: '',
      args: [],
    );
  }

  /// `Agent`
  String get factAgent {
    return Intl.message('Agent', name: 'factAgent', desc: '', args: []);
  }

  /// `No assistant on this site. The assistant is the agent link: add it, give it an API key, then ask here.`
  String get noAgent {
    return Intl.message(
      'No assistant on this site. The assistant is the agent link: add it, give it an API key, then ask here.',
      name: 'noAgent',
      desc: '',
      args: [],
    );
  }

  /// `Add the agent link`
  String get addAgent {
    return Intl.message(
      'Add the agent link',
      name: 'addAgent',
      desc: '',
      args: [],
    );
  }

  /// `Ask for a change. The agent reads the tree, writes a plan and waits for your approval. Nothing changes until you approve.`
  String get noTasks {
    return Intl.message(
      'Ask for a change. The agent reads the tree, writes a plan and waits for your approval. Nothing changes until you approve.',
      name: 'noTasks',
      desc: '',
      args: [],
    );
  }

  /// `Plan`
  String get planCard {
    return Intl.message('Plan', name: 'planCard', desc: '', args: []);
  }

  /// `The plan is in the task's record. Studio shows it when the gateway can read documents (docs/studio.md §10 item 11). Read it with wyrm-agent for now.`
  String get planNote {
    return Intl.message(
      'The plan is in the task\'s record. Studio shows it when the gateway can read documents (docs/studio.md §10 item 11). Read it with wyrm-agent for now.',
      name: 'planNote',
      desc: '',
      args: [],
    );
  }

  /// `The task is done. Its record keeps the plan and the log.`
  String get doneNote {
    return Intl.message(
      'The task is done. Its record keeps the plan and the log.',
      name: 'doneNote',
      desc: '',
      args: [],
    );
  }

  /// `The task stopped. What was done stays done.`
  String get failedNote {
    return Intl.message(
      'The task stopped. What was done stays done.',
      name: 'failedNote',
      desc: '',
      args: [],
    );
  }

  /// `The agent works on it. Cancel stops it; what was done stays done.`
  String get runningNote {
    return Intl.message(
      'The agent works on it. Cancel stops it; what was done stays done.',
      name: 'runningNote',
      desc: '',
      args: [],
    );
  }

  /// `Approving needs the gateway to sign the steps for you (docs/studio.md §10 item 1). Approve with wyrm-agent for now.`
  String get approveReasonNote {
    return Intl.message(
      'Approving needs the gateway to sign the steps for you (docs/studio.md §10 item 1). Approve with wyrm-agent for now.',
      name: 'approveReasonNote',
      desc: '',
      args: [],
    );
  }

  /// `Cancel task`
  String get cancelTask {
    return Intl.message('Cancel task', name: 'cancelTask', desc: '', args: []);
  }

  /// `Model`
  String get cfgModel {
    return Intl.message('Model', name: 'cfgModel', desc: '', args: []);
  }

  /// `Approval for`
  String get cfgApproval {
    return Intl.message(
      'Approval for',
      name: 'cfgApproval',
      desc: '',
      args: [],
    );
  }

  /// `May change`
  String get cfgPrefixes {
    return Intl.message('May change', name: 'cfgPrefixes', desc: '', args: []);
  }

  /// `Tokens a day`
  String get cfgBudget {
    return Intl.message('Tokens a day', name: 'cfgBudget', desc: '', args: []);
  }

  /// `API key secret`
  String get cfgApiKey {
    return Intl.message(
      'API key secret',
      name: 'cfgApiKey',
      desc: '',
      args: [],
    );
  }

  /// `The tree shows data only.`
  String get treeNoteLead {
    return Intl.message(
      'The tree shows data only.',
      name: 'treeNoteLead',
      desc: '',
      args: [],
    );
  }

  /// `is edited in`
  String get treeNoteMiddle {
    return Intl.message(
      'is edited in',
      name: 'treeNoteMiddle',
      desc: '',
      args: [],
    );
  }

  /// `and`
  String get andWord {
    return Intl.message('and', name: 'andWord', desc: '', args: []);
  }

  /// `Filter`
  String get filter {
    return Intl.message('Filter', name: 'filter', desc: '', args: []);
  }

  /// `Copy key`
  String get copyKey {
    return Intl.message('Copy key', name: 'copyKey', desc: '', args: []);
  }

  /// `Copy keys`
  String get copyKeys {
    return Intl.message('Copy keys', name: 'copyKeys', desc: '', args: []);
  }

  /// `Key copied`
  String get keyCopied {
    return Intl.message('Key copied', name: 'keyCopied', desc: '', args: []);
  }

  /// `{count} keys copied`
  String keysCopied(Object count) {
    return Intl.message(
      '$count keys copied',
      name: 'keysCopied',
      desc: '',
      args: [count],
    );
  }

  /// `Value copied`
  String get valueCopied {
    return Intl.message(
      'Value copied',
      name: 'valueCopied',
      desc: '',
      args: [],
    );
  }

  /// `Ping`
  String get ping {
    return Intl.message('Ping', name: 'ping', desc: '', args: []);
  }

  /// `Add point`
  String get addPoint {
    return Intl.message('Add point', name: 'addPoint', desc: '', args: []);
  }

  /// `Import CSV or DSA tree`
  String get importPoints {
    return Intl.message(
      'Import CSV or DSA tree',
      name: 'importPoints',
      desc: '',
      args: [],
    );
  }

  /// `Apply profile`
  String get applyProfile {
    return Intl.message(
      'Apply profile',
      name: 'applyProfile',
      desc: '',
      args: [],
    );
  }

  /// `Filter points`
  String get filterPoints {
    return Intl.message(
      'Filter points',
      name: 'filterPoints',
      desc: '',
      args: [],
    );
  }

  /// `Register`
  String get colRegister {
    return Intl.message('Register', name: 'colRegister', desc: '', args: []);
  }

  /// `Unit`
  String get colUnit {
    return Intl.message('Unit', name: 'colUnit', desc: '', args: []);
  }

  /// `Poll`
  String get colPoll {
    return Intl.message('Poll', name: 'colPoll', desc: '', args: []);
  }

  /// `What`
  String get colOp {
    return Intl.message('What', name: 'colOp', desc: '', args: []);
  }

  /// `Result`
  String get colResult {
    return Intl.message('Result', name: 'colResult', desc: '', args: []);
  }

  /// `was`
  String get wasWord {
    return Intl.message('was', name: 'wasWord', desc: '', args: []);
  }

  /// `No points yet`
  String get noPointsYet {
    return Intl.message(
      'No points yet',
      name: 'noPointsYet',
      desc: '',
      args: [],
    );
  }

  /// `{count} selected`
  String nSelected(Object count) {
    return Intl.message(
      '$count selected',
      name: 'nSelected',
      desc: '',
      args: [count],
    );
  }

  /// `Set poll…`
  String get setPoll {
    return Intl.message('Set poll…', name: 'setPoll', desc: '', args: []);
  }

  /// `Record in history…`
  String get recordInHistory {
    return Intl.message(
      'Record in history…',
      name: 'recordInHistory',
      desc: '',
      args: [],
    );
  }

  /// `Remove…`
  String get removeEllipsis {
    return Intl.message('Remove…', name: 'removeEllipsis', desc: '', args: []);
  }

  /// `Clear`
  String get clearSelection {
    return Intl.message('Clear', name: 'clearSelection', desc: '', args: []);
  }

  /// `not applied`
  String get notApplied {
    return Intl.message('not applied', name: 'notApplied', desc: '', args: []);
  }

  /// `stale`
  String get stale {
    return Intl.message('stale', name: 'stale', desc: '', args: []);
  }

  /// `last read {time}`
  String lastRead(Object time) {
    return Intl.message(
      'last read $time',
      name: 'lastRead',
      desc: '',
      args: [time],
    );
  }

  /// `unit {unit}`
  String unitNumber(Object unit) {
    return Intl.message(
      'unit $unit',
      name: 'unitNumber',
      desc: '',
      args: [unit],
    );
  }

  /// `device`
  String get kindDevice {
    return Intl.message('device', name: 'kindDevice', desc: '', args: []);
  }

  /// `connection`
  String get kindConnection {
    return Intl.message(
      'connection',
      name: 'kindConnection',
      desc: '',
      args: [],
    );
  }

  /// `link`
  String get kindLink {
    return Intl.message('link', name: 'kindLink', desc: '', args: []);
  }

  /// `node`
  String get kindNode {
    return Intl.message('node', name: 'kindNode', desc: '', args: []);
  }

  /// `Point`
  String get insPoint {
    return Intl.message('Point', name: 'insPoint', desc: '', args: []);
  }

  /// `Action`
  String get insAction {
    return Intl.message('Action', name: 'insAction', desc: '', args: []);
  }

  /// `Device`
  String get insDevice {
    return Intl.message('Device', name: 'insDevice', desc: '', args: []);
  }

  /// `Connection`
  String get insConnection {
    return Intl.message(
      'Connection',
      name: 'insConnection',
      desc: '',
      args: [],
    );
  }

  /// `Link`
  String get insLink {
    return Intl.message('Link', name: 'insLink', desc: '', args: []);
  }

  /// `Node`
  String get insNode {
    return Intl.message('Node', name: 'insNode', desc: '', args: []);
  }

  /// `Register`
  String get secRegister {
    return Intl.message('Register', name: 'secRegister', desc: '', args: []);
  }

  /// `Value`
  String get secValue {
    return Intl.message('Value', name: 'secValue', desc: '', args: []);
  }

  /// `Polling`
  String get secPolling {
    return Intl.message('Polling', name: 'secPolling', desc: '', args: []);
  }

  /// `Write`
  String get secWrite {
    return Intl.message('Write', name: 'secWrite', desc: '', args: []);
  }

  /// `What the tree will publish`
  String get secPublish {
    return Intl.message(
      'What the tree will publish',
      name: 'secPublish',
      desc: '',
      args: [],
    );
  }

  /// `Parameters`
  String get secParameters {
    return Intl.message(
      'Parameters',
      name: 'secParameters',
      desc: '',
      args: [],
    );
  }

  /// `Diagnostics`
  String get secDiagnostics {
    return Intl.message(
      'Diagnostics',
      name: 'secDiagnostics',
      desc: '',
      args: [],
    );
  }

  /// `Attributes`
  String get secAttributes {
    return Intl.message(
      'Attributes',
      name: 'secAttributes',
      desc: '',
      args: [],
    );
  }

  /// `staged · was {was}`
  String stagedWas(Object was) {
    return Intl.message(
      'staged · was $was',
      name: 'stagedWas',
      desc: '',
      args: [was],
    );
  }

  /// `Turning this on needs {level} level`
  String writableNeeds(Object level) {
    return Intl.message(
      'Turning this on needs $level level',
      name: 'writableNeeds',
      desc: '',
      args: [level],
    );
  }

  /// `Area`
  String get fieldArea {
    return Intl.message('Area', name: 'fieldArea', desc: '', args: []);
  }

  /// `Address`
  String get fieldAddress {
    return Intl.message('Address', name: 'fieldAddress', desc: '', args: []);
  }

  /// `Data type`
  String get fieldDataType {
    return Intl.message('Data type', name: 'fieldDataType', desc: '', args: []);
  }

  /// `Word order`
  String get fieldWordOrder {
    return Intl.message(
      'Word order',
      name: 'fieldWordOrder',
      desc: '',
      args: [],
    );
  }

  /// `Unit`
  String get fieldUnit {
    return Intl.message('Unit', name: 'fieldUnit', desc: '', args: []);
  }

  /// `Scale`
  String get fieldScale {
    return Intl.message('Scale', name: 'fieldScale', desc: '', args: []);
  }

  /// `Offset`
  String get fieldOffset {
    return Intl.message('Offset', name: 'fieldOffset', desc: '', args: []);
  }

  /// `Precision`
  String get fieldPrecision {
    return Intl.message(
      'Precision',
      name: 'fieldPrecision',
      desc: '',
      args: [],
    );
  }

  /// `Bit`
  String get fieldBit {
    return Intl.message('Bit', name: 'fieldBit', desc: '', args: []);
  }

  /// `Registers`
  String get fieldRegisters {
    return Intl.message(
      'Registers',
      name: 'fieldRegisters',
      desc: '',
      args: [],
    );
  }

  /// `Writable`
  String get fieldWritable {
    return Intl.message('Writable', name: 'fieldWritable', desc: '', args: []);
  }

  /// `Writable by the master`
  String get fieldWritableByMaster {
    return Intl.message(
      'Writable by the master',
      name: 'fieldWritableByMaster',
      desc: '',
      args: [],
    );
  }

  /// `Set by the data type: its _wswap, _bswap or _wbswap suffix.`
  String get wordOrderReason {
    return Intl.message(
      'Set by the data type: its _wswap, _bswap or _wbswap suffix.',
      name: 'wordOrderReason',
      desc: '',
      args: [],
    );
  }

  /// `The driver has no {param} parameter.`
  String noParamReason(Object param) {
    return Intl.message(
      'The driver has no $param parameter.',
      name: 'noParamReason',
      desc: '',
      args: [param],
    );
  }

  /// `This point has no edit action.`
  String get noEditReason {
    return Intl.message(
      'This point has no edit action.',
      name: 'noEditReason',
      desc: '',
      args: [],
    );
  }

  /// `This node has no ping action: the driver pings by itself (cfg ping).`
  String get noPingReason {
    return Intl.message(
      'This node has no ping action: the driver pings by itself (cfg ping).',
      name: 'noPingReason',
      desc: '',
      args: [],
    );
  }

  /// `The broker has no action to apply a profile to a device yet.`
  String get noProfileReason {
    return Intl.message(
      'The broker has no action to apply a profile to a device yet.',
      name: 'noProfileReason',
      desc: '',
      args: [],
    );
  }

  /// `This node has no {action} action.`
  String noActionReason(Object action) {
    return Intl.message(
      'This node has no $action action.',
      name: 'noActionReason',
      desc: '',
      args: [action],
    );
  }

  /// `Recording a point is set up in History (watch groups).`
  String get noHistoryAction {
    return Intl.message(
      'Recording a point is set up in History (watch groups).',
      name: 'noHistoryAction',
      desc: '',
      args: [],
    );
  }

  /// `The broker has no call to send a request to an admin yet.`
  String get askAdminReason {
    return Intl.message(
      'The broker has no call to send a request to an admin yet.',
      name: 'askAdminReason',
      desc: '',
      args: [],
    );
  }

  /// `The audit needs config on sys/audit.`
  String get auditNeeds {
    return Intl.message(
      'The audit needs config on sys/audit.',
      name: 'auditNeeds',
      desc: '',
      args: [],
    );
  }

  /// `done`
  String get auditDone {
    return Intl.message('done', name: 'auditDone', desc: '', args: []);
  }

  /// `refused ({code})`
  String auditRefused(Object code) {
    return Intl.message(
      'refused ($code)',
      name: 'auditRefused',
      desc: '',
      args: [code],
    );
  }

  /// `Select a point in the table to see its history.`
  String get pickAPoint {
    return Intl.message(
      'Select a point in the table to see its history.',
      name: 'pickAPoint',
      desc: '',
      args: [],
    );
  }

  /// `Site {site} · applied with your rights: {user}, {role} ({level})`
  String rightsLine(Object site, Object user, Object role, Object level) {
    return Intl.message(
      'Site $site · applied with your rights: $user, $role ($level)',
      name: 'rightsLine',
      desc: '',
      args: [site, user, role, level],
    );
  }

  /// `{count, plural, =1{Apply 1 change} other{Apply {count} changes}}`
  String applyChanges(num count) {
    return Intl.plural(
      count,
      one: 'Apply 1 change',
      other: 'Apply $count changes',
      name: 'applyChanges',
      desc: '',
      args: [count],
    );
  }

  /// `Ask an admin for {count}`
  String askAdminFor(Object count) {
    return Intl.message(
      'Ask an admin for $count',
      name: 'askAdminFor',
      desc: '',
      args: [count],
    );
  }

  /// `Each write is checked by the link and recorded in {audit}. A value shows only after it is read back.`
  String reviewNote(Object audit) {
    return Intl.message(
      'Each write is checked by the link and recorded in $audit. A value shows only after it is read back.',
      name: 'reviewNote',
      desc: '',
      args: [audit],
    );
  }

  /// `Close`
  String get closeLabel {
    return Intl.message('Close', name: 'closeLabel', desc: '', args: []);
  }

  /// `Discard all`
  String get discardAll {
    return Intl.message('Discard all', name: 'discardAll', desc: '', args: []);
  }

  /// `{kind} · {count} actions`
  String menuSubtitle(Object kind, Object count) {
    return Intl.message(
      '$kind · $count actions',
      name: 'menuSubtitle',
      desc: '',
      args: [kind, count],
    );
  }

  /// `Other`
  String get menuOther {
    return Intl.message('Other', name: 'menuOther', desc: '', args: []);
  }

  /// `No records for this node in the last 500 of sys/audit.`
  String get noAuditHere {
    return Intl.message(
      'No records for this node in the last 500 of sys/audit.',
      name: 'noAuditHere',
      desc: '',
      args: [],
    );
  }

  /// `My blocks`
  String get paletteMyBlocks {
    return Intl.message(
      'My blocks',
      name: 'paletteMyBlocks',
      desc: '',
      args: [],
    );
  }

  /// `Needs own blocks in the engine`
  String get myBlocksReason {
    return Intl.message(
      'Needs own blocks in the engine',
      name: 'myBlocksReason',
      desc: '',
      args: [],
    );
  }

  /// `Find a block`
  String get findBlock {
    return Intl.message('Find a block', name: 'findBlock', desc: '', args: []);
  }

  /// `Find a point or action`
  String get findInTree {
    return Intl.message(
      'Find a point or action',
      name: 'findInTree',
      desc: '',
      args: [],
    );
  }

  /// `Draft saved`
  String get draftSaved {
    return Intl.message('Draft saved', name: 'draftSaved', desc: '', args: []);
  }

  /// `Version {v} · deployed`
  String versionDeployed(Object v) {
    return Intl.message(
      'Version $v · deployed',
      name: 'versionDeployed',
      desc: '',
      args: [v],
    );
  }

  /// `reads a value`
  String get legendReads {
    return Intl.message(
      'reads a value',
      name: 'legendReads',
      desc: '',
      args: [],
    );
  }

  /// `writes to a device`
  String get legendWrites {
    return Intl.message(
      'writes to a device',
      name: 'legendWrites',
      desc: '',
      args: [],
    );
  }

  /// `free field`
  String get legendFree {
    return Intl.message('free field', name: 'legendFree', desc: '', args: []);
  }

  /// `no left port = read-only point`
  String get legendReadOnly {
    return Intl.message(
      'no left port = read-only point',
      name: 'legendReadOnly',
      desc: '',
      args: [],
    );
  }

  /// `Tree node`
  String get kindTreeNode {
    return Intl.message('Tree node', name: 'kindTreeNode', desc: '', args: []);
  }

  /// `Logic block`
  String get kindLogic {
    return Intl.message('Logic block', name: 'kindLogic', desc: '', args: []);
  }

  /// `Sink`
  String get kindSink {
    return Intl.message('Sink', name: 'kindSink', desc: '', args: []);
  }

  /// `Action`
  String get kindAction {
    return Intl.message('Action', name: 'kindAction', desc: '', args: []);
  }

  /// `Flow`
  String get kindFlow {
    return Intl.message('Flow', name: 'kindFlow', desc: '', args: []);
  }

  /// `A bound field shows the value that comes in; its wire and source light when you point at it. The link icon goes to the source or unbinds.`
  String get flowPropertiesNote2 {
    return Intl.message(
      'A bound field shows the value that comes in; its wire and source light when you point at it. The link icon goes to the source or unbinds.',
      name: 'flowPropertiesNote2',
      desc: '',
      args: [],
    );
  }

  /// `not bound`
  String get notBound {
    return Intl.message('not bound', name: 'notBound', desc: '', args: []);
  }

  /// `{n, plural, =1{1 input} other{{n} inputs}}`
  String inputsCount(num n) {
    return Intl.plural(
      n,
      one: '1 input',
      other: '$n inputs',
      name: 'inputsCount',
      desc: '',
      args: [n],
    );
  }

  /// `Add an input`
  String get addInput {
    return Intl.message('Add an input', name: 'addInput', desc: '', args: []);
  }

  /// `Remove the last input`
  String get removeInput {
    return Intl.message(
      'Remove the last input',
      name: 'removeInput',
      desc: '',
      args: [],
    );
  }

  /// `{n, plural, =1{1 case} other{{n} cases}}`
  String pairsCount(num n) {
    return Intl.plural(
      n,
      one: '1 case',
      other: '$n cases',
      name: 'pairsCount',
      desc: '',
      args: [n],
    );
  }

  /// `Add a case`
  String get addPair {
    return Intl.message('Add a case', name: 'addPair', desc: '', args: []);
  }

  /// `Remove the last case`
  String get removePair {
    return Intl.message(
      'Remove the last case',
      name: 'removePair',
      desc: '',
      args: [],
    );
  }

  /// `Unbind`
  String get unbind {
    return Intl.message('Unbind', name: 'unbind', desc: '', args: []);
  }

  /// `Drag an output here to bind`
  String get bindHint {
    return Intl.message(
      'Drag an output here to bind',
      name: 'bindHint',
      desc: '',
      args: [],
    );
  }

  /// `Deployed by`
  String get factDeployedBy {
    return Intl.message(
      'Deployed by',
      name: 'factDeployedBy',
      desc: '',
      args: [],
    );
  }

  /// `May write`
  String get factMayWrite {
    return Intl.message('May write', name: 'factMayWrite', desc: '', args: []);
  }

  /// `Reads`
  String get factReads {
    return Intl.message('Reads', name: 'factReads', desc: '', args: []);
  }

  /// `Writes`
  String get factWrites {
    return Intl.message('Writes', name: 'factWrites', desc: '', args: []);
  }

  /// `Problems`
  String get problems {
    return Intl.message('Problems', name: 'problems', desc: '', args: []);
  }

  /// `Point`
  String get treePoint {
    return Intl.message('Point', name: 'treePoint', desc: '', args: []);
  }

  /// `on a block: adds it as a field. On the canvas: a new block of that node.`
  String get treePointNote {
    return Intl.message(
      'on a block: adds it as a field. On the canvas: a new block of that node.',
      name: 'treePointNote',
      desc: '',
      args: [],
    );
  }

  /// `Action`
  String get treeAction {
    return Intl.message('Action', name: 'treeAction', desc: '', args: []);
  }

  /// `a block that runs it when run when turns true; its arguments are fields.`
  String get treeActionNote {
    return Intl.message(
      'a block that runs it when run when turns true; its arguments are fields.',
      name: 'treeActionNote',
      desc: '',
      args: [],
    );
  }

  /// `{n} in`
  String actionInputs(Object n) {
    return Intl.message('$n in', name: 'actionInputs', desc: '', args: [n]);
  }

  /// `A point of the tree. A read-only point has no input; binding into a writable one writes ~set.`
  String get noteTreeNode {
    return Intl.message(
      'A point of the tree. A read-only point has no input; binding into a writable one writes ~set.',
      name: 'noteTreeNode',
      desc: '',
      args: [],
    );
  }

  /// `Dragged from the tree. Runs when run when turns true.`
  String get noteAction {
    return Intl.message(
      'Dragged from the tree. Runs when run when turns true.',
      name: 'noteAction',
      desc: '',
      args: [],
    );
  }

  /// `Live values`
  String get factLive {
    return Intl.message('Live values', name: 'factLive', desc: '', args: []);
  }

  /// `You cannot read every source and target of this flow`
  String get liveRefused {
    return Intl.message(
      'You cannot read every source and target of this flow',
      name: 'liveRefused',
      desc: '',
      args: [],
    );
  }

  /// `fires at deploy`
  String get firesAtDeploy {
    return Intl.message(
      'fires at deploy',
      name: 'firesAtDeploy',
      desc: '',
      args: [],
    );
  }

  /// `A parameter sends its value when the flow starts, so this writes at every deploy.`
  String get firesAtDeployNote {
    return Intl.message(
      'A parameter sends its value when the flow starts, so this writes at every deploy.',
      name: 'firesAtDeployNote',
      desc: '',
      args: [],
    );
  }

  /// `Contents`
  String get tabContents {
    return Intl.message('Contents', name: 'tabContents', desc: '', args: []);
  }

  /// `folder`
  String get kindFolder {
    return Intl.message('folder', name: 'kindFolder', desc: '', args: []);
  }

  /// `dataflow`
  String get kindDataflow {
    return Intl.message('dataflow', name: 'kindDataflow', desc: '', args: []);
  }

  /// `storage`
  String get kindStorage {
    return Intl.message('storage', name: 'kindStorage', desc: '', args: []);
  }

  /// `broker`
  String get kindBroker {
    return Intl.message('broker', name: 'kindBroker', desc: '', args: []);
  }

  /// `Folder`
  String get insFolder {
    return Intl.message('Folder', name: 'insFolder', desc: '', args: []);
  }

  /// `Storage`
  String get insStorage {
    return Intl.message('Storage', name: 'insStorage', desc: '', args: []);
  }

  /// `Broker`
  String get insBroker {
    return Intl.message('Broker', name: 'insBroker', desc: '', args: []);
  }

  /// `State`
  String get secState {
    return Intl.message('State', name: 'secState', desc: '', args: []);
  }

  /// `Since`
  String get factSince {
    return Intl.message('Since', name: 'factSince', desc: '', args: []);
  }

  /// `deployed by {who}`
  String deployedByWho(Object who) {
    return Intl.message(
      'deployed by $who',
      name: 'deployedByWho',
      desc: '',
      args: [who],
    );
  }

  /// `{count, plural, =0{no children} =1{1 child} other{{count} children}}`
  String childCount(num count) {
    return Intl.plural(
      count,
      zero: 'no children',
      one: '1 child',
      other: '$count children',
      name: 'childCount',
      desc: '',
      args: [count],
    );
  }

  /// `Nothing under this node.`
  String get noChildren {
    return Intl.message(
      'Nothing under this node.',
      name: 'noChildren',
      desc: '',
      args: [],
    );
  }

  /// `Select a row: a node opens in the tree, a value opens in the inspector.`
  String get childrenNote {
    return Intl.message(
      'Select a row: a node opens in the tree, a value opens in the inspector.',
      name: 'childrenNote',
      desc: '',
      args: [],
    );
  }

  /// `Opening the editor needs read on this flow.`
  String get noReadFlow {
    return Intl.message(
      'Opening the editor needs read on this flow.',
      name: 'noReadFlow',
      desc: '',
      args: [],
    );
  }

  /// `Name`
  String get colName {
    return Intl.message('Name', name: 'colName', desc: '', args: []);
  }

  /// `Kind`
  String get colKind {
    return Intl.message('Kind', name: 'colKind', desc: '', args: []);
  }

  /// `Outputs cannot be bound`
  String get refuseOutput {
    return Intl.message(
      'Outputs cannot be bound',
      name: 'refuseOutput',
      desc: '',
      args: [],
    );
  }

  /// `{field} takes no input: type its value`
  String refuseNoInput(String field) {
    return Intl.message(
      '$field takes no input: type its value',
      name: 'refuseNoInput',
      desc: '',
      args: [field],
    );
  }

  /// `A block cannot feed itself`
  String get refuseSelf {
    return Intl.message(
      'A block cannot feed itself',
      name: 'refuseSelf',
      desc: '',
      args: [],
    );
  }

  /// `{from} does not fit {to}`
  String refuseType(String from, String to) {
    return Intl.message(
      '$from does not fit $to',
      name: 'refuseType',
      desc: '',
      args: [from, to],
    );
  }

  /// `This closes a loop (only a delay may)`
  String get refuseLoop {
    return Intl.message(
      'This closes a loop (only a delay may)',
      name: 'refuseLoop',
      desc: '',
      args: [],
    );
  }

  /// `Form`
  String get blockForm {
    return Intl.message('Form', name: 'blockForm', desc: '', args: []);
  }

  /// `Go to source`
  String get goToSource {
    return Intl.message('Go to source', name: 'goToSource', desc: '', args: []);
  }

  /// `bound`
  String get boundMark {
    return Intl.message('bound', name: 'boundMark', desc: '', args: []);
  }

  /// `would write {value}`
  String wouldWrite(String value) {
    return Intl.message(
      'would write $value',
      name: 'wouldWrite',
      desc: '',
      args: [value],
    );
  }

  /// `would run on {value}`
  String wouldRun(String value) {
    return Intl.message(
      'would run on $value',
      name: 'wouldRun',
      desc: '',
      args: [value],
    );
  }

  /// `preview`
  String get previewTag {
    return Intl.message('preview', name: 'previewTag', desc: '', args: []);
  }

  /// `Values`
  String get factValues {
    return Intl.message('Values', name: 'factValues', desc: '', args: []);
  }

  /// `a preview of the draft; nothing is written`
  String get valuesPreview {
    return Intl.message(
      'a preview of the draft; nothing is written',
      name: 'valuesPreview',
      desc: '',
      args: [],
    );
  }

  /// `the deployed version`
  String get valuesDeployed {
    return Intl.message(
      'the deployed version',
      name: 'valuesDeployed',
      desc: '',
      args: [],
    );
  }

  /// `The draft does not run: {message}`
  String previewInvalid(String message) {
    return Intl.message(
      'The draft does not run: $message',
      name: 'previewInvalid',
      desc: '',
      args: [message],
    );
  }

  /// `This field sends its value when the flow starts, so this wire writes at every deploy.`
  String get firesAtStartNote {
    return Intl.message(
      'This field sends its value when the flow starts, so this wire writes at every deploy.',
      name: 'firesAtStartNote',
      desc: '',
      args: [],
    );
  }

  /// `to a broker’s gateway. Your role there decides what you can change.`
  String get logInLead {
    return Intl.message(
      'to a broker’s gateway. Your role there decides what you can change.',
      name: 'logInLead',
      desc: '',
      args: [],
    );
  }

  /// `Gateway`
  String get gateway {
    return Intl.message('Gateway', name: 'gateway', desc: '', args: []);
  }

  /// `Remember the gateway and user on this computer`
  String get rememberGatewayAndUser {
    return Intl.message(
      'Remember the gateway and user on this computer',
      name: 'rememberGatewayAndUser',
      desc: '',
      args: [],
    );
  }

  /// `Signing in…`
  String get signingIn {
    return Intl.message('Signing in…', name: 'signingIn', desc: '', args: []);
  }

  /// `Reaching {host}`
  String stepReaching(Object host) {
    return Intl.message(
      'Reaching $host',
      name: 'stepReaching',
      desc: '',
      args: [host],
    );
  }

  /// `Checking user and password`
  String get stepChecking {
    return Intl.message(
      'Checking user and password',
      name: 'stepChecking',
      desc: '',
      args: [],
    );
  }

  /// `Reading your role and sites`
  String get stepReading {
    return Intl.message(
      'Reading your role and sites',
      name: 'stepReading',
      desc: '',
      args: [],
    );
  }

  /// `User or password is wrong. Ask an administrator to reset it; the gateway never sends it by mail.`
  String get wrongPassword {
    return Intl.message(
      'User or password is wrong. Ask an administrator to reset it; the gateway never sends it by mail.',
      name: 'wrongPassword',
      desc: '',
      args: [],
    );
  }

  /// `Can’t reach this gateway`
  String get cantReachGateway {
    return Intl.message(
      'Can’t reach this gateway',
      name: 'cantReachGateway',
      desc: '',
      args: [],
    );
  }

  /// `The broker may be restarting or this computer is on another network.`
  String get unreachableAdvice {
    return Intl.message(
      'The broker may be restarting or this computer is on another network.',
      name: 'unreachableAdvice',
      desc: '',
      args: [],
    );
  }

  /// `Its standby answers at`
  String get standbyAnswersAt {
    return Intl.message(
      'Its standby answers at',
      name: 'standbyAnswersAt',
      desc: '',
      args: [],
    );
  }

  /// `Try again`
  String get tryAgain {
    return Intl.message('Try again', name: 'tryAgain', desc: '', args: []);
  }

  /// `Use the standby`
  String get useStandby {
    return Intl.message(
      'Use the standby',
      name: 'useStandby',
      desc: '',
      args: [],
    );
  }

  /// `TLS · certificate of the {site} CA`
  String tlsCertificateOf(Object site) {
    return Intl.message(
      'TLS · certificate of the $site CA',
      name: 'tlsCertificateOf',
      desc: '',
      args: [site],
    );
  }

  /// `Add a standby gateway`
  String get addStandby {
    return Intl.message(
      'Add a standby gateway',
      name: 'addStandby',
      desc: '',
      args: [],
    );
  }

  /// `Standby: {host}`
  String standbyIs(Object host) {
    return Intl.message(
      'Standby: $host',
      name: 'standbyIs',
      desc: '',
      args: [host],
    );
  }

  /// `Standby gateway`
  String get standbyGateway {
    return Intl.message(
      'Standby gateway',
      name: 'standbyGateway',
      desc: '',
      args: [],
    );
  }

  /// `Studio {version} · {language}`
  String studioVersion(Object version, Object language) {
    return Intl.message(
      'Studio $version · $language',
      name: 'studioVersion',
      desc: '',
      args: [version, language],
    );
  }

  /// `English`
  String get languageName {
    return Intl.message('English', name: 'languageName', desc: '', args: []);
  }

  /// `{host} · answered in {ms} ms`
  String gatewayAnswered(Object host, Object ms) {
    return Intl.message(
      '$host · answered in $ms ms',
      name: 'gatewayAnswered',
      desc: '',
      args: [host, ms],
    );
  }

  /// `No answer from {host}`
  String gatewayNoAnswer(Object host) {
    return Intl.message(
      'No answer from $host',
      name: 'gatewayNoAnswer',
      desc: '',
      args: [host],
    );
  }

  /// `Checking the gateway`
  String get checkingGateway {
    return Intl.message(
      'Checking the gateway',
      name: 'checkingGateway',
      desc: '',
      args: [],
    );
  }

  /// `Welcome, {user}`
  String welcomeUser(Object user) {
    return Intl.message(
      'Welcome, $user',
      name: 'welcomeUser',
      desc: '',
      args: [user],
    );
  }

  /// `Opening the tree of {site}…`
  String openingTreeOf(Object site) {
    return Intl.message(
      'Opening the tree of $site…',
      name: 'openingTreeOf',
      desc: '',
      args: [site],
    );
  }

  /// `Opening the tree`
  String get openingTree {
    return Intl.message(
      'Opening the tree',
      name: 'openingTree',
      desc: '',
      args: [],
    );
  }

  /// `{role} on {site}`
  String roleOnSite(Object role, Object site) {
    return Intl.message(
      '$role on $site',
      name: 'roleOnSite',
      desc: '',
      args: [role, site],
    );
  }

  /// `reaches {sites}`
  String reachesSites(Object sites) {
    return Intl.message(
      'reaches $sites',
      name: 'reachesSites',
      desc: '',
      args: [sites],
    );
  }

  /// `{first} and {last}`
  String listAnd(Object first, Object last) {
    return Intl.message(
      '$first and $last',
      name: 'listAnd',
      desc: '',
      args: [first, last],
    );
  }

  /// `{n, plural, =1{1 link} other{{n} links}}`
  String linksCount(num n) {
    return Intl.plural(
      n,
      one: '1 link',
      other: '$n links',
      name: 'linksCount',
      desc: '',
      args: [n],
    );
  }

  /// `Show password`
  String get showPassword {
    return Intl.message(
      'Show password',
      name: 'showPassword',
      desc: '',
      args: [],
    );
  }

  /// `Hide password`
  String get hidePassword {
    return Intl.message(
      'Hide password',
      name: 'hidePassword',
      desc: '',
      args: [],
    );
  }

  /// `Every device, link and site`
  String get heroHeadline1 {
    return Intl.message(
      'Every device, link and site',
      name: 'heroHeadline1',
      desc: '',
      args: [],
    );
  }

  /// `in one living tree.`
  String get heroHeadline2 {
    return Intl.message(
      'in one living tree.',
      name: 'heroHeadline2',
      desc: '',
      args: [],
    );
  }

  /// `Browse what your brokers hold, add links, let devices in, connect sites and build flows. Nothing changes until you apply it.`
  String get heroLead {
    return Intl.message(
      'Browse what your brokers hold, add links, let devices in, connect sites and build flows. Nothing changes until you apply it.',
      name: 'heroLead',
      desc: '',
      args: [],
    );
  }

  /// `values flowing`
  String get legendValues {
    return Intl.message(
      'values flowing',
      name: 'legendValues',
      desc: '',
      args: [],
    );
  }

  /// `commands`
  String get legendCommands {
    return Intl.message('commands', name: 'legendCommands', desc: '', args: []);
  }

  /// `The animation is decoration; it stops when the system asks for less motion.`
  String get legendNote {
    return Intl.message(
      'The animation is decoration; it stops when the system asks for less motion.',
      name: 'legendNote',
      desc: '',
      args: [],
    );
  }

  /// `Reading the tree of {site}`
  String preloadTree(Object site) {
    return Intl.message(
      'Reading the tree of $site',
      name: 'preloadTree',
      desc: '',
      args: [site],
    );
  }

  /// `Reading the flows`
  String get preloadFlows {
    return Intl.message(
      'Reading the flows',
      name: 'preloadFlows',
      desc: '',
      args: [],
    );
  }

  /// `Reading the flow blocks`
  String get preloadBlocks {
    return Intl.message(
      'Reading the flow blocks',
      name: 'preloadBlocks',
      desc: '',
      args: [],
    );
  }

  /// `Reading the links`
  String get preloadLinks {
    return Intl.message(
      'Reading the links',
      name: 'preloadLinks',
      desc: '',
      args: [],
    );
  }

  /// `Reading the sites`
  String get preloadSites {
    return Intl.message(
      'Reading the sites',
      name: 'preloadSites',
      desc: '',
      args: [],
    );
  }

  /// `{step} · later`
  String preloadLater(Object step) {
    return Intl.message(
      '$step · later',
      name: 'preloadLater',
      desc: '',
      args: [step],
    );
  }

  /// `Updating…`
  String get updating {
    return Intl.message('Updating…', name: 'updating', desc: '', args: []);
  }

  /// `View value`
  String get viewValue {
    return Intl.message('View value', name: 'viewValue', desc: '', args: []);
  }

  /// `Copy`
  String get copyValue {
    return Intl.message('Copy', name: 'copyValue', desc: '', args: []);
  }

  /// `Copied`
  String get copiedValue {
    return Intl.message('Copied', name: 'copiedValue', desc: '', args: []);
  }

  /// `{count, plural, =1{1 key} other{{count} keys}}`
  String sizeKeys(int count) {
    return Intl.plural(
      count,
      one: '1 key',
      other: '$count keys',
      name: 'sizeKeys',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 item} other{{count} items}}`
  String sizeItems(int count) {
    return Intl.plural(
      count,
      one: '1 item',
      other: '$count items',
      name: 'sizeItems',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 char} other{{count} chars}}`
  String sizeChars(int count) {
    return Intl.plural(
      count,
      one: '1 char',
      other: '$count chars',
      name: 'sizeChars',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 line} other{{count} lines}}`
  String sizeLines(int count) {
    return Intl.plural(
      count,
      one: '1 line',
      other: '$count lines',
      name: 'sizeLines',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 byte} other{{count} bytes}}`
  String sizeBytes(int count) {
    return Intl.plural(
      count,
      one: '1 byte',
      other: '$count bytes',
      name: 'sizeBytes',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{… 1 more byte} other{… {count} more bytes}}`
  String moreBytes(int count) {
    return Intl.plural(
      count,
      one: '… 1 more byte',
      other: '… $count more bytes',
      name: 'moreBytes',
      desc: '',
      args: [count],
    );
  }

  /// `Keyboard and mouse`
  String get scTitle {
    return Intl.message(
      'Keyboard and mouse',
      name: 'scTitle',
      desc: '',
      args: [],
    );
  }

  /// `Keys work while no text field has the focus.`
  String get scNote {
    return Intl.message(
      'Keys work while no text field has the focus.',
      name: 'scNote',
      desc: '',
      args: [],
    );
  }

  /// `Selection`
  String get scGroupSelect {
    return Intl.message('Selection', name: 'scGroupSelect', desc: '', args: []);
  }

  /// `Editing`
  String get scGroupEdit {
    return Intl.message('Editing', name: 'scGroupEdit', desc: '', args: []);
  }

  /// `View and flow`
  String get scGroupView {
    return Intl.message(
      'View and flow',
      name: 'scGroupView',
      desc: '',
      args: [],
    );
  }

  /// `or`
  String get scOr {
    return Intl.message('or', name: 'scOr', desc: '', args: []);
  }

  /// `Space`
  String get scSpace {
    return Intl.message('Space', name: 'scSpace', desc: '', args: []);
  }

  /// `click`
  String get scClick {
    return Intl.message('click', name: 'scClick', desc: '', args: []);
  }

  /// `double click`
  String get scDoubleClick {
    return Intl.message(
      'double click',
      name: 'scDoubleClick',
      desc: '',
      args: [],
    );
  }

  /// `drag`
  String get scDrag {
    return Intl.message('drag', name: 'scDrag', desc: '', args: []);
  }

  /// `drag on empty canvas`
  String get scDragEmpty {
    return Intl.message(
      'drag on empty canvas',
      name: 'scDragEmpty',
      desc: '',
      args: [],
    );
  }

  /// `drag a header`
  String get scDragHeader {
    return Intl.message(
      'drag a header',
      name: 'scDragHeader',
      desc: '',
      args: [],
    );
  }

  /// `middle button drag`
  String get scMiddleDrag {
    return Intl.message(
      'middle button drag',
      name: 'scMiddleDrag',
      desc: '',
      args: [],
    );
  }

  /// `wheel / two fingers`
  String get scScroll {
    return Intl.message(
      'wheel / two fingers',
      name: 'scScroll',
      desc: '',
      args: [],
    );
  }

  /// `wheel`
  String get scWheel {
    return Intl.message('wheel', name: 'scWheel', desc: '', args: []);
  }

  /// `pinch`
  String get scPinch {
    return Intl.message('pinch', name: 'scPinch', desc: '', args: []);
  }

  /// `10 steps`
  String get scNudgeFar {
    return Intl.message('10 steps', name: 'scNudgeFar', desc: '', args: []);
  }

  /// `Select all`
  String get scSelectAll {
    return Intl.message('Select all', name: 'scSelectAll', desc: '', args: []);
  }

  /// `Select with a marquee`
  String get scMarquee {
    return Intl.message(
      'Select with a marquee',
      name: 'scMarquee',
      desc: '',
      args: [],
    );
  }

  /// `Add to or take from the selection`
  String get scAddToSelection {
    return Intl.message(
      'Add to or take from the selection',
      name: 'scAddToSelection',
      desc: '',
      args: [],
    );
  }

  /// `Move the selection`
  String get scMoveSelection {
    return Intl.message(
      'Move the selection',
      name: 'scMoveSelection',
      desc: '',
      args: [],
    );
  }

  /// `Move by one grid step`
  String get scNudge {
    return Intl.message(
      'Move by one grid step',
      name: 'scNudge',
      desc: '',
      args: [],
    );
  }

  /// `Cancel, clear the selection`
  String get scEscape {
    return Intl.message(
      'Cancel, clear the selection',
      name: 'scEscape',
      desc: '',
      args: [],
    );
  }

  /// `Copy`
  String get scCopy {
    return Intl.message('Copy', name: 'scCopy', desc: '', args: []);
  }

  /// `Cut`
  String get scCut {
    return Intl.message('Cut', name: 'scCut', desc: '', args: []);
  }

  /// `Paste`
  String get scPaste {
    return Intl.message('Paste', name: 'scPaste', desc: '', args: []);
  }

  /// `Duplicate`
  String get scDuplicate {
    return Intl.message('Duplicate', name: 'scDuplicate', desc: '', args: []);
  }

  /// `Delete`
  String get scDelete {
    return Intl.message('Delete', name: 'scDelete', desc: '', args: []);
  }

  /// `Undo`
  String get scUndo {
    return Intl.message('Undo', name: 'scUndo', desc: '', args: []);
  }

  /// `Redo`
  String get scRedo {
    return Intl.message('Redo', name: 'scRedo', desc: '', args: []);
  }

  /// `Unbind a field`
  String get scUnbind {
    return Intl.message('Unbind a field', name: 'scUnbind', desc: '', args: []);
  }

  /// `Pan`
  String get scPan {
    return Intl.message('Pan', name: 'scPan', desc: '', args: []);
  }

  /// `Zoom`
  String get scZoom {
    return Intl.message('Zoom', name: 'scZoom', desc: '', args: []);
  }

  /// `Zoom in`
  String get scZoomIn {
    return Intl.message('Zoom in', name: 'scZoomIn', desc: '', args: []);
  }

  /// `Zoom out`
  String get scZoomOut {
    return Intl.message('Zoom out', name: 'scZoomOut', desc: '', args: []);
  }

  /// `Zoom to 100 %`
  String get scZoomReset {
    return Intl.message(
      'Zoom to 100 %',
      name: 'scZoomReset',
      desc: '',
      args: [],
    );
  }

  /// `Fit all blocks`
  String get scZoomFit {
    return Intl.message(
      'Fit all blocks',
      name: 'scZoomFit',
      desc: '',
      args: [],
    );
  }

  /// `View the value under the pointer`
  String get scViewValue {
    return Intl.message(
      'View the value under the pointer',
      name: 'scViewValue',
      desc: '',
      args: [],
    );
  }

  /// `Find a block`
  String get scSearchPalette {
    return Intl.message(
      'Find a block',
      name: 'scSearchPalette',
      desc: '',
      args: [],
    );
  }

  /// `Deploy (asks first)`
  String get scDeploy {
    return Intl.message(
      'Deploy (asks first)',
      name: 'scDeploy',
      desc: '',
      args: [],
    );
  }

  /// `This card`
  String get scHelp {
    return Intl.message('This card', name: 'scHelp', desc: '', args: []);
  }

  /// `Fields`
  String get fmFields {
    return Intl.message('Fields', name: 'fmFields', desc: '', args: []);
  }

  /// `Fields on the block`
  String get fmFieldsTitle {
    return Intl.message(
      'Fields on the block',
      name: 'fmFieldsTitle',
      desc: '',
      args: [],
    );
  }

  /// `Unpin from block`
  String get fmUnpin {
    return Intl.message(
      'Unpin from block',
      name: 'fmUnpin',
      desc: '',
      args: [],
    );
  }

  /// `Unpin “{label}” from block`
  String fmUnpinField(String label) {
    return Intl.message(
      'Unpin “$label” from block',
      name: 'fmUnpinField',
      desc: '',
      args: [label],
    );
  }

  /// `Create custom block…`
  String get fmCreateCustom {
    return Intl.message(
      'Create custom block…',
      name: 'fmCreateCustom',
      desc: '',
      args: [],
    );
  }

  /// `Edit custom block`
  String get fmEditCustom {
    return Intl.message(
      'Edit custom block',
      name: 'fmEditCustom',
      desc: '',
      args: [],
    );
  }

  /// `bound`
  String get fmBound {
    return Intl.message('bound', name: 'fmBound', desc: '', args: []);
  }

  /// `Needs custom blocks in the engine`
  String get fmNeedsEngine {
    return Intl.message(
      'Needs custom blocks in the engine',
      name: 'fmNeedsEngine',
      desc: '',
      args: [],
    );
  }

  /// `Select a block first`
  String get fmNothingSelected {
    return Intl.message(
      'Select a block first',
      name: 'fmNothingSelected',
      desc: '',
      args: [],
    );
  }

  /// `Nothing to undo`
  String get fmNothingToUndo {
    return Intl.message(
      'Nothing to undo',
      name: 'fmNothingToUndo',
      desc: '',
      args: [],
    );
  }

  /// `Nothing to redo`
  String get fmNothingToRedo {
    return Intl.message(
      'Nothing to redo',
      name: 'fmNothingToRedo',
      desc: '',
      args: [],
    );
  }

  /// `{count} blocks`
  String fmBlocks(int count) {
    return Intl.message(
      '$count blocks',
      name: 'fmBlocks',
      desc: '',
      args: [count],
    );
  }

  /// `Canvas`
  String get fmCanvas {
    return Intl.message('Canvas', name: 'fmCanvas', desc: '', args: []);
  }

  /// `Pin to block`
  String get pinField {
    return Intl.message('Pin to block', name: 'pinField', desc: '', args: []);
  }

  /// `Unpin from block`
  String get unpinField {
    return Intl.message(
      'Unpin from block',
      name: 'unpinField',
      desc: '',
      args: [],
    );
  }

  /// `A bound field stays on the block`
  String get pinLocked {
    return Intl.message(
      'A bound field stays on the block',
      name: 'pinLocked',
      desc: '',
      args: [],
    );
  }

  /// `Edit`
  String get viewerEdit {
    return Intl.message('Edit', name: 'viewerEdit', desc: '', args: []);
  }

  /// `Save`
  String get viewerSave {
    return Intl.message('Save', name: 'viewerSave', desc: '', args: []);
  }

  /// `{keys} saves · Esc cancels`
  String viewerSaveHint(String keys) {
    return Intl.message(
      '$keys saves · Esc cancels',
      name: 'viewerSaveHint',
      desc: '',
      args: [keys],
    );
  }

  /// `Read only: a wire feeds this field. Unbind it to type a value.`
  String get viewerLockedBound {
    return Intl.message(
      'Read only: a wire feeds this field. Unbind it to type a value.',
      name: 'viewerLockedBound',
      desc: '',
      args: [],
    );
  }

  /// `Read only: the block computes this output.`
  String get viewerLockedOutput {
    return Intl.message(
      'Read only: the block computes this output.',
      name: 'viewerLockedOutput',
      desc: '',
      args: [],
    );
  }

  /// `Read only: this input holds no typed value. Bind an output to it.`
  String get viewerLockedInput {
    return Intl.message(
      'Read only: this input holds no typed value. Bind an output to it.',
      name: 'viewerLockedInput',
      desc: '',
      args: [],
    );
  }

  /// `Not a number`
  String get viewerBadNumber {
    return Intl.message(
      'Not a number',
      name: 'viewerBadNumber',
      desc: '',
      args: [],
    );
  }

  /// `Not a JSON map or list`
  String get viewerBadJson {
    return Intl.message(
      'Not a JSON map or list',
      name: 'viewerBadJson',
      desc: '',
      args: [],
    );
  }

  /// `true or false`
  String get viewerBadBool {
    return Intl.message(
      'true or false',
      name: 'viewerBadBool',
      desc: '',
      args: [],
    );
  }

  /// `Empty: the field goes back to its default`
  String get viewerEmpty {
    return Intl.message(
      'Empty: the field goes back to its default',
      name: 'viewerEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Deploy this flow?`
  String get deployAskTitle {
    return Intl.message(
      'Deploy this flow?',
      name: 'deployAskTitle',
      desc: '',
      args: [],
    );
  }

  /// `The draft of “{flow}” replaces the version that runs now.`
  String deployAskMessage(String flow) {
    return Intl.message(
      'The draft of “$flow” replaces the version that runs now.',
      name: 'deployAskMessage',
      desc: '',
      args: [flow],
    );
  }

  /// `Language`
  String get menuLanguage {
    return Intl.message('Language', name: 'menuLanguage', desc: '', args: []);
  }

  /// `Theme`
  String get menuTheme {
    return Intl.message('Theme', name: 'menuTheme', desc: '', args: []);
  }

  /// `Minimize`
  String get windowMinimize {
    return Intl.message('Minimize', name: 'windowMinimize', desc: '', args: []);
  }

  /// `Maximize`
  String get windowMaximize {
    return Intl.message('Maximize', name: 'windowMaximize', desc: '', args: []);
  }

  /// `Restore`
  String get windowRestore {
    return Intl.message('Restore', name: 'windowRestore', desc: '', args: []);
  }

  /// `Close window`
  String get windowClose {
    return Intl.message(
      'Close window',
      name: 'windowClose',
      desc: '',
      args: [],
    );
  }
}

class AppLocalizationDelegate extends LocalizationsDelegate<S> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'en'),
      Locale.fromSubtags(languageCode: 'uk'),
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale);
  @override
  Future<S> load(Locale locale) => S.load(locale);
  @override
  bool shouldReload(AppLocalizationDelegate old) => false;

  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }
}
