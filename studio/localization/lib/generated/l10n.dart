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
