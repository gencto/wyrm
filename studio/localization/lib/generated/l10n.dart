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

  /// `Values update live. Edits are staged in this session; nothing is written until you apply.`
  String get pointsNote {
    return Intl.message(
      'Values update live. Edits are staged in this session; nothing is written until you apply.',
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

  /// `Right-click a node or press and hold to see its actions. sys/** is edited in Links, Access, Sites and System.`
  String get treeNote {
    return Intl.message(
      'Right-click a node or press and hold to see its actions. sys/** is edited in Links, Access, Sites and System.',
      name: 'treeNote',
      desc: '',
      args: [],
    );
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
