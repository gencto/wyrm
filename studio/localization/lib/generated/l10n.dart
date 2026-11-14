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

  /// `official`
  String get officialMark {
    return Intl.message('official', name: 'officialMark', desc: '', args: []);
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

  /// `Approving in Studio comes with its next step. Approve with wyrm-agent for now.`
  String get approveReasonNote {
    return Intl.message(
      'Approving in Studio comes with its next step. Approve with wyrm-agent for now.',
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

  /// `{count, plural, =1{1 row} other{{count} rows}}`
  String sizeRows(int count) {
    return Intl.plural(
      count,
      one: '1 row',
      other: '$count rows',
      name: 'sizeRows',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 column} other{{count} columns}}`
  String sizeColumns(int count) {
    return Intl.plural(
      count,
      one: '1 column',
      other: '$count columns',
      name: 'sizeColumns',
      desc: '',
      args: [count],
    );
  }

  /// `a table with no columns`
  String get tableNoColumns {
    return Intl.message(
      'a table with no columns',
      name: 'tableNoColumns',
      desc: '',
      args: [],
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

  /// `Overview`
  String get sysTabOverview {
    return Intl.message('Overview', name: 'sysTabOverview', desc: '', args: []);
  }

  /// `Availability`
  String get sysTabAvailability {
    return Intl.message(
      'Availability',
      name: 'sysTabAvailability',
      desc: '',
      args: [],
    );
  }

  /// `Log`
  String get sysTabLog {
    return Intl.message('Log', name: 'sysTabLog', desc: '', args: []);
  }

  /// `Maintenance`
  String get sysTabMaintenance {
    return Intl.message(
      'Maintenance',
      name: 'sysTabMaintenance',
      desc: '',
      args: [],
    );
  }

  /// `System sections`
  String get sysTabsLabel {
    return Intl.message(
      'System sections',
      name: 'sysTabsLabel',
      desc: '',
      args: [],
    );
  }

  /// `Running · active`
  String get sysRunningActive {
    return Intl.message(
      'Running · active',
      name: 'sysRunningActive',
      desc: '',
      args: [],
    );
  }

  /// `Unreachable`
  String get sysUnreachable {
    return Intl.message(
      'Unreachable',
      name: 'sysUnreachable',
      desc: '',
      args: [],
    );
  }

  /// `started {t}`
  String sysMetaStarted(Object t) {
    return Intl.message(
      'started $t',
      name: 'sysMetaStarted',
      desc: '',
      args: [t],
    );
  }

  /// `Links and sites`
  String get sysGroupLinks {
    return Intl.message(
      'Links and sites',
      name: 'sysGroupLinks',
      desc: '',
      args: [],
    );
  }

  /// `Process and disk`
  String get sysGroupProcess {
    return Intl.message(
      'Process and disk',
      name: 'sysGroupProcess',
      desc: '',
      args: [],
    );
  }

  /// `Packages`
  String get sysPackages {
    return Intl.message('Packages', name: 'sysPackages', desc: '', args: []);
  }

  /// `Upstream`
  String get sysUpstream {
    return Intl.message('Upstream', name: 'sysUpstream', desc: '', args: []);
  }

  /// `Downstream`
  String get sysDownstream {
    return Intl.message(
      'Downstream',
      name: 'sysDownstream',
      desc: '',
      args: [],
    );
  }

  /// `of {n}`
  String sysOfTotal(Object n) {
    return Intl.message('of $n', name: 'sysOfTotal', desc: '', args: [n]);
  }

  /// `connected`
  String get sysUnitConnected {
    return Intl.message(
      'connected',
      name: 'sysUnitConnected',
      desc: '',
      args: [],
    );
  }

  /// `{id} failed · open Links`
  String sysSubLinkFailed(Object id) {
    return Intl.message(
      '$id failed · open Links',
      name: 'sysSubLinkFailed',
      desc: '',
      args: [id],
    );
  }

  /// `open Links`
  String get sysSubOpenLinks {
    return Intl.message(
      'open Links',
      name: 'sysSubOpenLinks',
      desc: '',
      args: [],
    );
  }

  /// `{cn} waits · open Quarantine`
  String sysSubWaits(Object cn) {
    return Intl.message(
      '$cn waits · open Quarantine',
      name: 'sysSubWaits',
      desc: '',
      args: [cn],
    );
  }

  /// `open Quarantine`
  String get sysSubOpenQuarantine {
    return Intl.message(
      'open Quarantine',
      name: 'sysSubOpenQuarantine',
      desc: '',
      args: [],
    );
  }

  /// `installed link packages`
  String get sysSubPackages {
    return Intl.message(
      'installed link packages',
      name: 'sysSubPackages',
      desc: '',
      args: [],
    );
  }

  /// `{site} · open Sites`
  String sysSubPeer(Object site) {
    return Intl.message(
      '$site · open Sites',
      name: 'sysSubPeer',
      desc: '',
      args: [site],
    );
  }

  /// `open Sites`
  String get sysSubOpenSites {
    return Intl.message(
      'open Sites',
      name: 'sysSubOpenSites',
      desc: '',
      args: [],
    );
  }

  /// `network sessions; gateway users not counted`
  String get sysSubSessions {
    return Intl.message(
      'network sessions; gateway users not counted',
      name: 'sysSubSessions',
      desc: '',
      args: [],
    );
  }

  /// `100 = one core`
  String get sysSubCpu {
    return Intl.message(
      '100 = one core',
      name: 'sysSubCpu',
      desc: '',
      args: [],
    );
  }

  /// `resident`
  String get sysSubMemory {
    return Intl.message('resident', name: 'sysSubMemory', desc: '', args: []);
  }

  /// `on the data_dir file system`
  String get sysSubDisk {
    return Intl.message(
      'on the data_dir file system',
      name: 'sysSubDisk',
      desc: '',
      args: [],
    );
  }

  /// `history {size} · open History`
  String sysSubData(Object size) {
    return Intl.message(
      'history $size · open History',
      name: 'sysSubData',
      desc: '',
      args: [size],
    );
  }

  /// `open History`
  String get sysSubOpenHistory {
    return Intl.message(
      'open History',
      name: 'sysSubOpenHistory',
      desc: '',
      args: [],
    );
  }

  /// `since the router started · open Audit`
  String get sysSubAcl {
    return Intl.message(
      'since the router started · open Audit',
      name: 'sysSubAcl',
      desc: '',
      args: [],
    );
  }

  /// `who did what · open Audit`
  String get sysSubAudit {
    return Intl.message(
      'who did what · open Audit',
      name: 'sysSubAudit',
      desc: '',
      args: [],
    );
  }

  /// `Router traffic`
  String get sysTraffic {
    return Intl.message(
      'Router traffic',
      name: 'sysTraffic',
      desc: '',
      args: [],
    );
  }

  /// `Messages`
  String get sysMessages {
    return Intl.message('Messages', name: 'sysMessages', desc: '', args: []);
  }

  /// `Frames`
  String get sysFrames {
    return Intl.message('Frames', name: 'sysFrames', desc: '', args: []);
  }

  /// `Bytes`
  String get sysBytes {
    return Intl.message('Bytes', name: 'sysBytes', desc: '', args: []);
  }

  /// `in`
  String get sysIn {
    return Intl.message('in', name: 'sysIn', desc: '', args: []);
  }

  /// `out`
  String get sysOut {
    return Intl.message('out', name: 'sysOut', desc: '', args: []);
  }

  /// `Sampled from the 'sys' rates while Studio is open (the broker keeps no history of them). Network sessions only: embedded links and gateway users talk in-process and are not counted.`
  String get sysTrafficNote {
    return Intl.message(
      'Sampled from the `sys` rates while Studio is open (the broker keeps no history of them). Network sessions only: embedded links and gateway users talk in-process and are not counted.',
      name: 'sysTrafficNote',
      desc: '',
      args: [],
    );
  }

  /// `Collecting…`
  String get sysCollecting {
    return Intl.message(
      'Collecting…',
      name: 'sysCollecting',
      desc: '',
      args: [],
    );
  }

  /// `{t} · now`
  String sysNow(Object t) {
    return Intl.message('$t · now', name: 'sysNow', desc: '', args: [t]);
  }

  /// `{measure} in and out per second from {from} to {to}`
  String sysTrafficDescribe(Object measure, Object from, Object to) {
    return Intl.message(
      '$measure in and out per second from $from to $to',
      name: 'sysTrafficDescribe',
      desc: '',
      args: [measure, from, to],
    );
  }

  /// `This broker · active`
  String get sysThisActive {
    return Intl.message(
      'This broker · active',
      name: 'sysThisActive',
      desc: '',
      args: [],
    );
  }

  /// `Serves links, flows, the gateway and peers. Answers 'sys/replication/**' for its standby.`
  String get sysActiveNote {
    return Intl.message(
      'Serves links, flows, the gateway and peers. Answers `sys/replication/**` for its standby.',
      name: 'sysActiveNote',
      desc: '',
      args: [],
    );
  }

  /// `WAL, files, storage, history`
  String get sysFlow {
    return Intl.message(
      'WAL, files, storage, history',
      name: 'sysFlow',
      desc: '',
      args: [],
    );
  }

  /// `pulled every 1 s`
  String get sysPulled {
    return Intl.message(
      'pulled every 1 s',
      name: 'sysPulled',
      desc: '',
      args: [],
    );
  }

  /// `Standby · following`
  String get sysStandbyFollowing {
    return Intl.message(
      'Standby · following',
      name: 'sysStandbyFollowing',
      desc: '',
      args: [],
    );
  }

  /// `Standby · behind`
  String get sysStandbyBehind {
    return Intl.message(
      'Standby · behind',
      name: 'sysStandbyBehind',
      desc: '',
      args: [],
    );
  }

  /// `Same keys, own 'data_dir'. Takes over only if this broker stops answering and a witness still answers it.`
  String get sysStandbyNote {
    return Intl.message(
      'Same keys, own `data_dir`. Takes over only if this broker stops answering and a witness still answers it.',
      name: 'sysStandbyNote',
      desc: '',
      args: [],
    );
  }

  /// `Standby connected`
  String get sysStandbyConnected {
    return Intl.message(
      'Standby connected',
      name: 'sysStandbyConnected',
      desc: '',
      args: [],
    );
  }

  /// `Lag`
  String get sysLag {
    return Intl.message('Lag', name: 'sysLag', desc: '', args: []);
  }

  /// `Arbiter lease`
  String get sysArbiterLease {
    return Intl.message(
      'Arbiter lease',
      name: 'sysArbiterLease',
      desc: '',
      args: [],
    );
  }

  /// `Forks moved aside`
  String get sysForks {
    return Intl.message(
      'Forks moved aside',
      name: 'sysForks',
      desc: '',
      args: [],
    );
  }

  /// `records`
  String get sysRecords {
    return Intl.message('records', name: 'sysRecords', desc: '', args: []);
  }

  /// `s left`
  String get sysSecondsLeft {
    return Intl.message('s left', name: 'sysSecondsLeft', desc: '', args: []);
  }

  /// `since start`
  String get sysSinceStart {
    return Intl.message(
      'since start',
      name: 'sysSinceStart',
      desc: '',
      args: [],
    );
  }

  /// `follows this broker over the peer link`
  String get sysSubFollows {
    return Intl.message(
      'follows this broker over the peer link',
      name: 'sysSubFollows',
      desc: '',
      args: [],
    );
  }

  /// `the standby has every registry record`
  String get sysSubLagNone {
    return Intl.message(
      'the standby has every registry record',
      name: 'sysSubLagNone',
      desc: '',
      args: [],
    );
  }

  /// `not on the standby yet: a takeover now loses them`
  String get sysSubLag {
    return Intl.message(
      'not on the standby yet: a takeover now loses them',
      name: 'sysSubLag',
      desc: '',
      args: [],
    );
  }

  /// `renewed by the lease arbiter`
  String get sysSubLease {
    return Intl.message(
      'renewed by the lease arbiter',
      name: 'sysSubLease',
      desc: '',
      args: [],
    );
  }

  /// `renewing late: check the arbiter host`
  String get sysSubLeaseLate {
    return Intl.message(
      'renewing late: check the arbiter host',
      name: 'sysSubLeaseLate',
      desc: '',
      args: [],
    );
  }

  /// `no arbiter configured`
  String get sysSubNoArbiter {
    return Intl.message(
      'no arbiter configured',
      name: 'sysSubNoArbiter',
      desc: '',
      args: [],
    );
  }

  /// `no split since this broker started`
  String get sysSubForksNone {
    return Intl.message(
      'no split since this broker started',
      name: 'sysSubForksNone',
      desc: '',
      args: [],
    );
  }

  /// `after a healed split · audit standby_forked`
  String get sysSubForks {
    return Intl.message(
      'after a healed split · audit standby_forked',
      name: 'sysSubForks',
      desc: '',
      args: [],
    );
  }

  /// `The standby is behind and moved a fork aside`
  String get sysBannerBoth {
    return Intl.message(
      'The standby is behind and moved a fork aside',
      name: 'sysBannerBoth',
      desc: '',
      args: [],
    );
  }

  /// `The standby is behind`
  String get sysBannerBehind {
    return Intl.message(
      'The standby is behind',
      name: 'sysBannerBehind',
      desc: '',
      args: [],
    );
  }

  /// `The standby moved a fork aside`
  String get sysBannerFork {
    return Intl.message(
      'The standby moved a fork aside',
      name: 'sysBannerFork',
      desc: '',
      args: [],
    );
  }

  /// `{n} registry records are not on the standby yet: a takeover now would lose them.`
  String sysBannerLag(Object n) {
    return Intl.message(
      '$n registry records are not on the standby yet: a takeover now would lose them.',
      name: 'sysBannerLag',
      desc: '',
      args: [n],
    );
  }

  /// `Sets of records moved aside after both brokers were active (a healed split): {n}. The audit record 'standby_forked' says which.`
  String sysBannerForks(Object n) {
    return Intl.message(
      'Sets of records moved aside after both brokers were active (a healed split): $n. The audit record `standby_forked` says which.',
      name: 'sysBannerForks',
      desc: '',
      args: [n],
    );
  }

  /// `Open the audit record ›`
  String get sysOpenAuditRecord {
    return Intl.message(
      'Open the audit record ›',
      name: 'sysOpenAuditRecord',
      desc: '',
      args: [],
    );
  }

  /// `What the standby holds`
  String get sysHeld {
    return Intl.message(
      'What the standby holds',
      name: 'sysHeld',
      desc: '',
      args: [],
    );
  }

  /// `Control plane`
  String get sysHeldControl {
    return Intl.message(
      'Control plane',
      name: 'sysHeldControl',
      desc: '',
      args: [],
    );
  }

  /// `Registry, flow definitions and gateway users: the WAL records themselves, checked against the HMAC chain.`
  String get sysHeldControlNote {
    return Intl.message(
      'Registry, flow definitions and gateway users: the WAL records themselves, checked against the HMAC chain.',
      name: 'sysHeldControlNote',
      desc: '',
      args: [],
    );
  }

  /// `Secrets and link data`
  String get sysHeldSecrets {
    return Intl.message(
      'Secrets and link data',
      name: 'sysHeldSecrets',
      desc: '',
      args: [],
    );
  }

  /// `secrets.bin, link tokens, link data_dirs and packages: sealed parts of 1 MiB, files up to 64 MiB, removed when gone here.`
  String get sysHeldSecretsNote {
    return Intl.message(
      'secrets.bin, link tokens, link data_dirs and packages: sealed parts of 1 MiB, files up to 64 MiB, removed when gone here.',
      name: 'sysHeldSecretsNote',
      desc: '',
      args: [],
    );
  }

  /// `Broker storage`
  String get sysHeldStorage {
    return Intl.message(
      'Broker storage',
      name: 'sysHeldStorage',
      desc: '',
      args: [],
    );
  }

  /// `The storage change journal, applied into the standby’s own storage (full tree beyond 20,000 changes).`
  String get sysHeldStorageNote {
    return Intl.message(
      'The storage change journal, applied into the standby’s own storage (full tree beyond 20,000 changes).',
      name: 'sysHeldStorageNote',
      desc: '',
      args: [],
    );
  }

  /// `History`
  String get sysHeldHistory {
    return Intl.message('History', name: 'sysHeldHistory', desc: '', args: []);
  }

  /// `Every series’ rows from the change journal, written into the standby’s own day files.`
  String get sysHeldHistoryNote {
    return Intl.message(
      'Every series’ rows from the change journal, written into the standby’s own day files.',
      name: 'sysHeldHistoryNote',
      desc: '',
      args: [],
    );
  }

  /// `No standby is following this broker`
  String get sysNoStandbyTitle {
    return Intl.message(
      'No standby is following this broker',
      name: 'sysNoStandbyTitle',
      desc: '',
      args: [],
    );
  }

  /// `'sys/standby_connected' is 0. Either no warm standby is configured, or the one configured cannot reach this broker. If this host fails, the site stops until it is back; links on other machines walk to their next endpoint only if they have one.`
  String get sysNoStandbyBody {
    return Intl.message(
      '`sys/standby_connected` is 0. Either no warm standby is configured, or the one configured cannot reach this broker. If this host fails, the site stops until it is back; links on other machines walk to their next endpoint only if they have one.',
      name: 'sysNoStandbyBody',
      desc: '',
      args: [],
    );
  }

  /// `To add one (on the hosts, not in Studio)`
  String get sysNoStandbySteps {
    return Intl.message(
      'To add one (on the hosts, not in Studio)',
      name: 'sysNoStandbySteps',
      desc: '',
      args: [],
    );
  }

  /// `1. Copy the keys to the second host: 'wyrmd keys export' here, 'wyrmd keys import' there.`
  String get sysNoStandbyStep1 {
    return Intl.message(
      '1. Copy the keys to the second host: `wyrmd keys export` here, `wyrmd keys import` there.',
      name: 'sysNoStandbyStep1',
      desc: '',
      args: [],
    );
  }

  /// `2. In 'wyrmd.json5' on both hosts: '{standby}' and 'peers.listen'; a lease 'arbiter' on a third host is recommended.`
  String sysNoStandbyStep2(Object standby) {
    return Intl.message(
      '2. In `wyrmd.json5` on both hosts: `$standby` and `peers.listen`; a lease `arbiter` on a third host is recommended.',
      name: 'sysNoStandbyStep2',
      desc: '',
      args: [standby],
    );
  }

  /// `3. Start the second host; this tab shows it within a second.`
  String get sysNoStandbyStep3 {
    return Intl.message(
      '3. Start the second host; this tab shows it within a second.',
      name: 'sysNoStandbyStep3',
      desc: '',
      args: [],
    );
  }

  /// `Guide: docs/operations.md › Warm standby ›`
  String get sysGuideLink {
    return Intl.message(
      'Guide: docs/operations.md › Warm standby ›',
      name: 'sysGuideLink',
      desc: '',
      args: [],
    );
  }

  /// `Link to the guide copied: {url}`
  String sysGuideCopied(Object url) {
    return Intl.message(
      'Link to the guide copied: $url',
      name: 'sysGuideCopied',
      desc: '',
      args: [url],
    );
  }

  /// `Source`
  String get sysSource {
    return Intl.message('Source', name: 'sysSource', desc: '', args: []);
  }

  /// `broker (all)`
  String get sysBrokerAll {
    return Intl.message(
      'broker (all)',
      name: 'sysBrokerAll',
      desc: '',
      args: [],
    );
  }

  /// `link: {id}`
  String sysLinkSource(Object id) {
    return Intl.message(
      'link: $id',
      name: 'sysLinkSource',
      desc: '',
      args: [id],
    );
  }

  /// `Level and more severe`
  String get sysLevelMore {
    return Intl.message(
      'Level and more severe',
      name: 'sysLevelMore',
      desc: '',
      args: [],
    );
  }

  /// `Filter`
  String get sysFilter {
    return Intl.message('Filter', name: 'sysFilter', desc: '', args: []);
  }

  /// `text in the target or message`
  String get sysFilterHint {
    return Intl.message(
      'text in the target or message',
      name: 'sysFilterHint',
      desc: '',
      args: [],
    );
  }

  /// `Lines`
  String get sysLines {
    return Intl.message('Lines', name: 'sysLines', desc: '', args: []);
  }

  /// `every 5 s`
  String get sysEvery5s {
    return Intl.message('every 5 s', name: 'sysEvery5s', desc: '', args: []);
  }

  /// `Get log`
  String get sysGetLog {
    return Intl.message('Get log', name: 'sysGetLog', desc: '', args: []);
  }

  /// `{n} lines from the broker's ring · newest first · 'sys/~act/get_log'`
  String sysLogSummary(Object n) {
    return Intl.message(
      '$n lines from the broker\'s ring · newest first · `sys/~act/get_log`',
      name: 'sysLogSummary',
      desc: '',
      args: [n],
    );
  }

  /// `'sys/~act/get_log' · config`
  String get sysLogSummaryNone {
    return Intl.message(
      '`sys/~act/get_log` · config',
      name: 'sysLogSummaryNone',
      desc: '',
      args: [],
    );
  }

  /// `Copy`
  String get sysCopy {
    return Intl.message('Copy', name: 'sysCopy', desc: '', args: []);
  }

  /// `Save as .log`
  String get sysSaveLog {
    return Intl.message('Save as .log', name: 'sysSaveLog', desc: '', args: []);
  }

  /// `No lines at this level.`
  String get sysNoLines {
    return Intl.message(
      'No lines at this level.',
      name: 'sysNoLines',
      desc: '',
      args: [],
    );
  }

  /// `Around (UTC)`
  String get sysAround {
    return Intl.message('Around (UTC)', name: 'sysAround', desc: '', args: []);
  }

  /// `hh:mm:ss`
  String get sysAroundHint {
    return Intl.message('hh:mm:ss', name: 'sysAroundHint', desc: '', args: []);
  }

  /// `Show every time`
  String get sysAroundClear {
    return Intl.message(
      'Show every time',
      name: 'sysAroundClear',
      desc: '',
      args: [],
    );
  }

  /// `Type a time as hh:mm or hh:mm:ss.`
  String get sysAroundBad {
    return Intl.message(
      'Type a time as hh:mm or hh:mm:ss.',
      name: 'sysAroundBad',
      desc: '',
      args: [],
    );
  }

  /// `{n} of {m} lines within 2 min of {time} UTC · newest first · 'sys/~act/get_log'`
  String sysLogSummaryAround(int n, int m, String time) {
    return Intl.message(
      '$n of $m lines within 2 min of $time UTC · newest first · `sys/~act/get_log`',
      name: 'sysLogSummaryAround',
      desc: '',
      args: [n, m, time],
    );
  }

  /// `None of the newest {m} lines is within 2 min of {time} UTC. Ask for more lines, or clear the time.`
  String sysNoLinesAround(int m, String time) {
    return Intl.message(
      'None of the newest $m lines is within 2 min of $time UTC. Ask for more lines, or clear the time.',
      name: 'sysNoLinesAround',
      desc: '',
      args: [m, time],
    );
  }

  /// `The log is read with config on sys.`
  String get sysLogNeedsConfig {
    return Intl.message(
      'The log is read with config on sys.',
      name: 'sysLogNeedsConfig',
      desc: '',
      args: [],
    );
  }

  /// `Lines copied: {n}`
  String sysLogCopied(Object n) {
    return Intl.message(
      'Lines copied: $n',
      name: 'sysLogCopied',
      desc: '',
      args: [n],
    );
  }

  /// `Saved {path}`
  String sysLogSaved(Object path) {
    return Intl.message(
      'Saved $path',
      name: 'sysLogSaved',
      desc: '',
      args: [path],
    );
  }

  /// `Cannot save the log`
  String get sysLogNotSaved {
    return Intl.message(
      'Cannot save the log',
      name: 'sysLogNotSaved',
      desc: '',
      args: [],
    );
  }

  /// `Broker log level`
  String get sysBrokerLogLevel {
    return Intl.message(
      'Broker log level',
      name: 'sysBrokerLogLevel',
      desc: '',
      args: [],
    );
  }

  /// `Staged in Review and apply; once applied it takes effect at once, no restart, and replaces 'RUST_LOG'. Zenoh stays at warn below trace. Values and tokens are never logged below trace. A link's own level: Links › the link › Log.`
  String get sysLogLevelNote {
    return Intl.message(
      'Staged in Review and apply; once applied it takes effect at once, no restart, and replaces `RUST_LOG`. Zenoh stays at warn below trace. Values and tokens are never logged below trace. A link\'s own level: Links › the link › Log.',
      name: 'sysLogLevelNote',
      desc: '',
      args: [],
    );
  }

  /// `Disconnected links`
  String get sysStale {
    return Intl.message(
      'Disconnected links',
      name: 'sysStale',
      desc: '',
      args: [],
    );
  }

  /// `Links admitted at runtime that run on other machines and are not connected now. Clearing removes them from the registry; their ids are retired and cannot be used again.`
  String get sysStaleNote {
    return Intl.message(
      'Links admitted at runtime that run on other machines and are not connected now. Clearing removes them from the registry; their ids are retired and cannot be used again.',
      name: 'sysStaleNote',
      desc: '',
      args: [],
    );
  }

  /// `external · CN {cn}`
  String sysStaleRow(Object cn) {
    return Intl.message(
      'external · CN $cn',
      name: 'sysStaleRow',
      desc: '',
      args: [cn],
    );
  }

  /// `not connected`
  String get sysNotConnected {
    return Intl.message(
      'not connected',
      name: 'sysNotConnected',
      desc: '',
      args: [],
    );
  }

  /// `No disconnected links.`
  String get sysNoStale {
    return Intl.message(
      'No disconnected links.',
      name: 'sysNoStale',
      desc: '',
      args: [],
    );
  }

  /// `Clear disconnected links ({n})…`
  String sysClear(Object n) {
    return Intl.message(
      'Clear disconnected links ($n)…',
      name: 'sysClear',
      desc: '',
      args: [n],
    );
  }

  /// `Clear {n} disconnected links…`
  String sysClearBoard(Object n) {
    return Intl.message(
      'Clear $n disconnected links…',
      name: 'sysClearBoard',
      desc: '',
      args: [n],
    );
  }

  /// `Clear 1 disconnected link…`
  String get sysClearOne {
    return Intl.message(
      'Clear 1 disconnected link…',
      name: 'sysClearOne',
      desc: '',
      args: [],
    );
  }

  /// `Clear disconnected links…`
  String get sysClearNone {
    return Intl.message(
      'Clear disconnected links…',
      name: 'sysClearNone',
      desc: '',
      args: [],
    );
  }

  /// `No disconnected links to clear`
  String get sysNothingToClear {
    return Intl.message(
      'No disconnected links to clear',
      name: 'sysNothingToClear',
      desc: '',
      args: [],
    );
  }

  /// `'sys/~act/clear_conns' · config · asks before it runs`
  String get sysClearFooter {
    return Intl.message(
      '`sys/~act/clear_conns` · config · asks before it runs',
      name: 'sysClearFooter',
      desc: '',
      args: [],
    );
  }

  /// `Clear these disconnected links?`
  String get sysClearAsk {
    return Intl.message(
      'Clear these disconnected links?',
      name: 'sysClearAsk',
      desc: '',
      args: [],
    );
  }

  /// `{ids}\n\nTheir ids are retired and cannot be used again.`
  String sysClearAskBody(Object ids) {
    return Intl.message(
      '$ids\n\nTheir ids are retired and cannot be used again.',
      name: 'sysClearAskBody',
      desc: '',
      args: [ids],
    );
  }

  /// `Clear`
  String get sysClearConfirm {
    return Intl.message('Clear', name: 'sysClearConfirm', desc: '', args: []);
  }

  /// `Removed: {ids}`
  String sysCleared(Object ids) {
    return Intl.message(
      'Removed: $ids',
      name: 'sysCleared',
      desc: '',
      args: [ids],
    );
  }

  /// `The broker removed no link.`
  String get sysClearedNone {
    return Intl.message(
      'The broker removed no link.',
      name: 'sysClearedNone',
      desc: '',
      args: [],
    );
  }

  /// `Device profiles`
  String get sysProfiles {
    return Intl.message(
      'Device profiles',
      name: 'sysProfiles',
      desc: '',
      args: [],
    );
  }

  /// `Models served as 'pub/<vendor>:<model>': points, units and ranges that links and the assistant inherit.`
  String get sysProfilesNote {
    return Intl.message(
      'Models served as `pub/<vendor>:<model>`: points, units and ranges that links and the assistant inherit.',
      name: 'sysProfilesNote',
      desc: '',
      args: [],
    );
  }

  /// `Put profile…`
  String get sysPutProfile {
    return Intl.message(
      'Put profile…',
      name: 'sysPutProfile',
      desc: '',
      args: [],
    );
  }

  /// `Remove`
  String get sysRemove {
    return Intl.message('Remove', name: 'sysRemove', desc: '', args: []);
  }

  /// `Remove profile {name}`
  String sysRemoveProfile(Object name) {
    return Intl.message(
      'Remove profile $name',
      name: 'sysRemoveProfile',
      desc: '',
      args: [name],
    );
  }

  /// `The broker stops serving pub/{name} and records it in the audit journal (profile_remove).`
  String sysRemoveProfileAsk(Object name) {
    return Intl.message(
      'The broker stops serving pub/$name and records it in the audit journal (profile_remove).',
      name: 'sysRemoveProfileAsk',
      desc: '',
      args: [name],
    );
  }

  /// `No profiles.`
  String get sysNoProfiles {
    return Intl.message(
      'No profiles.',
      name: 'sysNoProfiles',
      desc: '',
      args: [],
    );
  }

  /// `This broker does not list its profiles through the gateway ({reason}). You can still put one; it is then served at pub/<name>.`
  String sysProfilesUnlisted(Object reason) {
    return Intl.message(
      'This broker does not list its profiles through the gateway ($reason). You can still put one; it is then served at pub/<name>.',
      name: 'sysProfilesUnlisted',
      desc: '',
      args: [reason],
    );
  }

  /// `'sys/profiles' › Put Profile, Remove Profile · config`
  String get sysProfilesFooter {
    return Intl.message(
      '`sys/profiles` › Put Profile, Remove Profile · config',
      name: 'sysProfilesFooter',
      desc: '',
      args: [],
    );
  }

  /// `Name`
  String get sysProfileName {
    return Intl.message('Name', name: 'sysProfileName', desc: '', args: []);
  }

  /// `<vendor>:<model>`
  String get sysProfileNameHint {
    return Intl.message(
      '<vendor>:<model>',
      name: 'sysProfileNameHint',
      desc: '',
      args: [],
    );
  }

  /// `File {name}. A .cbor file is sent as it is; a JSON file is encoded first.`
  String sysProfileFile(Object name) {
    return Intl.message(
      'File $name. A .cbor file is sent as it is; a JSON file is encoded first.',
      name: 'sysProfileFile',
      desc: '',
      args: [name],
    );
  }

  /// `Put profile`
  String get sysPut {
    return Intl.message('Put profile', name: 'sysPut', desc: '', args: []);
  }

  /// `Profile {name} put`
  String sysProfilePut(Object name) {
    return Intl.message(
      'Profile $name put',
      name: 'sysProfilePut',
      desc: '',
      args: [name],
    );
  }

  /// `Profile {name} removed`
  String sysProfileRemoved(Object name) {
    return Intl.message(
      'Profile $name removed',
      name: 'sysProfileRemoved',
      desc: '',
      args: [name],
    );
  }

  /// `Back up and restore`
  String get sysBackup {
    return Intl.message(
      'Back up and restore',
      name: 'sysBackup',
      desc: '',
      args: [],
    );
  }

  /// `Everything the broker owns is in its 'data_dir' (here {size}). Studio does not take backups: they hold the site's keys and are made on the host. The steps, ready to copy:`
  String sysBackupNote(Object size) {
    return Intl.message(
      'Everything the broker owns is in its `data_dir` (here $size). Studio does not take backups: they hold the site\'s keys and are made on the host. The steps, ready to copy:',
      name: 'sysBackupNote',
      desc: '',
      args: [size],
    );
  }

  /// `Everything the broker owns is in its 'data_dir'. Studio does not take backups: they hold the site's keys and are made on the host. The steps, ready to copy:`
  String get sysBackupNoteNoSize {
    return Intl.message(
      'Everything the broker owns is in its `data_dir`. Studio does not take backups: they hold the site\'s keys and are made on the host. The steps, ready to copy:',
      name: 'sysBackupNoteNoSize',
      desc: '',
      args: [],
    );
  }

  /// `Back up (broker stopped)`
  String get sysCmdBackup {
    return Intl.message(
      'Back up (broker stopped)',
      name: 'sysCmdBackup',
      desc: '',
      args: [],
    );
  }

  /// `Consistent and simplest. With a filesystem snapshot (LVM, btrfs, ZFS) the broker can keep running.`
  String get sysCmdBackupNote {
    return Intl.message(
      'Consistent and simplest. With a filesystem snapshot (LVM, btrfs, ZFS) the broker can keep running.',
      name: 'sysCmdBackupNote',
      desc: '',
      args: [],
    );
  }

  /// `Check a copy`
  String get sysCmdVerify {
    return Intl.message(
      'Check a copy',
      name: 'sysCmdVerify',
      desc: '',
      args: [],
    );
  }

  /// `Checks every control-plane store offline: CRC, HMAC chain, anchors. Run it on the restored data_dir before a start.`
  String get sysCmdVerifyNote {
    return Intl.message(
      'Checks every control-plane store offline: CRC, HMAC chain, anchors. Run it on the restored data_dir before a start.',
      name: 'sysCmdVerifyNote',
      desc: '',
      args: [],
    );
  }

  /// `Before a restart with a changed file`
  String get sysCmdCheck {
    return Intl.message(
      'Before a restart with a changed file',
      name: 'sysCmdCheck',
      desc: '',
      args: [],
    );
  }

  /// `The configuration parses and validates; exit code 1 otherwise.`
  String get sysCmdCheckNote {
    return Intl.message(
      'The configuration parses and validates; exit code 1 otherwise.',
      name: 'sysCmdCheckNote',
      desc: '',
      args: [],
    );
  }

  /// `Copy: {title}`
  String sysCopyCommand(Object title) {
    return Intl.message(
      'Copy: $title',
      name: 'sysCopyCommand',
      desc: '',
      args: [title],
    );
  }

  /// `Commands copied`
  String get sysCommandCopied {
    return Intl.message(
      'Commands copied',
      name: 'sysCommandCopied',
      desc: '',
      args: [],
    );
  }

  /// `A backup holds the site CA and the gateway key: whoever reads it is an administrator. Encrypt it and keep it where only the broker's administrators can read it.`
  String get sysBackupWarning {
    return Intl.message(
      'A backup holds the site CA and the gateway key: whoever reads it is an administrator. Encrypt it and keep it where only the broker\'s administrators can read it.',
      name: 'sysBackupWarning',
      desc: '',
      args: [],
    );
  }

  /// `Also broker settings, kept where they are used:`
  String get sysElsewhere {
    return Intl.message(
      'Also broker settings, kept where they are used:',
      name: 'sysElsewhere',
      desc: '',
      args: [],
    );
  }

  /// `Admission of new links › Links › Quarantine`
  String get sysElsewhereLinks {
    return Intl.message(
      'Admission of new links › Links › Quarantine',
      name: 'sysElsewhereLinks',
      desc: '',
      args: [],
    );
  }

  /// `Tokens for sites below › Sites`
  String get sysElsewhereSites {
    return Intl.message(
      'Tokens for sites below › Sites',
      name: 'sysElsewhereSites',
      desc: '',
      args: [],
    );
  }

  /// `Roles and grants › Access`
  String get sysElsewhereAccess {
    return Intl.message(
      'Roles and grants › Access',
      name: 'sysElsewhereAccess',
      desc: '',
      args: [],
    );
  }

  /// `Retention and purge › History`
  String get sysElsewhereHistory {
    return Intl.message(
      'Retention and purge › History',
      name: 'sysElsewhereHistory',
      desc: '',
      args: [],
    );
  }

  /// `Needs a look · {n}`
  String sysNeedsLook(Object n) {
    return Intl.message(
      'Needs a look · $n',
      name: 'sysNeedsLook',
      desc: '',
      args: [n],
    );
  }

  /// `From the broker's own values. Each opens the screen where it is fixed.`
  String get sysNeedsLookNote {
    return Intl.message(
      'From the broker\'s own values. Each opens the screen where it is fixed.',
      name: 'sysNeedsLookNote',
      desc: '',
      args: [],
    );
  }

  /// `Nothing needs a look.`
  String get sysNothing {
    return Intl.message(
      'Nothing needs a look.',
      name: 'sysNothing',
      desc: '',
      args: [],
    );
  }

  /// `This broker`
  String get sysThisBroker {
    return Intl.message(
      'This broker',
      name: 'sysThisBroker',
      desc: '',
      args: [],
    );
  }

  /// `Site`
  String get sysFactSite {
    return Intl.message('Site', name: 'sysFactSite', desc: '', args: []);
  }

  /// `Liveliness`
  String get sysFactLiveliness {
    return Intl.message(
      'Liveliness',
      name: 'sysFactLiveliness',
      desc: '',
      args: [],
    );
  }

  /// `Standby is {n} records behind`
  String sysAttnBehind(Object n) {
    return Intl.message(
      'Standby is $n records behind',
      name: 'sysAttnBehind',
      desc: '',
      args: [n],
    );
  }

  /// `The standby moved a fork aside`
  String get sysAttnFork {
    return Intl.message(
      'The standby moved a fork aside',
      name: 'sysAttnFork',
      desc: '',
      args: [],
    );
  }

  /// `Forks moved aside after a split: {n}`
  String sysAttnBehindDetail(Object n) {
    return Intl.message(
      'Forks moved aside after a split: $n',
      name: 'sysAttnBehindDetail',
      desc: '',
      args: [n],
    );
  }

  /// `standby_lag is above 0: a takeover now loses records`
  String get sysAttnBehindPlain {
    return Intl.message(
      'standby_lag is above 0: a takeover now loses records',
      name: 'sysAttnBehindPlain',
      desc: '',
      args: [],
    );
  }

  /// `Open Availability ›`
  String get sysAttnOpenAvail {
    return Intl.message(
      'Open Availability ›',
      name: 'sysAttnOpenAvail',
      desc: '',
      args: [],
    );
  }

  /// `{id} failed`
  String sysAttnLinkFailed(Object id) {
    return Intl.message(
      '$id failed',
      name: 'sysAttnLinkFailed',
      desc: '',
      args: [id],
    );
  }

  /// `sys/links/{id}/state is failed; its log says why`
  String sysAttnLinkDetail(Object id) {
    return Intl.message(
      'sys/links/$id/state is failed; its log says why',
      name: 'sysAttnLinkDetail',
      desc: '',
      args: [id],
    );
  }

  /// `Open in Links ›`
  String get sysAttnOpenLinks {
    return Intl.message(
      'Open in Links ›',
      name: 'sysAttnOpenLinks',
      desc: '',
      args: [],
    );
  }

  /// `{cn} waits in quarantine`
  String sysAttnQuarantine(Object cn) {
    return Intl.message(
      '$cn waits in quarantine',
      name: 'sysAttnQuarantine',
      desc: '',
      args: [cn],
    );
  }

  /// `Unknown certificate CN {cn} since {t}`
  String sysAttnQuarantineSince(Object cn, Object t) {
    return Intl.message(
      'Unknown certificate CN $cn since $t',
      name: 'sysAttnQuarantineSince',
      desc: '',
      args: [cn, t],
    );
  }

  /// `Unknown certificate CN {cn}`
  String sysAttnQuarantineDetail(Object cn) {
    return Intl.message(
      'Unknown certificate CN $cn',
      name: 'sysAttnQuarantineDetail',
      desc: '',
      args: [cn],
    );
  }

  /// `Open Quarantine ›`
  String get sysAttnOpenQuarantine {
    return Intl.message(
      'Open Quarantine ›',
      name: 'sysAttnOpenQuarantine',
      desc: '',
      args: [],
    );
  }

  /// `{site} waits for Authorize`
  String sysAttnBroker(Object site) {
    return Intl.message(
      '$site waits for Authorize',
      name: 'sysAttnBroker',
      desc: '',
      args: [site],
    );
  }

  /// `A downstream broker that relays sites: {n}`
  String sysAttnBrokerRelays(Object n) {
    return Intl.message(
      'A downstream broker that relays sites: $n',
      name: 'sysAttnBrokerRelays',
      desc: '',
      args: [n],
    );
  }

  /// `A downstream broker`
  String get sysAttnBrokerPlain {
    return Intl.message(
      'A downstream broker',
      name: 'sysAttnBrokerPlain',
      desc: '',
      args: [],
    );
  }

  /// `Open in Sites ›`
  String get sysAttnOpenSites {
    return Intl.message(
      'Open in Sites ›',
      name: 'sysAttnOpenSites',
      desc: '',
      args: [],
    );
  }

  /// `ACL denials grew by {n}`
  String sysAttnAcl(Object n) {
    return Intl.message(
      'ACL denials grew by $n',
      name: 'sysAttnAcl',
      desc: '',
      args: [n],
    );
  }

  /// `acl_denied was {from} when this screen was last shown`
  String sysAttnAclDetail(Object from) {
    return Intl.message(
      'acl_denied was $from when this screen was last shown',
      name: 'sysAttnAclDetail',
      desc: '',
      args: [from],
    );
  }

  /// `Open Audit ›`
  String get sysAttnOpenAudit {
    return Intl.message(
      'Open Audit ›',
      name: 'sysAttnOpenAudit',
      desc: '',
      args: [],
    );
  }

  /// `No standby follows this broker`
  String get sysAttnNoStandby {
    return Intl.message(
      'No standby follows this broker',
      name: 'sysAttnNoStandby',
      desc: '',
      args: [],
    );
  }

  /// `standby_connected is 0`
  String get sysAttnNoStandbyDetail {
    return Intl.message(
      'standby_connected is 0',
      name: 'sysAttnNoStandbyDetail',
      desc: '',
      args: [],
    );
  }

  /// `Nothing to show here.`
  String get treeEmpty {
    return Intl.message(
      'Nothing to show here.',
      name: 'treeEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Reading the tree…`
  String get treeLoading {
    return Intl.message(
      'Reading the tree…',
      name: 'treeLoading',
      desc: '',
      args: [],
    );
  }

  /// `Read`
  String get dropRead {
    return Intl.message('Read', name: 'dropRead', desc: '', args: []);
  }

  /// `Write`
  String get dropWrite {
    return Intl.message('Write', name: 'dropWrite', desc: '', args: []);
  }

  /// `This flow`
  String get myBlocksThisFlow {
    return Intl.message(
      'This flow',
      name: 'myBlocksThisFlow',
      desc: '',
      args: [],
    );
  }

  /// `Site library`
  String get myBlocksLibrary {
    return Intl.message(
      'Site library',
      name: 'myBlocksLibrary',
      desc: '',
      args: [],
    );
  }

  /// `No custom blocks yet. Select blocks on the canvas and choose Create custom block… in their menu.`
  String get myBlocksEmpty {
    return Intl.message(
      'No custom blocks yet. Select blocks on the canvas and choose Create custom block… in their menu.',
      name: 'myBlocksEmpty',
      desc: '',
      args: [],
    );
  }

  /// `This broker has no custom blocks: its flow engine is older than ADR 0040.`
  String get myBlocksOff {
    return Intl.message(
      'This broker has no custom blocks: its flow engine is older than ADR 0040.',
      name: 'myBlocksOff',
      desc: '',
      args: [],
    );
  }

  /// `Save to library`
  String get mbSave {
    return Intl.message('Save to library', name: 'mbSave', desc: '', args: []);
  }

  /// `Rename`
  String get mbRename {
    return Intl.message('Rename', name: 'mbRename', desc: '', args: []);
  }

  /// `Delete`
  String get mbDelete {
    return Intl.message('Delete', name: 'mbDelete', desc: '', args: []);
  }

  /// `Update from library`
  String get mbUpdate {
    return Intl.message(
      'Update from library',
      name: 'mbUpdate',
      desc: '',
      args: [],
    );
  }

  /// `Edit custom block`
  String get mbEdit {
    return Intl.message(
      'Edit custom block',
      name: 'mbEdit',
      desc: '',
      args: [],
    );
  }

  /// `Delete from library`
  String get mbRemoveLibrary {
    return Intl.message(
      'Delete from library',
      name: 'mbRemoveLibrary',
      desc: '',
      args: [],
    );
  }

  /// `{n, plural, =1{1 instance uses it} other{{n} instances use it}}`
  String mbInUse(int n) {
    return Intl.plural(
      n,
      one: '1 instance uses it',
      other: '$n instances use it',
      name: 'mbInUse',
      desc: '',
      args: [n],
    );
  }

  /// `The flow has the library's version`
  String get mbSameVersion {
    return Intl.message(
      'The flow has the library\'s version',
      name: 'mbSameVersion',
      desc: '',
      args: [],
    );
  }

  /// `The library has no block of this name`
  String get mbNotInLibrary {
    return Intl.message(
      'The library has no block of this name',
      name: 'mbNotInLibrary',
      desc: '',
      args: [],
    );
  }

  /// `Go back to the flow first`
  String get mbBackFirst {
    return Intl.message(
      'Go back to the flow first',
      name: 'mbBackFirst',
      desc: '',
      args: [],
    );
  }

  /// `A block cannot contain itself`
  String get mbInsideItself {
    return Intl.message(
      'A block cannot contain itself',
      name: 'mbInsideItself',
      desc: '',
      args: [],
    );
  }

  /// `{n} used`
  String mbUsed(int n) {
    return Intl.message('$n used', name: 'mbUsed', desc: '', args: [n]);
  }

  /// `v{n}`
  String mbVersion(int n) {
    return Intl.message('v$n', name: 'mbVersion', desc: '', args: [n]);
  }

  /// `library v{n}`
  String mbUpdateTo(int n) {
    return Intl.message('library v$n', name: 'mbUpdateTo', desc: '', args: [n]);
  }

  /// `Open inside`
  String get openInside {
    return Intl.message('Open inside', name: 'openInside', desc: '', args: []);
  }

  /// `My block`
  String get kindMyBlock {
    return Intl.message('My block', name: 'kindMyBlock', desc: '', args: []);
  }

  /// `Custom block`
  String get kindBlockPorts {
    return Intl.message(
      'Custom block',
      name: 'kindBlockPorts',
      desc: '',
      args: [],
    );
  }

  /// `Inputs`
  String get blockInputs {
    return Intl.message('Inputs', name: 'blockInputs', desc: '', args: []);
  }

  /// `Outputs`
  String get blockOutputs {
    return Intl.message('Outputs', name: 'blockOutputs', desc: '', args: []);
  }

  /// `What the block takes. Drag from an input to every inner field it feeds; type its default here. + adds an input.`
  String get noteBlockInputs {
    return Intl.message(
      'What the block takes. Drag from an input to every inner field it feeds; type its default here. + adds an input.',
      name: 'noteBlockInputs',
      desc: '',
      args: [],
    );
  }

  /// `What the block gives. Drag an inner output onto each. + adds an output.`
  String get noteBlockOutputs {
    return Intl.message(
      'What the block gives. Drag an inner output onto each. + adds an output.',
      name: 'noteBlockOutputs',
      desc: '',
      args: [],
    );
  }

  /// `{n, plural, =1{1 port} other{{n} ports}}`
  String portsCount(int n) {
    return Intl.plural(
      n,
      one: '1 port',
      other: '$n ports',
      name: 'portsCount',
      desc: '',
      args: [n],
    );
  }

  /// `Add a port`
  String get addPort {
    return Intl.message('Add a port', name: 'addPort', desc: '', args: []);
  }

  /// `Remove the last port`
  String get removePort {
    return Intl.message(
      'Remove the last port',
      name: 'removePort',
      desc: '',
      args: [],
    );
  }

  /// `Back`
  String get flowBack {
    return Intl.message('Back', name: 'flowBack', desc: '', args: []);
  }

  /// `{n, plural, =0{no instance in this flow} =1{1 instance in this flow} other{{n} instances in this flow}} · a change here changes them all`
  String instancesInFlow(int n) {
    return Intl.message(
      '${Intl.plural(n, zero: 'no instance in this flow', one: '1 instance in this flow', other: '$n instances in this flow')} · a change here changes them all',
      name: 'instancesInFlow',
      desc: '',
      args: [n],
    );
  }

  /// `Go back to the flow to deploy`
  String get deployInside {
    return Intl.message(
      'Go back to the flow to deploy',
      name: 'deployInside',
      desc: '',
      args: [],
    );
  }

  /// `Create custom block`
  String get cbTitle {
    return Intl.message(
      'Create custom block',
      name: 'cbTitle',
      desc: '',
      args: [],
    );
  }

  /// `{n, plural, =1{1 block becomes} other{{n} blocks become}} one block of this flow. Wires that cross its edge become its inputs and outputs.`
  String cbNote(int n) {
    return Intl.message(
      '${Intl.plural(n, one: '1 block becomes', other: '$n blocks become')} one block of this flow. Wires that cross its edge become its inputs and outputs.',
      name: 'cbNote',
      desc: '',
      args: [n],
    );
  }

  /// `Name`
  String get cbName {
    return Intl.message('Name', name: 'cbName', desc: '', args: []);
  }

  /// `Description`
  String get cbDescription {
    return Intl.message(
      'Description',
      name: 'cbDescription',
      desc: '',
      args: [],
    );
  }

  /// `Inputs`
  String get cbInputs {
    return Intl.message('Inputs', name: 'cbInputs', desc: '', args: []);
  }

  /// `Outputs`
  String get cbOutputs {
    return Intl.message('Outputs', name: 'cbOutputs', desc: '', args: []);
  }

  /// `default`
  String get cbDefault {
    return Intl.message('default', name: 'cbDefault', desc: '', args: []);
  }

  /// `none`
  String get cbNone {
    return Intl.message('none', name: 'cbNone', desc: '', args: []);
  }

  /// `Create`
  String get cbCreate {
    return Intl.message('Create', name: 'cbCreate', desc: '', args: []);
  }

  /// `A name has letters, digits and _ only`
  String get cbBadName {
    return Intl.message(
      'A name has letters, digits and _ only',
      name: 'cbBadName',
      desc: '',
      args: [],
    );
  }

  /// `This flow already has a block of this name`
  String get cbTaken {
    return Intl.message(
      'This flow already has a block of this name',
      name: 'cbTaken',
      desc: '',
      args: [],
    );
  }

  /// `A port's name has letters, digits and _ only`
  String get cbBadPort {
    return Intl.message(
      'A port\'s name has letters, digits and _ only',
      name: 'cbBadPort',
      desc: '',
      args: [],
    );
  }

  /// `Two ports have the same name`
  String get cbDuplicate {
    return Intl.message(
      'Two ports have the same name',
      name: 'cbDuplicate',
      desc: '',
      args: [],
    );
  }

  /// `At most 64 blocks, and 64 inputs and 64 outputs each`
  String get cbLimit {
    return Intl.message(
      'At most 64 blocks, and 64 inputs and 64 outputs each',
      name: 'cbLimit',
      desc: '',
      args: [],
    );
  }

  /// `This broker has no custom blocks (its flow engine is older than ADR 0040)`
  String get fmNeedsBroker {
    return Intl.message(
      'This broker has no custom blocks (its flow engine is older than ADR 0040)',
      name: 'fmNeedsBroker',
      desc: '',
      args: [],
    );
  }

  /// `Not a custom block`
  String get fmNotCustom {
    return Intl.message(
      'Not a custom block',
      name: 'fmNotCustom',
      desc: '',
      args: [],
    );
  }

  /// `This block may read keys under`
  String get scopeTitle {
    return Intl.message(
      'This block may read keys under',
      name: 'scopeTitle',
      desc: '',
      args: [],
    );
  }

  /// `A key that comes on the wire is read only inside this scope. Whoever deploys must be able to read all of it.`
  String get scopeNote {
    return Intl.message(
      'A key that comes on the wire is read only inside this scope. Whoever deploys must be able to read all of it.',
      name: 'scopeNote',
      desc: '',
      args: [],
    );
  }

  /// `Edit the scope`
  String get scopeEdit {
    return Intl.message(
      'Edit the scope',
      name: 'scopeEdit',
      desc: '',
      args: [],
    );
  }

  /// `Type a scope: a key from a wire needs one`
  String get scopeEmpty {
    return Intl.message(
      'Type a scope: a key from a wire needs one',
      name: 'scopeEmpty',
      desc: '',
      args: [],
    );
  }

  /// `A scope starts with downstream, dataflows or storage`
  String get scopeSection {
    return Intl.message(
      'A scope starts with downstream, dataflows or storage',
      name: 'scopeSection',
      desc: '',
      args: [],
    );
  }

  /// `A scope lies in this site`
  String get scopeOtherSite {
    return Intl.message(
      'A scope lies in this site',
      name: 'scopeOtherSite',
      desc: '',
      args: [],
    );
  }

  /// `Not a key expression: segments of letters, digits, _ . - or * and **`
  String get scopeSegment {
    return Intl.message(
      'Not a key expression: segments of letters, digits, _ . - or * and **',
      name: 'scopeSegment',
      desc: '',
      args: [],
    );
  }

  /// `This broker cannot bind {field} (its flow engine is older than ADR 0040)`
  String refuseNeedsBroker(String field) {
    return Intl.message(
      'This broker cannot bind $field (its flow engine is older than ADR 0040)',
      name: 'refuseNeedsBroker',
      desc: '',
      args: [field],
    );
  }

  /// `Target`
  String get grpTarget {
    return Intl.message('Target', name: 'grpTarget', desc: '', args: []);
  }

  /// `Arguments`
  String get grpArguments {
    return Intl.message('Arguments', name: 'grpArguments', desc: '', args: []);
  }

  /// `Behaviour`
  String get grpBehaviour {
    return Intl.message('Behaviour', name: 'grpBehaviour', desc: '', args: []);
  }

  /// `Events`
  String get grpEvents {
    return Intl.message('Events', name: 'grpEvents', desc: '', args: []);
  }

  /// `State`
  String get grpState {
    return Intl.message('State', name: 'grpState', desc: '', args: []);
  }

  /// `Run`
  String get runBlock {
    return Intl.message('Run', name: 'runBlock', desc: '', args: []);
  }

  /// `This broker has no trigger action (its flow engine is older than ADR 0040)`
  String get runNoBroker {
    return Intl.message(
      'This broker has no trigger action (its flow engine is older than ADR 0040)',
      name: 'runNoBroker',
      desc: '',
      args: [],
    );
  }

  /// `A sample on its wire presses it. Wire an event into it (a timer, a change, a point); Studio cannot press it in a running flow.`
  String get commandNote {
    return Intl.message(
      'A sample on its wire presses it. Wire an event into it (a timer, a change, a point); Studio cannot press it in a running flow.',
      name: 'commandNote',
      desc: '',
      args: [],
    );
  }

  /// `Add a row`
  String get rowsAdd {
    return Intl.message('Add a row', name: 'rowsAdd', desc: '', args: []);
  }

  /// `Remove this row`
  String get rowsRemove {
    return Intl.message(
      'Remove this row',
      name: 'rowsRemove',
      desc: '',
      args: [],
    );
  }

  /// `No rows yet`
  String get rowsEmpty {
    return Intl.message('No rows yet', name: 'rowsEmpty', desc: '', args: []);
  }

  /// `Choose a value`
  String get suggestPick {
    return Intl.message(
      'Choose a value',
      name: 'suggestPick',
      desc: '',
      args: [],
    );
  }

  /// `Deploy first: Run acts on the deployed version, and the draft differs from it`
  String get runDraft {
    return Intl.message(
      'Deploy first: Run acts on the deployed version, and the draft differs from it',
      name: 'runDraft',
      desc: '',
      args: [],
    );
  }

  /// `Deploy the flow first`
  String get runNotDeployed {
    return Intl.message(
      'Deploy the flow first',
      name: 'runNotDeployed',
      desc: '',
      args: [],
    );
  }

  /// `The block is disabled`
  String get runOff {
    return Intl.message(
      'The block is disabled',
      name: 'runOff',
      desc: '',
      args: [],
    );
  }

  /// `Open the block from an instance to run it`
  String get runNoInstance {
    return Intl.message(
      'Open the block from an instance to run it',
      name: 'runNoInstance',
      desc: '',
      args: [],
    );
  }

  /// `Run on every start?`
  String get runOnStartTitle {
    return Intl.message(
      'Run on every start?',
      name: 'runOnStartTitle',
      desc: '',
      args: [],
    );
  }

  /// `Turn on`
  String get turnOn {
    return Intl.message('Turn on', name: 'turnOn', desc: '', args: []);
  }

  /// `not yet`
  String get eventNone {
    return Intl.message('not yet', name: 'eventNone', desc: '', args: []);
  }

  /// `would send {value}`
  String wouldSend(String value) {
    return Intl.message(
      'would send $value',
      name: 'wouldSend',
      desc: '',
      args: [value],
    );
  }

  /// `An action of the tree. It runs on its trigger, on a changed argument, on a period, or by Run.`
  String get noteActionBlock {
    return Intl.message(
      'An action of the tree. It runs on its trigger, on a changed argument, on a period, or by Run.',
      name: 'noteActionBlock',
      desc: '',
      args: [],
    );
  }

  /// `a block that runs it: its parameters are fields you fill from other blocks, with a trigger.`
  String get treeActionNote2 {
    return Intl.message(
      'a block that runs it: its parameters are fields you fill from other blocks, with a trigger.',
      name: 'treeActionNote2',
      desc: '',
      args: [],
    );
  }

  /// `on the canvas: a block that reads it (a writable point asks Read or Write; Alt writes). On a field: wired into it.`
  String get treePointNote2 {
    return Intl.message(
      'on the canvas: a block that reads it (a writable point asks Read or Write; Alt writes). On a field: wired into it.',
      name: 'treePointNote2',
      desc: '',
      args: [],
    );
  }

  /// `You can’t {what}`
  String errTitleRights(String what) {
    return Intl.message(
      'You can’t $what',
      name: 'errTitleRights',
      desc: '',
      args: [what],
    );
  }

  /// `{site} did not answer`
  String errTitleReach(String site) {
    return Intl.message(
      '$site did not answer',
      name: 'errTitleReach',
      desc: '',
      args: [site],
    );
  }

  /// `The broker did not answer`
  String get errTitleReachNoSite {
    return Intl.message(
      'The broker did not answer',
      name: 'errTitleReachNoSite',
      desc: '',
      args: [],
    );
  }

  /// `Studio is not connected to a gateway`
  String get errTitleNotConnected {
    return Intl.message(
      'Studio is not connected to a gateway',
      name: 'errTitleNotConnected',
      desc: '',
      args: [],
    );
  }

  /// `The broker refused these parameters`
  String get errTitleInput {
    return Intl.message(
      'The broker refused these parameters',
      name: 'errTitleInput',
      desc: '',
      args: [],
    );
  }

  /// `The broker refused this value`
  String get errTitleInputValue {
    return Intl.message(
      'The broker refused this value',
      name: 'errTitleInputValue',
      desc: '',
      args: [],
    );
  }

  /// `{site} is busy, {what} did not start`
  String errTitleBusy(String site, String what) {
    return Intl.message(
      '$site is busy, $what did not start',
      name: 'errTitleBusy',
      desc: '',
      args: [site, what],
    );
  }

  /// `{thing} is not there anymore`
  String errTitleGone(String thing) {
    return Intl.message(
      '$thing is not there anymore',
      name: 'errTitleGone',
      desc: '',
      args: [thing],
    );
  }

  /// `{thing} does not support {call}`
  String errTitleUnsupported(String thing, String call) {
    return Intl.message(
      '$thing does not support $call',
      name: 'errTitleUnsupported',
      desc: '',
      args: [thing, call],
    );
  }

  /// `{doing} failed on {site}`
  String errTitleBroker(String doing, String site) {
    return Intl.message(
      '$doing failed on $site',
      name: 'errTitleBroker',
      desc: '',
      args: [doing, site],
    );
  }

  /// `{doing} failed`
  String errTitleBrokerNoSite(String doing) {
    return Intl.message(
      '$doing failed',
      name: 'errTitleBrokerNoSite',
      desc: '',
      args: [doing],
    );
  }

  /// `Studio could not {what}`
  String errTitleStudio(String what) {
    return Intl.message(
      'Studio could not $what',
      name: 'errTitleStudio',
      desc: '',
      args: [what],
    );
  }

  /// `Live values from {site} stopped`
  String errTitleStream(String site) {
    return Intl.message(
      'Live values from $site stopped',
      name: 'errTitleStream',
      desc: '',
      args: [site],
    );
  }

  /// `Reading {thing} failed`
  String errTitleRead(String thing) {
    return Intl.message(
      'Reading $thing failed',
      name: 'errTitleRead',
      desc: '',
      args: [thing],
    );
  }

  /// `History of {thing} unavailable`
  String errTitleHistory(String thing) {
    return Intl.message(
      'History of $thing unavailable',
      name: 'errTitleHistory',
      desc: '',
      args: [thing],
    );
  }

  /// `this`
  String get errThingThis {
    return Intl.message('this', name: 'errThingThis', desc: '', args: []);
  }

  /// `the broker`
  String get errThingBroker {
    return Intl.message(
      'the broker',
      name: 'errThingBroker',
      desc: '',
      args: [],
    );
  }

  /// `deploy {thing}`
  String errDoDeploy(String thing) {
    return Intl.message(
      'deploy $thing',
      name: 'errDoDeploy',
      desc: '',
      args: [thing],
    );
  }

  /// `Deploying {thing}`
  String errDoingDeploy(String thing) {
    return Intl.message(
      'Deploying $thing',
      name: 'errDoingDeploy',
      desc: '',
      args: [thing],
    );
  }

  /// `the deploy`
  String get errNounDeploy {
    return Intl.message(
      'the deploy',
      name: 'errNounDeploy',
      desc: '',
      args: [],
    );
  }

  /// `install {thing}`
  String errDoInstall(String thing) {
    return Intl.message(
      'install $thing',
      name: 'errDoInstall',
      desc: '',
      args: [thing],
    );
  }

  /// `Installing {thing}`
  String errDoingInstall(String thing) {
    return Intl.message(
      'Installing $thing',
      name: 'errDoingInstall',
      desc: '',
      args: [thing],
    );
  }

  /// `the install`
  String get errNounInstall {
    return Intl.message(
      'the install',
      name: 'errNounInstall',
      desc: '',
      args: [],
    );
  }

  /// `write {thing}`
  String errDoWrite(String thing) {
    return Intl.message(
      'write $thing',
      name: 'errDoWrite',
      desc: '',
      args: [thing],
    );
  }

  /// `Writing {thing}`
  String errDoingWrite(String thing) {
    return Intl.message(
      'Writing $thing',
      name: 'errDoingWrite',
      desc: '',
      args: [thing],
    );
  }

  /// `the write`
  String get errNounWrite {
    return Intl.message('the write', name: 'errNounWrite', desc: '', args: []);
  }

  /// `read {thing}`
  String errDoRead(String thing) {
    return Intl.message(
      'read $thing',
      name: 'errDoRead',
      desc: '',
      args: [thing],
    );
  }

  /// `Reading {thing}`
  String errDoingRead(String thing) {
    return Intl.message(
      'Reading $thing',
      name: 'errDoingRead',
      desc: '',
      args: [thing],
    );
  }

  /// `the read`
  String get errNounRead {
    return Intl.message('the read', name: 'errNounRead', desc: '', args: []);
  }

  /// `list {thing}`
  String errDoList(String thing) {
    return Intl.message(
      'list $thing',
      name: 'errDoList',
      desc: '',
      args: [thing],
    );
  }

  /// `Listing {thing}`
  String errDoingList(String thing) {
    return Intl.message(
      'Listing $thing',
      name: 'errDoingList',
      desc: '',
      args: [thing],
    );
  }

  /// `the list`
  String get errNounList {
    return Intl.message('the list', name: 'errNounList', desc: '', args: []);
  }

  /// `remove {thing}`
  String errDoRemove(String thing) {
    return Intl.message(
      'remove $thing',
      name: 'errDoRemove',
      desc: '',
      args: [thing],
    );
  }

  /// `Removing {thing}`
  String errDoingRemove(String thing) {
    return Intl.message(
      'Removing $thing',
      name: 'errDoingRemove',
      desc: '',
      args: [thing],
    );
  }

  /// `the removal`
  String get errNounRemove {
    return Intl.message(
      'the removal',
      name: 'errNounRemove',
      desc: '',
      args: [],
    );
  }

  /// `save {thing}`
  String errDoSave(String thing) {
    return Intl.message(
      'save $thing',
      name: 'errDoSave',
      desc: '',
      args: [thing],
    );
  }

  /// `Saving {thing}`
  String errDoingSave(String thing) {
    return Intl.message(
      'Saving $thing',
      name: 'errDoingSave',
      desc: '',
      args: [thing],
    );
  }

  /// `the save`
  String get errNounSave {
    return Intl.message('the save', name: 'errNounSave', desc: '', args: []);
  }

  /// `start {thing}`
  String errDoStart(String thing) {
    return Intl.message(
      'start $thing',
      name: 'errDoStart',
      desc: '',
      args: [thing],
    );
  }

  /// `Starting {thing}`
  String errDoingStart(String thing) {
    return Intl.message(
      'Starting $thing',
      name: 'errDoingStart',
      desc: '',
      args: [thing],
    );
  }

  /// `the start`
  String get errNounStart {
    return Intl.message('the start', name: 'errNounStart', desc: '', args: []);
  }

  /// `stop {thing}`
  String errDoStop(String thing) {
    return Intl.message(
      'stop $thing',
      name: 'errDoStop',
      desc: '',
      args: [thing],
    );
  }

  /// `Stopping {thing}`
  String errDoingStop(String thing) {
    return Intl.message(
      'Stopping $thing',
      name: 'errDoingStop',
      desc: '',
      args: [thing],
    );
  }

  /// `the stop`
  String get errNounStop {
    return Intl.message('the stop', name: 'errNounStop', desc: '', args: []);
  }

  /// `open {thing}`
  String errDoOpen(String thing) {
    return Intl.message(
      'open $thing',
      name: 'errDoOpen',
      desc: '',
      args: [thing],
    );
  }

  /// `Opening {thing}`
  String errDoingOpen(String thing) {
    return Intl.message(
      'Opening $thing',
      name: 'errDoingOpen',
      desc: '',
      args: [thing],
    );
  }

  /// `the opening`
  String get errNounOpen {
    return Intl.message('the opening', name: 'errNounOpen', desc: '', args: []);
  }

  /// `log in to {thing}`
  String errDoLogIn(String thing) {
    return Intl.message(
      'log in to $thing',
      name: 'errDoLogIn',
      desc: '',
      args: [thing],
    );
  }

  /// `Logging in to {thing}`
  String errDoingLogIn(String thing) {
    return Intl.message(
      'Logging in to $thing',
      name: 'errDoingLogIn',
      desc: '',
      args: [thing],
    );
  }

  /// `the log-in`
  String get errNounLogIn {
    return Intl.message('the log-in', name: 'errNounLogIn', desc: '', args: []);
  }

  /// `run {call} on {thing}`
  String errDoRun(String call, String thing) {
    return Intl.message(
      'run $call on $thing',
      name: 'errDoRun',
      desc: '',
      args: [call, thing],
    );
  }

  /// `{call} on {thing}`
  String errDoingRun(String call, String thing) {
    return Intl.message(
      '$call on $thing',
      name: 'errDoingRun',
      desc: '',
      args: [call, thing],
    );
  }

  /// `{call}`
  String errNounRun(String call) {
    return Intl.message('$call', name: 'errNounRun', desc: '', args: [call]);
  }

  /// `finish “{step}”`
  String errDoStep(String step) {
    return Intl.message(
      'finish “$step”',
      name: 'errDoStep',
      desc: '',
      args: [step],
    );
  }

  /// `The broker said`
  String get errSaidBroker {
    return Intl.message(
      'The broker said',
      name: 'errSaidBroker',
      desc: '',
      args: [],
    );
  }

  /// `Studio waited`
  String get errSaidNoAnswer {
    return Intl.message(
      'Studio waited',
      name: 'errSaidNoAnswer',
      desc: '',
      args: [],
    );
  }

  /// `What happened`
  String get errSaidStudio {
    return Intl.message(
      'What happened',
      name: 'errSaidStudio',
      desc: '',
      args: [],
    );
  }

  /// `No answer from the broker at {site}.`
  String errSilentReach(String site) {
    return Intl.message(
      'No answer from the broker at $site.',
      name: 'errSilentReach',
      desc: '',
      args: [site],
    );
  }

  /// `The broker answered {status} and sent no message.`
  String errSilentStatus(String status) {
    return Intl.message(
      'The broker answered $status and sent no message.',
      name: 'errSilentStatus',
      desc: '',
      args: [status],
    );
  }

  /// `Something in Studio failed here. This is a fault in Studio, not on the broker; nothing more was sent.`
  String get errFaultMessage {
    return Intl.message(
      'Something in Studio failed here. This is a fault in Studio, not on the broker; nothing more was sent.',
      name: 'errFaultMessage',
      desc: '',
      args: [],
    );
  }

  /// `What you can do`
  String get errWhatYouCanDo {
    return Intl.message(
      'What you can do',
      name: 'errWhatYouCanDo',
      desc: '',
      args: [],
    );
  }

  /// `Ask an administrator for the right, or ask one to do it.`
  String get errAdviceRights {
    return Intl.message(
      'Ask an administrator for the right, or ask one to do it.',
      name: 'errAdviceRights',
      desc: '',
      args: [],
    );
  }

  /// `Your role is {role}. Nothing was changed on {site}.`
  String errAdviceRightsRole(String role, String site) {
    return Intl.message(
      'Your role is $role. Nothing was changed on $site.',
      name: 'errAdviceRightsRole',
      desc: '',
      args: [role, site],
    );
  }

  /// `Try again; if it keeps failing, look at the link’s status in Links.`
  String get errAdviceReach {
    return Intl.message(
      'Try again; if it keeps failing, look at the link’s status in Links.',
      name: 'errAdviceReach',
      desc: '',
      args: [],
    );
  }

  /// `Log in again: Studio has no session with a gateway.`
  String get errAdviceReachLogin {
    return Intl.message(
      'Log in again: Studio has no session with a gateway.',
      name: 'errAdviceReachLogin',
      desc: '',
      args: [],
    );
  }

  /// `Back in the form, the field {field} is marked; correct it and send again.`
  String errAdviceInputField(String field) {
    return Intl.message(
      'Back in the form, the field $field is marked; correct it and send again.',
      name: 'errAdviceInputField',
      desc: '',
      args: [field],
    );
  }

  /// `Back in the form, correct the values and send again.`
  String get errAdviceInput {
    return Intl.message(
      'Back in the form, correct the values and send again.',
      name: 'errAdviceInput',
      desc: '',
      args: [],
    );
  }

  /// `Studio can try again by itself when the broker is ready.`
  String get errAdviceBusyAuto {
    return Intl.message(
      'Studio can try again by itself when the broker is ready.',
      name: 'errAdviceBusyAuto',
      desc: '',
      args: [],
    );
  }

  /// `Wait a moment and try again.`
  String get errAdviceBusy {
    return Intl.message(
      'Wait a moment and try again.',
      name: 'errAdviceBusy',
      desc: '',
      args: [],
    );
  }

  /// `Someone removed or renamed it after this screen loaded. Refresh to see what is there now.`
  String get errAdviceGone {
    return Intl.message(
      'Someone removed or renamed it after this screen loaded. Refresh to see what is there now.',
      name: 'errAdviceGone',
      desc: '',
      args: [],
    );
  }

  /// `This broker or link does not have this call; it may be older than Studio expects.`
  String get errAdviceUnsupported {
    return Intl.message(
      'This broker or link does not have this call; it may be older than Studio expects.',
      name: 'errAdviceUnsupported',
      desc: '',
      args: [],
    );
  }

  /// `The broker log around {time} has the rest of the story.`
  String errAdviceBroker(String time) {
    return Intl.message(
      'The broker log around $time has the rest of the story.',
      name: 'errAdviceBroker',
      desc: '',
      args: [time],
    );
  }

  /// `The call reached the broker and it answered no. Check what it names above.`
  String get errAdviceBrokerSaid {
    return Intl.message(
      'The call reached the broker and it answered no. Check what it names above.',
      name: 'errAdviceBrokerSaid',
      desc: '',
      args: [],
    );
  }

  /// `Try it again; restart Studio if it keeps happening.`
  String get errAdviceStudio {
    return Intl.message(
      'Try it again; restart Studio if it keeps happening.',
      name: 'errAdviceStudio',
      desc: '',
      args: [],
    );
  }

  /// `Copy the report and send it to us: it holds no values or passwords.`
  String get errAdviceReport {
    return Intl.message(
      'Copy the report and send it to us: it holds no values or passwords.',
      name: 'errAdviceReport',
      desc: '',
      args: [],
    );
  }

  /// `A write that timed out may still have been applied. Check the value before you send it again.`
  String get errWriteNote {
    return Intl.message(
      'A write that timed out may still have been applied. Check the value before you send it again.',
      name: 'errWriteNote',
      desc: '',
      args: [],
    );
  }

  /// `Details`
  String get errDetails {
    return Intl.message('Details', name: 'errDetails', desc: '', args: []);
  }

  /// `Status`
  String get errRowStatus {
    return Intl.message('Status', name: 'errRowStatus', desc: '', args: []);
  }

  /// `Call`
  String get errRowCall {
    return Intl.message('Call', name: 'errRowCall', desc: '', args: []);
  }

  /// `Site`
  String get errRowSite {
    return Intl.message('Site', name: 'errRowSite', desc: '', args: []);
  }

  /// `As`
  String get errRowAs {
    return Intl.message('As', name: 'errRowAs', desc: '', args: []);
  }

  /// `Gateway`
  String get errRowGateway {
    return Intl.message('Gateway', name: 'errRowGateway', desc: '', args: []);
  }

  /// `Time`
  String get errRowTime {
    return Intl.message('Time', name: 'errRowTime', desc: '', args: []);
  }

  /// `Error`
  String get errRowError {
    return Intl.message('Error', name: 'errRowError', desc: '', args: []);
  }

  /// `In`
  String get errRowIn {
    return Intl.message('In', name: 'errRowIn', desc: '', args: []);
  }

  /// `Screen`
  String get errRowScreen {
    return Intl.message('Screen', name: 'errRowScreen', desc: '', args: []);
  }

  /// `Studio`
  String get errRowStudio {
    return Intl.message('Studio', name: 'errRowStudio', desc: '', args: []);
  }

  /// `Report`
  String get errRowReport {
    return Intl.message('Report', name: 'errRowReport', desc: '', args: []);
  }

  /// `the stack trace is in the copied report only`
  String get errReportNote {
    return Intl.message(
      'the stack trace is in the copied report only',
      name: 'errReportNote',
      desc: '',
      args: [],
    );
  }

  /// `{call} on {key}`
  String errCallOn(String call, String key) {
    return Intl.message(
      '$call on $key',
      name: 'errCallOn',
      desc: '',
      args: [call, key],
    );
  }

  /// `{time} (local)`
  String errTimeLocal(String time) {
    return Intl.message(
      '$time (local)',
      name: 'errTimeLocal',
      desc: '',
      args: [time],
    );
  }

  /// `{user} ({role})`
  String errUserRole(String user, String role) {
    return Intl.message(
      '$user ($role)',
      name: 'errUserRole',
      desc: '',
      args: [user, role],
    );
  }

  /// `Copy details`
  String get errCopyDetails {
    return Intl.message(
      'Copy details',
      name: 'errCopyDetails',
      desc: '',
      args: [],
    );
  }

  /// `Copy report`
  String get errCopyReport {
    return Intl.message(
      'Copy report',
      name: 'errCopyReport',
      desc: '',
      args: [],
    );
  }

  /// `Try again`
  String get errTryAgain {
    return Intl.message('Try again', name: 'errTryAgain', desc: '', args: []);
  }

  /// `Try again in {seconds} s`
  String errTryAgainIn(int seconds) {
    return Intl.message(
      'Try again in $seconds s',
      name: 'errTryAgainIn',
      desc: '',
      args: [seconds],
    );
  }

  /// `Back to the form`
  String get errBackToForm {
    return Intl.message(
      'Back to the form',
      name: 'errBackToForm',
      desc: '',
      args: [],
    );
  }

  /// `Refresh`
  String get errRefresh {
    return Intl.message('Refresh', name: 'errRefresh', desc: '', args: []);
  }

  /// `Open the log`
  String get errOpenLog {
    return Intl.message('Open the log', name: 'errOpenLog', desc: '', args: []);
  }

  /// `See my access`
  String get errSeeAccess {
    return Intl.message(
      'See my access',
      name: 'errSeeAccess',
      desc: '',
      args: [],
    );
  }

  /// `Copied`
  String get errCopied {
    return Intl.message('Copied', name: 'errCopied', desc: '', args: []);
  }

  /// `The details are on the clipboard.`
  String get errDetailsCopied {
    return Intl.message(
      'The details are on the clipboard.',
      name: 'errDetailsCopied',
      desc: '',
      args: [],
    );
  }

  /// `The report is on the clipboard.`
  String get errReportCopied {
    return Intl.message(
      'The report is on the clipboard.',
      name: 'errReportCopied',
      desc: '',
      args: [],
    );
  }

  /// `Problems · this session`
  String get problemsTitle {
    return Intl.message(
      'Problems · this session',
      name: 'problemsTitle',
      desc: '',
      args: [],
    );
  }

  /// `Clear all`
  String get problemsClear {
    return Intl.message('Clear all', name: 'problemsClear', desc: '', args: []);
  }

  /// `Close problems`
  String get problemsClose {
    return Intl.message(
      'Close problems',
      name: 'problemsClose',
      desc: '',
      args: [],
    );
  }

  /// `Failures of things Studio did on its own (reads, refreshes, live values) and every dialog you closed. Kept until Studio quits; newest first.`
  String get problemsNote {
    return Intl.message(
      'Failures of things Studio did on its own (reads, refreshes, live values) and every dialog you closed. Kept until Studio quits; newest first.',
      name: 'problemsNote',
      desc: '',
      args: [],
    );
  }

  /// `No problems in this session.`
  String get problemsEmpty {
    return Intl.message(
      'No problems in this session.',
      name: 'problemsEmpty',
      desc: '',
      args: [],
    );
  }

  /// `shown as a dialog`
  String get problemsShown {
    return Intl.message(
      'shown as a dialog',
      name: 'problemsShown',
      desc: '',
      args: [],
    );
  }

  /// `hides in {seconds} s`
  String toastHidesIn(int seconds) {
    return Intl.message(
      'hides in $seconds s',
      name: 'toastHidesIn',
      desc: '',
      args: [seconds],
    );
  }

  /// `stays until {site} is back`
  String toastStays(String site) {
    return Intl.message(
      'stays until $site is back',
      name: 'toastStays',
      desc: '',
      args: [site],
    );
  }

  /// `Dismiss`
  String get toastDismiss {
    return Intl.message('Dismiss', name: 'toastDismiss', desc: '', args: []);
  }

  /// `Studio reopens the streams when it is back.`
  String get toastStream {
    return Intl.message(
      'Studio reopens the streams when it is back.',
      name: 'toastStream',
      desc: '',
      args: [],
    );
  }

  /// `Notifications`
  String get toastNotifications {
    return Intl.message(
      'Notifications',
      name: 'toastNotifications',
      desc: '',
      args: [],
    );
  }

  /// `read failed`
  String get readFailed {
    return Intl.message('read failed', name: 'readFailed', desc: '', args: []);
  }

  /// `Reading the value failed: {status}. Details in Problems.`
  String readFailedTip(String status) {
    return Intl.message(
      'Reading the value failed: $status. Details in Problems.',
      name: 'readFailedTip',
      desc: '',
      args: [status],
    );
  }

  /// `Reading the list of children failed: {status}. Details in Problems.`
  String listFailedTip(String status) {
    return Intl.message(
      'Reading the list of children failed: $status. Details in Problems.',
      name: 'listFailedTip',
      desc: '',
      args: [status],
    );
  }

  /// `Reading the description failed: {status}. Details in Problems.`
  String metaFailedTip(String status) {
    return Intl.message(
      'Reading the description failed: $status. Details in Problems.',
      name: 'metaFailedTip',
      desc: '',
      args: [status],
    );
  }

  /// `Read again`
  String get readAgain {
    return Intl.message('Read again', name: 'readAgain', desc: '', args: []);
  }

  /// `history unavailable`
  String get historyUnavailable {
    return Intl.message(
      'history unavailable',
      name: 'historyUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `Reading the history failed: {status}. Details in Problems.`
  String historyUnavailableTip(String status) {
    return Intl.message(
      'Reading the history failed: $status. Details in Problems.',
      name: 'historyUnavailableTip',
      desc: '',
      args: [status],
    );
  }

  /// `The {panel} could not be drawn`
  String faultTitle(String panel) {
    return Intl.message(
      'The $panel could not be drawn',
      name: 'faultTitle',
      desc: '',
      args: [panel],
    );
  }

  /// `This part could not be drawn`
  String get faultTitleThis {
    return Intl.message(
      'This part could not be drawn',
      name: 'faultTitleThis',
      desc: '',
      args: [],
    );
  }

  /// `The rest of Studio still works; values and actions elsewhere are not affected.`
  String get faultBody {
    return Intl.message(
      'The rest of Studio still works; values and actions elsewhere are not affected.',
      name: 'faultBody',
      desc: '',
      args: [],
    );
  }

  /// `Draw it again`
  String get faultDrawAgain {
    return Intl.message(
      'Draw it again',
      name: 'faultDrawAgain',
      desc: '',
      args: [],
    );
  }

  /// `Studio could not draw {panel}`
  String faultProblem(String panel) {
    return Intl.message(
      'Studio could not draw $panel',
      name: 'faultProblem',
      desc: '',
      args: [panel],
    );
  }

  /// `this part`
  String get faultThisPart {
    return Intl.message('this part', name: 'faultThisPart', desc: '', args: []);
  }

  /// `Studio hit a fault in the background`
  String get faultUncaught {
    return Intl.message(
      'Studio hit a fault in the background',
      name: 'faultUncaught',
      desc: '',
      args: [],
    );
  }

  /// `tree`
  String get panelTree {
    return Intl.message('tree', name: 'panelTree', desc: '', args: []);
  }

  /// `inspector`
  String get panelInspector {
    return Intl.message(
      'inspector',
      name: 'panelInspector',
      desc: '',
      args: [],
    );
  }

  /// `editor canvas`
  String get panelCanvas {
    return Intl.message(
      'editor canvas',
      name: 'panelCanvas',
      desc: '',
      args: [],
    );
  }

  /// `drawer`
  String get panelDrawer {
    return Intl.message('drawer', name: 'panelDrawer', desc: '', args: []);
  }

  /// `workspace`
  String get panelWorkspace {
    return Intl.message(
      'workspace',
      name: 'panelWorkspace',
      desc: '',
      args: [],
    );
  }

  /// `Studio could not start`
  String get fatalTitle {
    return Intl.message(
      'Studio could not start',
      name: 'fatalTitle',
      desc: '',
      args: [],
    );
  }

  /// `The settings it saved on this computer are unreadable, so it cannot tell which gateways you use. Your brokers are not affected: nothing on them depends on Studio.`
  String get fatalBody {
    return Intl.message(
      'The settings it saved on this computer are unreadable, so it cannot tell which gateways you use. Your brokers are not affected: nothing on them depends on Studio.',
      name: 'fatalBody',
      desc: '',
      args: [],
    );
  }

  /// `File`
  String get fatalFile {
    return Intl.message('File', name: 'fatalFile', desc: '', args: []);
  }

  /// `Start with fresh settings`
  String get fatalFresh {
    return Intl.message(
      'Start with fresh settings',
      name: 'fatalFresh',
      desc: '',
      args: [],
    );
  }

  /// `Quit`
  String get fatalQuit {
    return Intl.message('Quit', name: 'fatalQuit', desc: '', args: []);
  }

  /// `Fresh settings keep the unreadable file beside the new one as {name}. You add your gateways and log in again.`
  String fatalNote(String name) {
    return Intl.message(
      'Fresh settings keep the unreadable file beside the new one as $name. You add your gateways and log in again.',
      name: 'fatalNote',
      desc: '',
      args: [name],
    );
  }

  /// `The unreadable file could not be moved aside: {reason}`
  String fatalMoveFailed(String reason) {
    return Intl.message(
      'The unreadable file could not be moved aside: $reason',
      name: 'fatalMoveFailed',
      desc: '',
      args: [reason],
    );
  }

  /// `Not JSON: {detail}`
  String paramsNotJson(String detail) {
    return Intl.message(
      'Not JSON: $detail',
      name: 'paramsNotJson',
      desc: '',
      args: [detail],
    );
  }

  /// `The parameters must be one JSON object.`
  String get paramsNotObject {
    return Intl.message(
      'The parameters must be one JSON object.',
      name: 'paramsNotObject',
      desc: '',
      args: [],
    );
  }

  /// `{version} ({os})`
  String studioAbout(String version, String os) {
    return Intl.message(
      '$version ($os)',
      name: 'studioAbout',
      desc: '',
      args: [version, os],
    );
  }

  /// `{count, plural, =1{1 problem} other{{count} problems}}`
  String problemsCount(int count) {
    return Intl.plural(
      count,
      one: '1 problem',
      other: '$count problems',
      name: 'problemsCount',
      desc: '',
      args: [count],
    );
  }

  /// `{status}: {message}`
  String errStatusLine(String status, String message) {
    return Intl.message(
      '$status: $message',
      name: 'errStatusLine',
      desc: '',
      args: [status, message],
    );
  }

  /// `studio · {type}`
  String errChipStudio(String type) {
    return Intl.message(
      'studio · $type',
      name: 'errChipStudio',
      desc: '',
      args: [type],
    );
  }

  /// `Studio could not finish this`
  String get errTitlePlain {
    return Intl.message(
      'Studio could not finish this',
      name: 'errTitlePlain',
      desc: '',
      args: [],
    );
  }

  /// `{name}`
  String screenOf(String name) {
    return Intl.message('$name', name: 'screenOf', desc: '', args: [name]);
  }

  /// `Pick a point to see its trend`
  String get pickPointTrend {
    return Intl.message(
      'Pick a point to see its trend',
      name: 'pickPointTrend',
      desc: '',
      args: [],
    );
  }

  /// `Click a point to see its trend; ⌘/Ctrl-click adds up to three.`
  String get pickPointHint {
    return Intl.message(
      'Click a point to see its trend; ⌘/Ctrl-click adds up to three.',
      name: 'pickPointHint',
      desc: '',
      args: [],
    );
  }

  /// `Stop recording`
  String get stopRecording {
    return Intl.message(
      'Stop recording',
      name: 'stopRecording',
      desc: '',
      args: [],
    );
  }

  /// `Values on the trend`
  String get colReadRows {
    return Intl.message(
      'Values on the trend',
      name: 'colReadRows',
      desc: '',
      args: [],
    );
  }

  /// `Filter rows`
  String get tableFilter {
    return Intl.message('Filter rows', name: 'tableFilter', desc: '', args: []);
  }

  /// `{shown} of {total} rows`
  String tableFiltered(int shown, int total) {
    return Intl.message(
      '$shown of $total rows',
      name: 'tableFiltered',
      desc: '',
      args: [shown, total],
    );
  }

  /// `Add row`
  String get tableAddRow {
    return Intl.message('Add row', name: 'tableAddRow', desc: '', args: []);
  }

  /// `Add column`
  String get tableAddColumn {
    return Intl.message(
      'Add column',
      name: 'tableAddColumn',
      desc: '',
      args: [],
    );
  }

  /// `More`
  String get tableMore {
    return Intl.message('More', name: 'tableMore', desc: '', args: []);
  }

  /// `Rename column`
  String get tableRenameColumn {
    return Intl.message(
      'Rename column',
      name: 'tableRenameColumn',
      desc: '',
      args: [],
    );
  }

  /// `Remove row`
  String get tableRemoveRow {
    return Intl.message(
      'Remove row',
      name: 'tableRemoveRow',
      desc: '',
      args: [],
    );
  }

  /// `Remove column`
  String get tableRemoveColumn {
    return Intl.message(
      'Remove column',
      name: 'tableRemoveColumn',
      desc: '',
      args: [],
    );
  }

  /// `No rows`
  String get tableNoRows {
    return Intl.message('No rows', name: 'tableNoRows', desc: '', args: []);
  }

  /// `No columns yet. Add one with Add column.`
  String get tableNoColumnsEdit {
    return Intl.message(
      'No columns yet. Add one with Add column.',
      name: 'tableNoColumnsEdit',
      desc: '',
      args: [],
    );
  }

  /// `Refused: a table holds at most 10 000 rows.`
  String get tableRefusedRows {
    return Intl.message(
      'Refused: a table holds at most 10 000 rows.',
      name: 'tableRefusedRows',
      desc: '',
      args: [],
    );
  }

  /// `Refused: a table holds at most 128 columns.`
  String get tableRefusedColumns {
    return Intl.message(
      'Refused: a table holds at most 128 columns.',
      name: 'tableRefusedColumns',
      desc: '',
      args: [],
    );
  }

  /// `Refused: the cells of a table hold at most 512 KiB.`
  String get tableRefusedBytes {
    return Intl.message(
      'Refused: the cells of a table hold at most 512 KiB.',
      name: 'tableRefusedBytes',
      desc: '',
      args: [],
    );
  }

  /// `Refused: a column name has 1 to 256 bytes.`
  String get tableRefusedName {
    return Intl.message(
      'Refused: a column name has 1 to 256 bytes.',
      name: 'tableRefusedName',
      desc: '',
      args: [],
    );
  }

  /// `Refused: the table already has a column with this name.`
  String get tableRefusedNameTaken {
    return Intl.message(
      'Refused: the table already has a column with this name.',
      name: 'tableRefusedNameTaken',
      desc: '',
      args: [],
    );
  }

  /// `{count, plural, =1{1 more line} other{{count} more lines}}`
  String moreLines(int count) {
    return Intl.plural(
      count,
      one: '1 more line',
      other: '$count more lines',
      name: 'moreLines',
      desc: '',
      args: [count],
    );
  }

  /// `Copy CSV`
  String get viewerCopyCsv {
    return Intl.message('Copy CSV', name: 'viewerCopyCsv', desc: '', args: []);
  }

  /// `Copy JSON`
  String get viewerCopyJson {
    return Intl.message(
      'Copy JSON',
      name: 'viewerCopyJson',
      desc: '',
      args: [],
    );
  }

  /// `Edit as JSON`
  String get viewerEditJson {
    return Intl.message(
      'Edit as JSON',
      name: 'viewerEditJson',
      desc: '',
      args: [],
    );
  }

  /// `Text`
  String get viewerTabText {
    return Intl.message('Text', name: 'viewerTabText', desc: '', args: []);
  }

  /// `As table`
  String get viewerTabTable {
    return Intl.message('As table', name: 'viewerTabTable', desc: '', args: []);
  }

  /// `Read as the block reads it: delimiter {delimiter}, {header}`
  String viewerCsvRules(String delimiter, String header) {
    return Intl.message(
      'Read as the block reads it: delimiter $delimiter, $header',
      name: 'viewerCsvRules',
      desc: '',
      args: [delimiter, header],
    );
  }

  /// `the first row names the columns`
  String get viewerCsvHeaderOn {
    return Intl.message(
      'the first row names the columns',
      name: 'viewerCsvHeaderOn',
      desc: '',
      args: [],
    );
  }

  /// `no header row`
  String get viewerCsvHeaderOff {
    return Intl.message(
      'no header row',
      name: 'viewerCsvHeaderOff',
      desc: '',
      args: [],
    );
  }

  /// `A wire feeds the delimiter or the header: the table uses the values they hold now.`
  String get viewerCsvWired {
    return Intl.message(
      'A wire feeds the delimiter or the header: the table uses the values they hold now.',
      name: 'viewerCsvWired',
      desc: '',
      args: [],
    );
  }

  /// `The block refuses this text (parse_error): it has no row, or it passes a bound of a table.`
  String get viewerCsvRefused {
    return Intl.message(
      'The block refuses this text (parse_error): it has no row, or it passes a bound of a table.',
      name: 'viewerCsvRefused',
      desc: '',
      args: [],
    );
  }

  /// `Discard`
  String get viewerDiscard {
    return Intl.message('Discard', name: 'viewerDiscard', desc: '', args: []);
  }

  /// `{keys} saves · Esc discards the changes`
  String viewerTableHint(String keys) {
    return Intl.message(
      '$keys saves · Esc discards the changes',
      name: 'viewerTableHint',
      desc: '',
      args: [keys],
    );
  }

  /// `Hover for values · drag on the chart to zoom · click to set marker A · drag or resize the window below · double-click resets · ← → move the focused handle`
  String get trendHint {
    return Intl.message(
      'Hover for values · drag on the chart to zoom · click to set marker A · drag or resize the window below · double-click resets · ← → move the focused handle',
      name: 'trendHint',
      desc: '',
      args: [],
    );
  }

  /// `Reset zoom`
  String get trendResetZoom {
    return Intl.message(
      'Reset zoom',
      name: 'trendResetZoom',
      desc: '',
      args: [],
    );
  }

  /// `Follow now`
  String get trendFollowNow {
    return Intl.message(
      'Follow now',
      name: 'trendFollowNow',
      desc: '',
      args: [],
    );
  }

  /// `no data`
  String get trendNoData {
    return Intl.message('no data', name: 'trendNoData', desc: '', args: []);
  }

  /// `no data recorded`
  String get trendNoDataRecorded {
    return Intl.message(
      'no data recorded',
      name: 'trendNoDataRecorded',
      desc: '',
      args: [],
    );
  }

  /// `bad quality recorded`
  String get trendBadRecorded {
    return Intl.message(
      'bad quality recorded',
      name: 'trendBadRecorded',
      desc: '',
      args: [],
    );
  }

  /// `all`
  String get trendAll {
    return Intl.message('all', name: 'trendAll', desc: '', args: []);
  }

  /// `now`
  String get trendNow {
    return Intl.message('now', name: 'trendNow', desc: '', args: []);
  }

  /// `No values recorded in this range.`
  String get trendNothing {
    return Intl.message(
      'No values recorded in this range.',
      name: 'trendNothing',
      desc: '',
      args: [],
    );
  }

  /// `All series are hidden.`
  String get trendAllHidden {
    return Intl.message(
      'All series are hidden.',
      name: 'trendAllHidden',
      desc: '',
      args: [],
    );
  }

  /// `You may not read {key}`
  String trendLocked(String key) {
    return Intl.message(
      'You may not read $key',
      name: 'trendLocked',
      desc: '',
      args: [key],
    );
  }

  /// `Show or hide {name}`
  String trendShowHide(String name) {
    return Intl.message(
      'Show or hide $name',
      name: 'trendShowHide',
      desc: '',
      args: [name],
    );
  }

  /// `Click to set marker A`
  String get trendSetMarker {
    return Intl.message(
      'Click to set marker A',
      name: 'trendSetMarker',
      desc: '',
      args: [],
    );
  }

  /// `Click A again to clear it`
  String get trendClearMarker {
    return Intl.message(
      'Click A again to clear it',
      name: 'trendClearMarker',
      desc: '',
      args: [],
    );
  }

  /// `A · {t}`
  String trendMarker(String t) {
    return Intl.message('A · $t', name: 'trendMarker', desc: '', args: [t]);
  }

  /// `min {min} · max {max}`
  String trendMinMax(String min, String max) {
    return Intl.message(
      'min $min · max $max',
      name: 'trendMinMax',
      desc: '',
      args: [min, max],
    );
  }

  /// `uncertain · stale reads in this bucket`
  String get trendUncertain {
    return Intl.message(
      'uncertain · stale reads in this bucket',
      name: 'trendUncertain',
      desc: '',
      args: [],
    );
  }

  /// `Δ from A ({at}): {delta} {key} over {over}`
  String trendDelta(String at, String delta, String key, String over) {
    return Intl.message(
      'Δ from A ($at): $delta $key over $over',
      name: 'trendDelta',
      desc: '',
      args: [at, delta, key, over],
    );
  }

  /// `{h} h {m} min`
  String trendHoursMinutes(String h, String m) {
    return Intl.message(
      '$h h $m min',
      name: 'trendHoursMinutes',
      desc: '',
      args: [h, m],
    );
  }

  /// `{m} min`
  String trendMinutes(String m) {
    return Intl.message('$m min', name: 'trendMinutes', desc: '', args: [m]);
  }

  /// `{s} s`
  String trendSeconds(String s) {
    return Intl.message('$s s', name: 'trendSeconds', desc: '', args: [s]);
  }

  /// `{rollup} · {from}–{to}`
  String trendBucket(String rollup, String from, String to) {
    return Intl.message(
      '$rollup · $from–$to',
      name: 'trendBucket',
      desc: '',
      args: [rollup, from, to],
    );
  }

  /// `raw · {t}`
  String trendRawAt(String t) {
    return Intl.message('raw · $t', name: 'trendRawAt', desc: '', args: [t]);
  }

  /// `raw`
  String get trendRaw {
    return Intl.message('raw', name: 'trendRaw', desc: '', args: []);
  }

  /// `{step} avg`
  String trendAvg(String step) {
    return Intl.message('$step avg', name: 'trendAvg', desc: '', args: [step]);
  }

  /// `{n} min`
  String trendStepMinutes(String n) {
    return Intl.message(
      '$n min',
      name: 'trendStepMinutes',
      desc: '',
      args: [n],
    );
  }

  /// `{n} h`
  String trendStepHours(String n) {
    return Intl.message('$n h', name: 'trendStepHours', desc: '', args: [n]);
  }

  /// `{n} d`
  String trendStepDays(String n) {
    return Intl.message('$n d', name: 'trendStepDays', desc: '', args: [n]);
  }

  /// `Start of the window`
  String get trendWindowStart {
    return Intl.message(
      'Start of the window',
      name: 'trendWindowStart',
      desc: '',
      args: [],
    );
  }

  /// `End of the window`
  String get trendWindowEnd {
    return Intl.message(
      'End of the window',
      name: 'trendWindowEnd',
      desc: '',
      args: [],
    );
  }

  /// `Drag to move the window`
  String get trendMoveWindow {
    return Intl.message(
      'Drag to move the window',
      name: 'trendMoveWindow',
      desc: '',
      args: [],
    );
  }

  /// `{what}, {range}. Use the window below to choose the range.`
  String trendDescribe(String what, String range) {
    return Intl.message(
      '$what, $range. Use the window below to choose the range.',
      name: 'trendDescribe',
      desc: '',
      args: [what, range],
    );
  }

  /// `Mon,Tue,Wed,Thu,Fri,Sat,Sun`
  String get trendWeekdays {
    return Intl.message(
      'Mon,Tue,Wed,Thu,Fri,Sat,Sun',
      name: 'trendWeekdays',
      desc: '',
      args: [],
    );
  }

  /// `Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec`
  String get trendMonths {
    return Intl.message(
      'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec',
      name: 'trendMonths',
      desc: '',
      args: [],
    );
  }

  /// `Updates`
  String get updTab {
    return Intl.message('Updates', name: 'updTab', desc: '', args: []);
  }

  /// `Links whose package has a newer version. Every link of a package is updated together, and the broker keeps what it needs to go back.`
  String get updTabNote {
    return Intl.message(
      'Links whose package has a newer version. Every link of a package is updated together, and the broker keeps what it needs to go back.',
      name: 'updTabNote',
      desc: '',
      args: [],
    );
  }

  /// `Update all official…`
  String get updAllOfficial {
    return Intl.message(
      'Update all official…',
      name: 'updAllOfficial',
      desc: '',
      args: [],
    );
  }

  /// `Package`
  String get updColPackage {
    return Intl.message('Package', name: 'updColPackage', desc: '', args: []);
  }

  /// `Version`
  String get updColVersion {
    return Intl.message('Version', name: 'updColVersion', desc: '', args: []);
  }

  /// `Update from file…`
  String get updFromFileRow {
    return Intl.message(
      'Update from file…',
      name: 'updFromFileRow',
      desc: '',
      args: [],
    );
  }

  /// `updated together`
  String get updTogether {
    return Intl.message(
      'updated together',
      name: 'updTogether',
      desc: '',
      args: [],
    );
  }

  /// `Every package is up to date.`
  String get updNothing {
    return Intl.message(
      'Every package is up to date.',
      name: 'updNothing',
      desc: '',
      args: [],
    );
  }

  /// `being checked`
  String get updRowChecking {
    return Intl.message(
      'being checked',
      name: 'updRowChecking',
      desc: '',
      args: [],
    );
  }

  /// `Update {package} {from} → {to}`
  String updTitle(Object package, Object from, Object to) {
    return Intl.message(
      'Update $package $from → $to',
      name: 'updTitle',
      desc: '',
      args: [package, from, to],
    );
  }

  /// `Update {package} {from} from a file`
  String updTitleCustom(Object package, Object from) {
    return Intl.message(
      'Update $package $from from a file',
      name: 'updTitleCustom',
      desc: '',
      args: [package, from],
    );
  }

  /// `official`
  String get updOfficial {
    return Intl.message('official', name: 'updOfficial', desc: '', args: []);
  }

  /// `custom`
  String get updCustom {
    return Intl.message('custom', name: 'updCustom', desc: '', args: []);
  }

  /// `Package of the repository · links that run it: {n}`
  String updSubOfficial(Object n) {
    return Intl.message(
      'Package of the repository · links that run it: $n',
      name: 'updSubOfficial',
      desc: '',
      args: [n],
    );
  }

  /// `Custom package · links that run it: {n}`
  String updSubCustom(Object n) {
    return Intl.message(
      'Custom package · links that run it: $n',
      name: 'updSubCustom',
      desc: '',
      args: [n],
    );
  }

  /// `What is new in {version}`
  String updWhatIsNew(Object version) {
    return Intl.message(
      'What is new in $version',
      name: 'updWhatIsNew',
      desc: '',
      args: [version],
    );
  }

  /// `The repository gives no notes for this version.`
  String get updNoNotes {
    return Intl.message(
      'The repository gives no notes for this version.',
      name: 'updNoNotes',
      desc: '',
      args: [],
    );
  }

  /// `A newer archive`
  String get updFromFile {
    return Intl.message(
      'A newer archive',
      name: 'updFromFile',
      desc: '',
      args: [],
    );
  }

  /// `Bring a zip of the package {package} with a higher version. The broker checks it as any install and updates every link of the package.`
  String updFromFileNote(Object package) {
    return Intl.message(
      'Bring a zip of the package $package with a higher version. The broker checks it as any install and updates every link of the package.',
      name: 'updFromFileNote',
      desc: '',
      args: [package],
    );
  }

  /// `What changes for the broker`
  String get updWhatChanges {
    return Intl.message(
      'What changes for the broker',
      name: 'updWhatChanges',
      desc: '',
      args: [],
    );
  }

  /// `Links that restart ({n}): {links}`
  String updLinksRestart(Object n, Object links) {
    return Intl.message(
      'Links that restart ($n): $links',
      name: 'updLinksRestart',
      desc: '',
      args: [n, links],
    );
  }

  /// `Their values pause while each restarts; their nodes are declared again from the settings they keep.`
  String get updLinksRestartNote {
    return Intl.message(
      'Their values pause while each restarts; their nodes are declared again from the settings they keep.',
      name: 'updLinksRestartNote',
      desc: '',
      args: [],
    );
  }

  /// `Hot start, no restart: {links}`
  String updHotStart(Object links) {
    return Intl.message(
      'Hot start, no restart: $links',
      name: 'updHotStart',
      desc: '',
      args: [links],
    );
  }

  /// `The running app gets the new code in place.`
  String get updHotStartNote {
    return Intl.message(
      'The running app gets the new code in place.',
      name: 'updHotStartNote',
      desc: '',
      args: [],
    );
  }

  /// `Settings and nodes are kept`
  String get updKept {
    return Intl.message(
      'Settings and nodes are kept',
      name: 'updKept',
      desc: '',
      args: [],
    );
  }

  /// `Each link keeps its private data; the new version reads it.`
  String get updKeptNote {
    return Intl.message(
      'Each link keeps its private data; the new version reads it.',
      name: 'updKeptNote',
      desc: '',
      args: [],
    );
  }

  /// `It asks for more rights`
  String get updAsksMore {
    return Intl.message(
      'It asks for more rights',
      name: 'updAsksMore',
      desc: '',
      args: [],
    );
  }

  /// `Rights and network`
  String get updRights {
    return Intl.message(
      'Rights and network',
      name: 'updRights',
      desc: '',
      args: [],
    );
  }

  /// `If the new version asks for more than the links have, the broker installs nothing and lists them here for you to accept.`
  String get updRightsNote {
    return Intl.message(
      'If the new version asks for more than the links have, the broker installs nothing and lists them here for you to accept.',
      name: 'updRightsNote',
      desc: '',
      args: [],
    );
  }

  /// `Store format: same (state {state})`
  String updStateSame(Object state) {
    return Intl.message(
      'Store format: same (state $state)',
      name: 'updStateSame',
      desc: '',
      args: [state],
    );
  }

  /// `The new version reads the store of the installed one.`
  String get updStateSameNote {
    return Intl.message(
      'The new version reads the store of the installed one.',
      name: 'updStateSameNote',
      desc: '',
      args: [],
    );
  }

  /// `It changes the store format (from state {state})`
  String updStateChanges(Object state) {
    return Intl.message(
      'It changes the store format (from state $state)',
      name: 'updStateChanges',
      desc: '',
      args: [state],
    );
  }

  /// `The old version cannot read the new store: a rollback restores the store of the restore point.`
  String get updStateChangesNote {
    return Intl.message(
      'The old version cannot read the new store: a rollback restores the store of the restore point.',
      name: 'updStateChangesNote',
      desc: '',
      args: [],
    );
  }

  /// `Store format: the archive says`
  String get updStateCustom {
    return Intl.message(
      'Store format: the archive says',
      name: 'updStateCustom',
      desc: '',
      args: [],
    );
  }

  /// `If the archive does not read the installed store format, the broker refuses an update without a restore point.`
  String get updStateCustomNote {
    return Intl.message(
      'If the archive does not read the installed store format, the broker refuses an update without a restore point.',
      name: 'updStateCustomNote',
      desc: '',
      args: [],
    );
  }

  /// `Before it starts`
  String get updBefore {
    return Intl.message(
      'Before it starts',
      name: 'updBefore',
      desc: '',
      args: [],
    );
  }

  /// `Save a restore point of each link (settings, secrets, private data)`
  String get updOptPoint {
    return Intl.message(
      'Save a restore point of each link (settings, secrets, private data)',
      name: 'updOptPoint',
      desc: '',
      args: [],
    );
  }

  /// `The store format changes: a rollback needs the restore point`
  String get updOptPointLocked {
    return Intl.message(
      'The store format changes: a rollback needs the restore point',
      name: 'updOptPointLocked',
      desc: '',
      args: [],
    );
  }

  /// `Roll back by itself if a link does not come back with all its nodes in 2 min`
  String get updOptAuto {
    return Intl.message(
      'Roll back by itself if a link does not come back with all its nodes in 2 min',
      name: 'updOptAuto',
      desc: '',
      args: [],
    );
  }

  /// `Accept the new rights it asks for`
  String get updOptAccept {
    return Intl.message(
      'Accept the new rights it asks for',
      name: 'updOptAccept',
      desc: '',
      args: [],
    );
  }

  /// `Then`
  String get updThen {
    return Intl.message('Then', name: 'updThen', desc: '', args: []);
  }

  /// `Needs config on sys/links`
  String get updNeedsConfig {
    return Intl.message(
      'Needs config on sys/links',
      name: 'updNeedsConfig',
      desc: '',
      args: [],
    );
  }

  /// `Update links: {n}`
  String updDo(Object n) {
    return Intl.message('Update links: $n', name: 'updDo', desc: '', args: [n]);
  }

  /// `Choose the archive…`
  String get updChooseArchive {
    return Intl.message(
      'Choose the archive…',
      name: 'updChooseArchive',
      desc: '',
      args: [],
    );
  }

  /// `Updating {package}`
  String updUpdating(Object package) {
    return Intl.message(
      'Updating $package',
      name: 'updUpdating',
      desc: '',
      args: [package],
    );
  }

  /// `Values of its links pause while each restarts.`
  String get updUpdatingSub {
    return Intl.message(
      'Values of its links pause while each restarts.',
      name: 'updUpdatingSub',
      desc: '',
      args: [],
    );
  }

  /// `health check`
  String get updChecking {
    return Intl.message(
      'health check',
      name: 'updChecking',
      desc: '',
      args: [],
    );
  }

  /// `installing`
  String get updWorking {
    return Intl.message('installing', name: 'updWorking', desc: '', args: []);
  }

  /// `Restore points saved`
  String get updStepPoint {
    return Intl.message(
      'Restore points saved',
      name: 'updStepPoint',
      desc: '',
      args: [],
    );
  }

  /// `one for each link`
  String get updStepPointSaved {
    return Intl.message(
      'one for each link',
      name: 'updStepPointSaved',
      desc: '',
      args: [],
    );
  }

  /// `Package fetched, checked and unpacked beside the old version`
  String get updStepPackage {
    return Intl.message(
      'Package fetched, checked and unpacked beside the old version',
      name: 'updStepPackage',
      desc: '',
      args: [],
    );
  }

  /// `Links restarted`
  String get updStepRestart {
    return Intl.message(
      'Links restarted',
      name: 'updStepRestart',
      desc: '',
      args: [],
    );
  }

  /// `Health: every link back with its nodes`
  String get updStepNodes {
    return Intl.message(
      'Health: every link back with its nodes',
      name: 'updStepNodes',
      desc: '',
      args: [],
    );
  }

  /// `declared again: {back} · not back yet or gone: {gone}`
  String updStepNodesCount(Object back, Object gone) {
    return Intl.message(
      'declared again: $back · not back yet or gone: $gone',
      name: 'updStepNodesCount',
      desc: '',
      args: [back, gone],
    );
  }

  /// `You can leave this screen; it goes on.`
  String get updLeave {
    return Intl.message(
      'You can leave this screen; it goes on.',
      name: 'updLeave',
      desc: '',
      args: [],
    );
  }

  /// `Stop and roll back`
  String get updStopAndRollBack {
    return Intl.message(
      'Stop and roll back',
      name: 'updStopAndRollBack',
      desc: '',
      args: [],
    );
  }

  /// `Updating…`
  String get updUpdatingButton {
    return Intl.message(
      'Updating…',
      name: 'updUpdatingButton',
      desc: '',
      args: [],
    );
  }

  /// `Rolled back to {version}`
  String updRolledBackTo(Object version) {
    return Intl.message(
      'Rolled back to $version',
      name: 'updRolledBackTo',
      desc: '',
      args: [version],
    );
  }

  /// `The links run the kept version again.`
  String get updRolledBackNote {
    return Intl.message(
      'The links run the kept version again.',
      name: 'updRolledBackNote',
      desc: '',
      args: [],
    );
  }

  /// `{version} stays, a link did not answer`
  String updFailed(Object version) {
    return Intl.message(
      '$version stays, a link did not answer',
      name: 'updFailed',
      desc: '',
      args: [version],
    );
  }

  /// `The health check ended without an answer from every link.`
  String get updFailedNote {
    return Intl.message(
      'The health check ended without an answer from every link.',
      name: 'updFailedNote',
      desc: '',
      args: [],
    );
  }

  /// `The links run {version}`
  String updRuns(Object version) {
    return Intl.message(
      'The links run $version',
      name: 'updRuns',
      desc: '',
      args: [version],
    );
  }

  /// `{links}: back with all their nodes.`
  String updRunsNote(Object links) {
    return Intl.message(
      '$links: back with all their nodes.',
      name: 'updRunsNote',
      desc: '',
      args: [links],
    );
  }

  /// `{package} update rolled back`
  String updTitleRolledBack(Object package) {
    return Intl.message(
      '$package update rolled back',
      name: 'updTitleRolledBack',
      desc: '',
      args: [package],
    );
  }

  /// `{package} updated`
  String updTitleDone(Object package) {
    return Intl.message(
      '$package updated',
      name: 'updTitleDone',
      desc: '',
      args: [package],
    );
  }

  /// `links: {n}`
  String updLinksCount(Object n) {
    return Intl.message(
      'links: $n',
      name: 'updLinksCount',
      desc: '',
      args: [n],
    );
  }

  /// `rolled back`
  String get updPillRolledBack {
    return Intl.message(
      'rolled back',
      name: 'updPillRolledBack',
      desc: '',
      args: [],
    );
  }

  /// `failed`
  String get updPillFailed {
    return Intl.message('failed', name: 'updPillFailed', desc: '', args: []);
  }

  /// `done`
  String get updPillDone {
    return Intl.message('done', name: 'updPillDone', desc: '', args: []);
  }

  /// `Nodes before and after`
  String get updNodes {
    return Intl.message(
      'Nodes before and after',
      name: 'updNodes',
      desc: '',
      args: [],
    );
  }

  /// `kept`
  String get updKeptTile {
    return Intl.message('kept', name: 'updKeptTile', desc: '', args: []);
  }

  /// `new`
  String get updNewTile {
    return Intl.message('new', name: 'updNewTile', desc: '', args: []);
  }

  /// `gone`
  String get updGoneTile {
    return Intl.message('gone', name: 'updGoneTile', desc: '', args: []);
  }

  /// `Restore points`
  String get updPoints {
    return Intl.message(
      'Restore points',
      name: 'updPoints',
      desc: '',
      args: [],
    );
  }

  /// `No restore point is kept for its links.`
  String get updNoPoints {
    return Intl.message(
      'No restore point is kept for its links.',
      name: 'updNoPoints',
      desc: '',
      args: [],
    );
  }

  /// `{link} · {version} · before update`
  String updPointBeforeUpdate(Object link, Object version) {
    return Intl.message(
      '$link · $version · before update',
      name: 'updPointBeforeUpdate',
      desc: '',
      args: [link, version],
    );
  }

  /// `{link} · before a restore from a backup`
  String updPointBeforeRestore(Object link) {
    return Intl.message(
      '$link · before a restore from a backup',
      name: 'updPointBeforeRestore',
      desc: '',
      args: [link],
    );
  }

  /// `Roll back to {version}…`
  String updRollBackTo(Object version) {
    return Intl.message(
      'Roll back to $version…',
      name: 'updRollBackTo',
      desc: '',
      args: [version],
    );
  }

  /// `{version} stays installed until {when}. A restore point is sealed for this broker and stays on it.`
  String updKeptUntil(Object version, Object when) {
    return Intl.message(
      '$version stays installed until $when. A restore point is sealed for this broker and stays on it.',
      name: 'updKeptUntil',
      desc: '',
      args: [version, when],
    );
  }

  /// `Audit: update_rollback`
  String get updAuditRollback {
    return Intl.message(
      'Audit: update_rollback',
      name: 'updAuditRollback',
      desc: '',
      args: [],
    );
  }

  /// `Audit: package_update, restore_point`
  String get updAuditUpdate {
    return Intl.message(
      'Audit: package_update, restore_point',
      name: 'updAuditUpdate',
      desc: '',
      args: [],
    );
  }

  /// `Close`
  String get updClose {
    return Intl.message('Close', name: 'updClose', desc: '', args: []);
  }

  /// `Open the log`
  String get updOpenLog {
    return Intl.message('Open the log', name: 'updOpenLog', desc: '', args: []);
  }

  /// `Open {link}`
  String updOpenLink(Object link) {
    return Intl.message(
      'Open $link',
      name: 'updOpenLink',
      desc: '',
      args: [link],
    );
  }

  /// `Roll back {package} to {version}?`
  String updRollBackTitle(Object package, Object version) {
    return Intl.message(
      'Roll back $package to $version?',
      name: 'updRollBackTitle',
      desc: '',
      args: [package, version],
    );
  }

  /// `These links stop and start on {version}: {links}. The broker puts their private data back to the restore point of the update when the update changed the store format or did not end well; after an update that ended well they keep the data they have. After it no version is kept: there is no second rollback.`
  String updRollBackNote(Object version, Object links) {
    return Intl.message(
      'These links stop and start on $version: $links. The broker puts their private data back to the restore point of the update when the update changed the store format or did not end well; after an update that ended well they keep the data they have. After it no version is kept: there is no second rollback.',
      name: 'updRollBackNote',
      desc: '',
      args: [version, links],
    );
  }

  /// `Roll back`
  String get updRollBack {
    return Intl.message('Roll back', name: 'updRollBack', desc: '', args: []);
  }

  /// `Update to {version}`
  String actUpdateTo(Object version) {
    return Intl.message(
      'Update to $version',
      name: 'actUpdateTo',
      desc: '',
      args: [version],
    );
  }

  /// `A newer version of its package is in the repository. Review what changes first.`
  String get actUpdateToNote {
    return Intl.message(
      'A newer version of its package is in the repository. Review what changes first.',
      name: 'actUpdateToNote',
      desc: '',
      args: [],
    );
  }

  /// `Versions and restore points`
  String get actVersions {
    return Intl.message(
      'Versions and restore points',
      name: 'actVersions',
      desc: '',
      args: [],
    );
  }

  /// `The last update, the restore points of this link, roll back to the kept version.`
  String get actVersionsNote {
    return Intl.message(
      'The last update, the restore points of this link, roll back to the kept version.',
      name: 'actVersionsNote',
      desc: '',
      args: [],
    );
  }

  /// `Update from file…`
  String get actUpdateFromFile {
    return Intl.message(
      'Update from file…',
      name: 'actUpdateFromFile',
      desc: '',
      args: [],
    );
  }

  /// `A custom package: bring a newer archive of it.`
  String get actUpdateFromFileNote {
    return Intl.message(
      'A custom package: bring a newer archive of it.',
      name: 'actUpdateFromFileNote',
      desc: '',
      args: [],
    );
  }

  /// `Restore points`
  String get factRestorePoints {
    return Intl.message(
      'Restore points',
      name: 'factRestorePoints',
      desc: '',
      args: [],
    );
  }

  /// `This session reaches the site through an upstream broker: its keys and a passphrase-sealed file never travel up. Sign in at the site's own gateway.`
  String get bakSecretsUpstream {
    return Intl.message(
      'This session reaches the site through an upstream broker: its keys and a passphrase-sealed file never travel up. Sign in at the site\'s own gateway.',
      name: 'bakSecretsUpstream',
      desc: '',
      args: [],
    );
  }

  /// `The host does not let secrets leave this broker (backups.export_secrets is false in wyrmd.json5). Secrets are sealed for this site.`
  String get bakSecretsHost {
    return Intl.message(
      'The host does not let secrets leave this broker (backups.export_secrets is false in wyrmd.json5). Secrets are sealed for this site.',
      name: 'bakSecretsHost',
      desc: '',
      args: [],
    );
  }

  /// `Control plane`
  String get bakSecControl {
    return Intl.message(
      'Control plane',
      name: 'bakSecControl',
      desc: '',
      args: [],
    );
  }

  /// `Keys and secrets`
  String get bakSecKeys {
    return Intl.message(
      'Keys and secrets',
      name: 'bakSecKeys',
      desc: '',
      args: [],
    );
  }

  /// `Dataflows`
  String get bakSecDataflows {
    return Intl.message(
      'Dataflows',
      name: 'bakSecDataflows',
      desc: '',
      args: [],
    );
  }

  /// `Broker storage`
  String get bakSecStorage {
    return Intl.message(
      'Broker storage',
      name: 'bakSecStorage',
      desc: '',
      args: [],
    );
  }

  /// `History`
  String get bakSecHistory {
    return Intl.message('History', name: 'bakSecHistory', desc: '', args: []);
  }

  /// `Links`
  String get bakSecLinks {
    return Intl.message('Links', name: 'bakSecLinks', desc: '', args: []);
  }

  /// `Installed packages`
  String get bakSecPackages {
    return Intl.message(
      'Installed packages',
      name: 'bakSecPackages',
      desc: '',
      args: [],
    );
  }

  /// `wyrmd.json5 (read only)`
  String get bakSecConfig {
    return Intl.message(
      'wyrmd.json5 (read only)',
      name: 'bakSecConfig',
      desc: '',
      args: [],
    );
  }

  /// `Settings`
  String get bakSecSettings {
    return Intl.message('Settings', name: 'bakSecSettings', desc: '', args: []);
  }

  /// `Private data`
  String get bakSecData {
    return Intl.message('Private data', name: 'bakSecData', desc: '', args: []);
  }

  /// `Package`
  String get bakSecPackage {
    return Intl.message('Package', name: 'bakSecPackage', desc: '', args: []);
  }

  /// `Registry (links, grants, peers, tokens), users and roles, flow store, audit. Needed to restore anything else.`
  String get bakSecControlNote {
    return Intl.message(
      'Registry (links, grants, peers, tokens), users and roles, flow store, audit. Needed to restore anything else.',
      name: 'bakSecControlNote',
      desc: '',
      args: [],
    );
  }

  /// `Site CA, state and secrets keys, gateway keys, link tokens and sealed secrets. Sealed with the passphrase below.`
  String get bakSecKeysNote {
    return Intl.message(
      'Site CA, state and secrets keys, gateway keys, link tokens and sealed secrets. Sealed with the passphrase below.',
      name: 'bakSecKeysNote',
      desc: '',
      args: [],
    );
  }

  /// `The artifacts of the flow engine; the flows themselves are in the control plane.`
  String get bakSecDataflowsNote {
    return Intl.message(
      'The artifacts of the flow engine; the flows themselves are in the control plane.',
      name: 'bakSecDataflowsNote',
      desc: '',
      args: [],
    );
  }

  /// `The storage tree and its values, with a JSON export for people.`
  String get bakSecStorageNote {
    return Intl.message(
      'The storage tree and its values, with a JSON export for people.',
      name: 'bakSecStorageNote',
      desc: '',
      args: [],
    );
  }

  /// `The recorded days of the historian and its index.`
  String get bakSecHistoryNote {
    return Intl.message(
      'The recorded days of the historian and its index.',
      name: 'bakSecHistoryNote',
      desc: '',
      args: [],
    );
  }

  /// `The recorded rows of its points.`
  String get bakSecLinkHistoryNote {
    return Intl.message(
      'The recorded rows of its points.',
      name: 'bakSecLinkHistoryNote',
      desc: '',
      args: [],
    );
  }

  /// `Per link: its definition, its secrets and its private data, sealed. Their packages go in too.`
  String get bakSecLinksNote {
    return Intl.message(
      'Per link: its definition, its secrets and its private data, sealed. Their packages go in too.',
      name: 'bakSecLinksNote',
      desc: '',
      args: [],
    );
  }

  /// `Every installed package as its files, so a restore needs no repository.`
  String get bakSecPackagesNote {
    return Intl.message(
      'Every installed package as its files, so a restore needs no repository.',
      name: 'bakSecPackagesNote',
      desc: '',
      args: [],
    );
  }

  /// `The configuration with secrets masked, for reference; a restore never writes it.`
  String get bakSecConfigNote {
    return Intl.message(
      'The configuration with secrets masked, for reference; a restore never writes it.',
      name: 'bakSecConfigNote',
      desc: '',
      args: [],
    );
  }

  /// `The link's definition: driver, mode, params, grants.`
  String get bakSecSettingsNote {
    return Intl.message(
      'The link\'s definition: driver, mode, params, grants.',
      name: 'bakSecSettingsNote',
      desc: '',
      args: [],
    );
  }

  /// `Its secrets and its private directory: the runtime edits of a driver (connections, devices, points), a portable app's store.`
  String get bakSecDataNote {
    return Intl.message(
      'Its secrets and its private directory: the runtime edits of a driver (connections, devices, points), a portable app\'s store.',
      name: 'bakSecDataNote',
      desc: '',
      args: [],
    );
  }

  /// `The package it runs, as its files, so it restores where the repository cannot be reached.`
  String get bakSecPackageNote {
    return Intl.message(
      'The package it runs, as its files, so it restores where the repository cannot be reached.',
      name: 'bakSecPackageNote',
      desc: '',
      args: [],
    );
  }

  /// `Last 7 days`
  String get bakLast7 {
    return Intl.message('Last 7 days', name: 'bakLast7', desc: '', args: []);
  }

  /// `Last 30 days`
  String get bakLast30 {
    return Intl.message('Last 30 days', name: 'bakLast30', desc: '', args: []);
  }

  /// `Last 90 days`
  String get bakLast90 {
    return Intl.message('Last 90 days', name: 'bakLast90', desc: '', args: []);
  }

  /// `All`
  String get bakAll {
    return Intl.message('All', name: 'bakAll', desc: '', args: []);
  }

  /// `Give a passphrase of at least 12 characters below: the keys are sealed with it.`
  String get bakKeysNeedPassphrase {
    return Intl.message(
      'Give a passphrase of at least 12 characters below: the keys are sealed with it.',
      name: 'bakKeysNeedPassphrase',
      desc: '',
      args: [],
    );
  }

  /// `The host lists no file-store link for backups (backups.send_links in wyrmd.json5).`
  String get bakNoSendLinks {
    return Intl.message(
      'The host lists no file-store link for backups (backups.send_links in wyrmd.json5).',
      name: 'bakNoSendLinks',
      desc: '',
      args: [],
    );
  }

  /// `A backup with Keys and secrets is never sent: download it at the site's own gateway.`
  String get bakKeysNeverSent {
    return Intl.message(
      'A backup with Keys and secrets is never sent: download it at the site\'s own gateway.',
      name: 'bakKeysNeverSent',
      desc: '',
      args: [],
    );
  }

  /// `Back up {site}`
  String bakTitle(Object site) {
    return Intl.message(
      'Back up $site',
      name: 'bakTitle',
      desc: '',
      args: [site],
    );
  }

  /// `Back up the link {link}`
  String bakTitleLink(Object link) {
    return Intl.message(
      'Back up the link $link',
      name: 'bakTitleLink',
      desc: '',
      args: [link],
    );
  }

  /// `Pick what goes in. One .wyrm-backup file (a zip with a manifest); the broker keeps running while it is made.`
  String get bakSub {
    return Intl.message(
      'Pick what goes in. One .wyrm-backup file (a zip with a manifest); the broker keeps running while it is made.',
      name: 'bakSub',
      desc: '',
      args: [],
    );
  }

  /// `One .wyrm-link file with what {link} needs to come back, here or on another broker.`
  String bakSubLink(Object link) {
    return Intl.message(
      'One .wyrm-link file with what $link needs to come back, here or on another broker.',
      name: 'bakSubLink',
      desc: '',
      args: [link],
    );
  }

  /// `What goes in`
  String get bakWhatGoesIn {
    return Intl.message(
      'What goes in',
      name: 'bakWhatGoesIn',
      desc: '',
      args: [],
    );
  }

  /// `always`
  String get bakTagAlways {
    return Intl.message('always', name: 'bakTagAlways', desc: '', args: []);
  }

  /// `passphrase`
  String get bakTagPassphrase {
    return Intl.message(
      'passphrase',
      name: 'bakTagPassphrase',
      desc: '',
      args: [],
    );
  }

  /// `sealed for this site`
  String get bakTagSite {
    return Intl.message(
      'sealed for this site',
      name: 'bakTagSite',
      desc: '',
      args: [],
    );
  }

  /// `Link`
  String get bakFactLink {
    return Intl.message('Link', name: 'bakFactLink', desc: '', args: []);
  }

  /// `Restore it with Links › Add a link › From backup: on this broker (it replaces the link, after a restore point) or on another one as a new link.`
  String get bakLinkRestoreNote {
    return Intl.message(
      'Restore it with Links › Add a link › From backup: on this broker (it replaces the link, after a restore point) or on another one as a new link.',
      name: 'bakLinkRestoreNote',
      desc: '',
      args: [],
    );
  }

  /// `Passphrase for the keys and secrets`
  String get bakPassphrase {
    return Intl.message(
      'Passphrase for the keys and secrets',
      name: 'bakPassphrase',
      desc: '',
      args: [],
    );
  }

  /// `Passphrase for its private data`
  String get bakPassphraseLink {
    return Intl.message(
      'Passphrase for its private data',
      name: 'bakPassphraseLink',
      desc: '',
      args: [],
    );
  }

  /// `At least {n} characters`
  String bakPassphraseShort(Object n) {
    return Intl.message(
      'At least $n characters',
      name: 'bakPassphraseShort',
      desc: '',
      args: [n],
    );
  }

  /// `Seals Keys and secrets and the links' secrets (Argon2id). Without it the keys stay out and link secrets are sealed for this site. Studio never stores it.`
  String get bakPassphraseNote {
    return Intl.message(
      'Seals Keys and secrets and the links\' secrets (Argon2id). Without it the keys stay out and link secrets are sealed for this site. Studio never stores it.',
      name: 'bakPassphraseNote',
      desc: '',
      args: [],
    );
  }

  /// `With it the file opens on any broker. Without it Private data is sealed for this site and opens only on a broker with its keys. Studio never stores it.`
  String get bakPassphraseLinkNote {
    return Intl.message(
      'With it the file opens on any broker. Without it Private data is sealed for this site and opens only on a broker with its keys. Studio never stores it.',
      name: 'bakPassphraseLinkNote',
      desc: '',
      args: [],
    );
  }

  /// `Where`
  String get bakWhere {
    return Intl.message('Where', name: 'bakWhere', desc: '', args: []);
  }

  /// `This computer`
  String get bakWhereComputer {
    return Intl.message(
      'This computer',
      name: 'bakWhereComputer',
      desc: '',
      args: [],
    );
  }

  /// `File store link…`
  String get bakWhereStore {
    return Intl.message(
      'File store link…',
      name: 'bakWhereStore',
      desc: '',
      args: [],
    );
  }

  /// `Keep on the broker`
  String get bakWhereBroker {
    return Intl.message(
      'Keep on the broker',
      name: 'bakWhereBroker',
      desc: '',
      args: [],
    );
  }

  /// `Downloaded in parts when it is ready; also kept on the broker for {days} days.`
  String bakWhereComputerNote(Object days) {
    return Intl.message(
      'Downloaded in parts when it is ready; also kept on the broker for $days days.',
      name: 'bakWhereComputerNote',
      desc: '',
      args: [days],
    );
  }

  /// `A file-store link (S3, WebDAV, a disk) takes it from the broker without passing through this computer.`
  String get bakWhereStoreNote {
    return Intl.message(
      'A file-store link (S3, WebDAV, a disk) takes it from the broker without passing through this computer.',
      name: 'bakWhereStoreNote',
      desc: '',
      args: [],
    );
  }

  /// `Kept in Backups for {days} days.`
  String bakWhereBrokerNote(Object days) {
    return Intl.message(
      'Kept in Backups for $days days.',
      name: 'bakWhereBrokerNote',
      desc: '',
      args: [days],
    );
  }

  /// `File-store link`
  String get bakSendLink {
    return Intl.message(
      'File-store link',
      name: 'bakSendLink',
      desc: '',
      args: [],
    );
  }

  /// `Connection`
  String get bakSendConnection {
    return Intl.message(
      'Connection',
      name: 'bakSendConnection',
      desc: '',
      args: [],
    );
  }

  /// `This link has no connection.`
  String get bakNoConnections {
    return Intl.message(
      'This link has no connection.',
      name: 'bakNoConnections',
      desc: '',
      args: [],
    );
  }

  /// `Folder (set on the host)`
  String get bakSendFolder {
    return Intl.message(
      'Folder (set on the host)',
      name: 'bakSendFolder',
      desc: '',
      args: [],
    );
  }

  /// `File name or sub-path`
  String get bakSendPath {
    return Intl.message(
      'File name or sub-path',
      name: 'bakSendPath',
      desc: '',
      args: [],
    );
  }

  /// `Empty: the backup's own file name. A sub-folder must exist; a name that exists is refused, never replaced.`
  String get bakSendPathNote {
    return Intl.message(
      'Empty: the backup\'s own file name. A sub-folder must exist; a name that exists is refused, never replaced.',
      name: 'bakSendPathNote',
      desc: '',
      args: [],
    );
  }

  /// `config on sys`
  String get bakNeedsConfig {
    return Intl.message(
      'config on sys',
      name: 'bakNeedsConfig',
      desc: '',
      args: [],
    );
  }

  /// `config on sys/links`
  String get bakNeedsConfigLinks {
    return Intl.message(
      'config on sys/links',
      name: 'bakNeedsConfigLinks',
      desc: '',
      args: [],
    );
  }

  /// `About {size} · {rights}`
  String bakAbout(Object size, Object rights) {
    return Intl.message(
      'About $size · $rights',
      name: 'bakAbout',
      desc: '',
      args: [size, rights],
    );
  }

  /// `Back up`
  String get bakDo {
    return Intl.message('Back up', name: 'bakDo', desc: '', args: []);
  }

  /// `Back up {link}`
  String bakDoLink(Object link) {
    return Intl.message(
      'Back up $link',
      name: 'bakDoLink',
      desc: '',
      args: [link],
    );
  }

  /// `Choose a link and a connection`
  String get bakChooseConnection {
    return Intl.message(
      'Choose a link and a connection',
      name: 'bakChooseConnection',
      desc: '',
      args: [],
    );
  }

  /// `Backup of {what} failed`
  String bakFailedTitle(Object what) {
    return Intl.message(
      'Backup of $what failed',
      name: 'bakFailedTitle',
      desc: '',
      args: [what],
    );
  }

  /// `The broker did not make the backup`
  String get bakFailed {
    return Intl.message(
      'The broker did not make the backup',
      name: 'bakFailed',
      desc: '',
      args: [],
    );
  }

  /// `Backing up {what}`
  String bakProgressTitle(Object what) {
    return Intl.message(
      'Backing up $what',
      name: 'bakProgressTitle',
      desc: '',
      args: [what],
    );
  }

  /// `You can close this; the broker finishes it and keeps it under Backups.`
  String get bakProgressSub {
    return Intl.message(
      'You can close this; the broker finishes it and keeps it under Backups.',
      name: 'bakProgressSub',
      desc: '',
      args: [],
    );
  }

  /// `Each store is read at one consistent moment, inside its own read transaction; the broker keeps running and writing.`
  String get bakConsistent {
    return Intl.message(
      'Each store is read at one consistent moment, inside its own read transaction; the broker keeps running and writing.',
      name: 'bakConsistent',
      desc: '',
      args: [],
    );
  }

  /// `Backing up…`
  String get bakWorking {
    return Intl.message('Backing up…', name: 'bakWorking', desc: '', args: []);
  }

  /// `Backup ready`
  String get bakDoneTitle {
    return Intl.message(
      'Backup ready',
      name: 'bakDoneTitle',
      desc: '',
      args: [],
    );
  }

  /// `Kept on the broker until {when} (Backups).`
  String bakDoneSub(Object when) {
    return Intl.message(
      'Kept on the broker until $when (Backups).',
      name: 'bakDoneSub',
      desc: '',
      args: [when],
    );
  }

  /// `Saved {name}`
  String bakSaved(Object name) {
    return Intl.message(
      'Saved $name',
      name: 'bakSaved',
      desc: '',
      args: [name],
    );
  }

  /// `{size} · sections: {n}`
  String bakSavedNote(Object size, Object n) {
    return Intl.message(
      '$size · sections: $n',
      name: 'bakSavedNote',
      desc: '',
      args: [size, n],
    );
  }

  /// `Contents`
  String get bakFactContents {
    return Intl.message(
      'Contents',
      name: 'bakFactContents',
      desc: '',
      args: [],
    );
  }

  /// `Secrets`
  String get bakFactSealed {
    return Intl.message('Secrets', name: 'bakFactSealed', desc: '', args: []);
  }

  /// `Made by`
  String get bakFactBy {
    return Intl.message('Made by', name: 'bakFactBy', desc: '', args: []);
  }

  /// `Sent to`
  String get bakFactSent {
    return Intl.message('Sent to', name: 'bakFactSent', desc: '', args: []);
  }

  /// `sealed with the passphrase`
  String get bakSealedPassphrase {
    return Intl.message(
      'sealed with the passphrase',
      name: 'bakSealedPassphrase',
      desc: '',
      args: [],
    );
  }

  /// `sealed for {site}: opens only on a broker with its keys`
  String bakSealedBroker(Object site) {
    return Intl.message(
      'sealed for $site: opens only on a broker with its keys',
      name: 'bakSealedBroker',
      desc: '',
      args: [site],
    );
  }

  /// `none in it`
  String get bakSealedNone {
    return Intl.message(
      'none in it',
      name: 'bakSealedNone',
      desc: '',
      args: [],
    );
  }

  /// `It holds the site's keys: whoever has the file and the passphrase is an administrator of {site}.`
  String bakKeysWarning(Object site) {
    return Intl.message(
      'It holds the site\'s keys: whoever has the file and the passphrase is an administrator of $site.',
      name: 'bakKeysWarning',
      desc: '',
      args: [site],
    );
  }

  /// `A backup is as sensitive as the broker's data directory: keep it where only administrators reach it.`
  String get bakSensitive {
    return Intl.message(
      'A backup is as sensitive as the broker\'s data directory: keep it where only administrators reach it.',
      name: 'bakSensitive',
      desc: '',
      args: [],
    );
  }

  /// `Downloading: {done} of {size}`
  String bakDownloading(Object done, Object size) {
    return Intl.message(
      'Downloading: $done of $size',
      name: 'bakDownloading',
      desc: '',
      args: [done, size],
    );
  }

  /// `Saved to {path}; SHA-256 checked.`
  String bakSavedTo(Object path) {
    return Intl.message(
      'Saved to $path; SHA-256 checked.',
      name: 'bakSavedTo',
      desc: '',
      args: [path],
    );
  }

  /// `Sending to {to}`
  String bakSending(Object to) {
    return Intl.message(
      'Sending to $to',
      name: 'bakSending',
      desc: '',
      args: [to],
    );
  }

  /// `Not sent: {error}`
  String bakSendFailed(Object error) {
    return Intl.message(
      'Not sent: $error',
      name: 'bakSendFailed',
      desc: '',
      args: [error],
    );
  }

  /// `Download…`
  String get bakDownload {
    return Intl.message('Download…', name: 'bakDownload', desc: '', args: []);
  }

  /// `Cancel the download`
  String get bakCancelDownload {
    return Intl.message(
      'Cancel the download',
      name: 'bakCancelDownload',
      desc: '',
      args: [],
    );
  }

  /// `Send`
  String get bakSend {
    return Intl.message('Send', name: 'bakSend', desc: '', args: []);
  }

  /// `Show in Backups`
  String get bakShow {
    return Intl.message('Show in Backups', name: 'bakShow', desc: '', args: []);
  }

  /// `Choose the folder for {name}`
  String bakChooseFolder(Object name) {
    return Intl.message(
      'Choose the folder for $name',
      name: 'bakChooseFolder',
      desc: '',
      args: [name],
    );
  }

  /// `Give the passphrase of the backup: the keys are restored only with it.`
  String get rstKeysNeedPassphrase {
    return Intl.message(
      'Give the passphrase of the backup: the keys are restored only with it.',
      name: 'rstKeysNeedPassphrase',
      desc: '',
      args: [],
    );
  }

  /// `This session reaches the site through an upstream broker: the broker refuses a replace from above. Add is open.`
  String get rstReplaceUpstream {
    return Intl.message(
      'This session reaches the site through an upstream broker: the broker refuses a replace from above. Add is open.',
      name: 'rstReplaceUpstream',
      desc: '',
      args: [],
    );
  }

  /// `The check found problems that block a replace.`
  String get rstReplaceProblems {
    return Intl.message(
      'The check found problems that block a replace.',
      name: 'rstReplaceProblems',
      desc: '',
      args: [],
    );
  }

  /// `Restore {site} from a backup`
  String rstTitle(Object site) {
    return Intl.message(
      'Restore $site from a backup',
      name: 'rstTitle',
      desc: '',
      args: [site],
    );
  }

  /// `{site} restarts and applies the backup`
  String rstRestarting(Object site) {
    return Intl.message(
      '$site restarts and applies the backup',
      name: 'rstRestarting',
      desc: '',
      args: [site],
    );
  }

  /// `Studio reconnects by itself.`
  String get rstRestartingNote {
    return Intl.message(
      'Studio reconnects by itself.',
      name: 'rstRestartingNote',
      desc: '',
      args: [],
    );
  }

  /// `A backup of what is replaced was made first (pre-restore, in Backups). The broker stops, and its next start applies the staged sections before any store opens.`
  String get rstRestartingMore {
    return Intl.message(
      'A backup of what is replaced was made first (pre-restore, in Backups). The broker stops, and its next start applies the staged sections before any store opens.',
      name: 'rstRestartingMore',
      desc: '',
      args: [],
    );
  }

  /// `Added; nothing was replaced, no restart`
  String get rstAdded {
    return Intl.message(
      'Added; nothing was replaced, no restart',
      name: 'rstAdded',
      desc: '',
      args: [],
    );
  }

  /// `Sections`
  String get rstFactSections {
    return Intl.message(
      'Sections',
      name: 'rstFactSections',
      desc: '',
      args: [],
    );
  }

  /// `Pick a .wyrm-backup file.`
  String get rstPick {
    return Intl.message(
      'Pick a .wyrm-backup file.',
      name: 'rstPick',
      desc: '',
      args: [],
    );
  }

  /// `The file goes to the broker in parts. Nothing changes until you have seen what the broker found in it.`
  String get rstPickNote {
    return Intl.message(
      'The file goes to the broker in parts. Nothing changes until you have seen what the broker found in it.',
      name: 'rstPickNote',
      desc: '',
      args: [],
    );
  }

  /// `Uploading: {done} of {size}`
  String rstUploading(Object done, Object size) {
    return Intl.message(
      'Uploading: $done of $size',
      name: 'rstUploading',
      desc: '',
      args: [done, size],
    );
  }

  /// `The file is on the broker`
  String get rstUploaded {
    return Intl.message(
      'The file is on the broker',
      name: 'rstUploaded',
      desc: '',
      args: [],
    );
  }

  /// `Nothing was changed yet. The check reads its manifest and compares it with this broker.`
  String get rstUploadedNote {
    return Intl.message(
      'Nothing was changed yet. The check reads its manifest and compares it with this broker.',
      name: 'rstUploadedNote',
      desc: '',
      args: [],
    );
  }

  /// `Passphrase of the backup`
  String get rstPassphrase {
    return Intl.message(
      'Passphrase of the backup',
      name: 'rstPassphrase',
      desc: '',
      args: [],
    );
  }

  /// `Only for a backup sealed with one. Studio never stores it.`
  String get rstPassphraseNote {
    return Intl.message(
      'Only for a backup sealed with one. Studio never stores it.',
      name: 'rstPassphraseNote',
      desc: '',
      args: [],
    );
  }

  /// `Sent again with the restore. Studio never stores it.`
  String get rstPassphraseKept {
    return Intl.message(
      'Sent again with the restore. Studio never stores it.',
      name: 'rstPassphraseKept',
      desc: '',
      args: [],
    );
  }

  /// `Choose the file…`
  String get rstChoose {
    return Intl.message(
      'Choose the file…',
      name: 'rstChoose',
      desc: '',
      args: [],
    );
  }

  /// `Check the file`
  String get rstCheck {
    return Intl.message('Check the file', name: 'rstCheck', desc: '', args: []);
  }

  /// `Uploading…`
  String get rstUploadingButton {
    return Intl.message(
      'Uploading…',
      name: 'rstUploadingButton',
      desc: '',
      args: [],
    );
  }

  /// `tick what to bring back`
  String get rstTick {
    return Intl.message(
      'tick what to bring back',
      name: 'rstTick',
      desc: '',
      args: [],
    );
  }

  /// `Checked`
  String get rstChecked {
    return Intl.message('Checked', name: 'rstChecked', desc: '', args: []);
  }

  /// `From {site} · wyrmd {broker}`
  String rstFile(Object site, Object broker) {
    return Intl.message(
      'From $site · wyrmd $broker',
      name: 'rstFile',
      desc: '',
      args: [site, broker],
    );
  }

  /// `Made {when} · sections: {n} · secrets: {sealed}`
  String rstFileNote(Object when, Object n, Object sealed) {
    return Intl.message(
      'Made $when · sections: $n · secrets: $sealed',
      name: 'rstFileNote',
      desc: '',
      args: [when, n, sealed],
    );
  }

  /// `A backup of another site: {site}`
  String rstOtherSite(Object site) {
    return Intl.message(
      'A backup of another site: $site',
      name: 'rstOtherSite',
      desc: '',
      args: [site],
    );
  }

  /// `The broker refuses a backup of another site name. Set site in wyrmd.json5 to the backup's first.`
  String get rstOtherSiteNote {
    return Intl.message(
      'The broker refuses a backup of another site name. Set site in wyrmd.json5 to the backup\'s first.',
      name: 'rstOtherSiteNote',
      desc: '',
      args: [],
    );
  }

  /// `The same keys`
  String get rstKeysSame {
    return Intl.message(
      'The same keys',
      name: 'rstKeysSame',
      desc: '',
      args: [],
    );
  }

  /// `Every key file of the backup is this broker's; tokens and certificates stay valid.`
  String get rstKeysSameNote {
    return Intl.message(
      'Every key file of the backup is this broker\'s; tokens and certificates stay valid.',
      name: 'rstKeysSameNote',
      desc: '',
      args: [],
    );
  }

  /// `This site's CA, other key files`
  String get rstKeysDiffer {
    return Intl.message(
      'This site\'s CA, other key files',
      name: 'rstKeysDiffer',
      desc: '',
      args: [],
    );
  }

  /// `Another CA`
  String get rstKeysOther {
    return Intl.message('Another CA', name: 'rstKeysOther', desc: '', args: []);
  }

  /// `Restoring the keys changes the site's identity: links, operators and peer brokers enrol again.`
  String get rstKeysOtherNote {
    return Intl.message(
      'Restoring the keys changes the site\'s identity: links, operators and peer brokers enrol again.',
      name: 'rstKeysOtherNote',
      desc: '',
      args: [],
    );
  }

  /// `No keys in the file`
  String get rstKeysNone {
    return Intl.message(
      'No keys in the file',
      name: 'rstKeysNone',
      desc: '',
      args: [],
    );
  }

  /// `This broker keeps its own keys.`
  String get rstKeysNoneNote {
    return Intl.message(
      'This broker keeps its own keys.',
      name: 'rstKeysNoneNote',
      desc: '',
      args: [],
    );
  }

  /// `The control plane does not open with this broker's keys`
  String get rstControlOther {
    return Intl.message(
      'The control plane does not open with this broker\'s keys',
      name: 'rstControlOther',
      desc: '',
      args: [],
    );
  }

  /// `It is restored only together with Keys and secrets.`
  String get rstControlOtherNote {
    return Intl.message(
      'It is restored only together with Keys and secrets.',
      name: 'rstControlOtherNote',
      desc: '',
      args: [],
    );
  }

  /// `Store formats differ (backup → here)`
  String get rstSchemas {
    return Intl.message(
      'Store formats differ (backup → here)',
      name: 'rstSchemas',
      desc: '',
      args: [],
    );
  }

  /// `Links: {fresh} new, {exists} exist here`
  String rstLinks(Object fresh, Object exists) {
    return Intl.message(
      'Links: $fresh new, $exists exist here',
      name: 'rstLinks',
      desc: '',
      args: [fresh, exists],
    );
  }

  /// `In the file`
  String get rstInTheFile {
    return Intl.message(
      'In the file',
      name: 'rstInTheFile',
      desc: '',
      args: [],
    );
  }

  /// `A copy for reference; a restore never writes it.`
  String get rstConfigNever {
    return Intl.message(
      'A copy for reference; a restore never writes it.',
      name: 'rstConfigNever',
      desc: '',
      args: [],
    );
  }

  /// `Add takes links and storage only.`
  String get rstNotInAdd {
    return Intl.message(
      'Add takes links and storage only.',
      name: 'rstNotInAdd',
      desc: '',
      args: [],
    );
  }

  /// `How`
  String get rstHow {
    return Intl.message('How', name: 'rstHow', desc: '', args: []);
  }

  /// `Replace what is ticked and restart the broker once (a backup of what it replaces is made first)`
  String get rstReplace {
    return Intl.message(
      'Replace what is ticked and restart the broker once (a backup of what it replaces is made first)',
      name: 'rstReplace',
      desc: '',
      args: [],
    );
  }

  /// `Add only: links and storage nodes that do not exist yet; nothing replaced, no restart`
  String get rstAdd {
    return Intl.message(
      'Add only: links and storage nodes that do not exist yet; nothing replaced, no restart',
      name: 'rstAdd',
      desc: '',
      args: [],
    );
  }

  /// `Replace the site's keys: {files}`
  String rstReplaceKeys(Object files) {
    return Intl.message(
      'Replace the site\'s keys: $files',
      name: 'rstReplaceKeys',
      desc: '',
      args: [files],
    );
  }

  /// `Replace the site's keys with another CA: links, operators and peer brokers enrol again`
  String get rstReplaceKeysOther {
    return Intl.message(
      'Replace the site\'s keys with another CA: links, operators and peer brokers enrol again',
      name: 'rstReplaceKeysOther',
      desc: '',
      args: [],
    );
  }

  /// `Accept the rights and network the packages of the file ask for`
  String get rstAcceptPackages {
    return Intl.message(
      'Accept the rights and network the packages of the file ask for',
      name: 'rstAcceptPackages',
      desc: '',
      args: [],
    );
  }

  /// `Accept the rights and network the links of the file ask for`
  String get rstAcceptLinks {
    return Intl.message(
      'Accept the rights and network the links of the file ask for',
      name: 'rstAcceptLinks',
      desc: '',
      args: [],
    );
  }

  /// `A backup of what it replaces is made first`
  String get rstReplaceNote {
    return Intl.message(
      'A backup of what it replaces is made first',
      name: 'rstReplaceNote',
      desc: '',
      args: [],
    );
  }

  /// `Nothing is replaced`
  String get rstAddNote {
    return Intl.message(
      'Nothing is replaced',
      name: 'rstAddNote',
      desc: '',
      args: [],
    );
  }

  /// `Restore and restart`
  String get rstDoReplace {
    return Intl.message(
      'Restore and restart',
      name: 'rstDoReplace',
      desc: '',
      args: [],
    );
  }

  /// `Add`
  String get rstDoAdd {
    return Intl.message('Add', name: 'rstDoAdd', desc: '', args: []);
  }

  /// `Tick a section this mode takes`
  String get rstNothingTicked {
    return Intl.message(
      'Tick a section this mode takes',
      name: 'rstNothingTicked',
      desc: '',
      args: [],
    );
  }

  /// `Tick Replace the site's keys first`
  String get rstConfirmKeys {
    return Intl.message(
      'Tick Replace the site\'s keys first',
      name: 'rstConfirmKeys',
      desc: '',
      args: [],
    );
  }

  /// `Backups`
  String get bakCard {
    return Intl.message('Backups', name: 'bakCard', desc: '', args: []);
  }

  /// `Made while the broker runs, kept on it for {days} days. Download one or send it to a file store.`
  String bakCardNote(Object days) {
    return Intl.message(
      'Made while the broker runs, kept on it for $days days. Download one or send it to a file store.',
      name: 'bakCardNote',
      desc: '',
      args: [days],
    );
  }

  /// `This broker has no backups from Studio (it runs a wyrmd before ADR 0048). Use the commands below.`
  String get bakCardOld {
    return Intl.message(
      'This broker has no backups from Studio (it runs a wyrmd before ADR 0048). Use the commands below.',
      name: 'bakCardOld',
      desc: '',
      args: [],
    );
  }

  /// `No backup is kept on the broker.`
  String get bakCardEmpty {
    return Intl.message(
      'No backup is kept on the broker.',
      name: 'bakCardEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Restore…`
  String get bakRestore {
    return Intl.message('Restore…', name: 'bakRestore', desc: '', args: []);
  }

  /// `Back up…`
  String get bakBackUp {
    return Intl.message('Back up…', name: 'bakBackUp', desc: '', args: []);
  }

  /// `being made · {percent} %`
  String bakRowRunning(Object percent) {
    return Intl.message(
      'being made · $percent %',
      name: 'bakRowRunning',
      desc: '',
      args: [percent],
    );
  }

  /// `failed`
  String get bakRowFailed {
    return Intl.message('failed', name: 'bakRowFailed', desc: '', args: []);
  }

  /// `sending · {percent} %`
  String bakRowSending(Object percent) {
    return Intl.message(
      'sending · $percent %',
      name: 'bakRowSending',
      desc: '',
      args: [percent],
    );
  }

  /// `broker`
  String get bakKindFull {
    return Intl.message('broker', name: 'bakKindFull', desc: '', args: []);
  }

  /// `link {link}`
  String bakKindLink(Object link) {
    return Intl.message(
      'link $link',
      name: 'bakKindLink',
      desc: '',
      args: [link],
    );
  }

  /// `before an update`
  String get bakKindPreUpdate {
    return Intl.message(
      'before an update',
      name: 'bakKindPreUpdate',
      desc: '',
      args: [],
    );
  }

  /// `before a restore`
  String get bakKindPreRestore {
    return Intl.message(
      'before a restore',
      name: 'bakKindPreRestore',
      desc: '',
      args: [],
    );
  }

  /// `Open`
  String get bakOpen {
    return Intl.message('Open', name: 'bakOpen', desc: '', args: []);
  }

  /// `Remove {name}?`
  String bakRemoveTitle(Object name) {
    return Intl.message(
      'Remove $name?',
      name: 'bakRemoveTitle',
      desc: '',
      args: [name],
    );
  }

  /// `The file is deleted from the broker. A copy you downloaded or sent stays.`
  String get bakRemoveNote {
    return Intl.message(
      'The file is deleted from the broker. A copy you downloaded or sent stays.',
      name: 'bakRemoveNote',
      desc: '',
      args: [],
    );
  }

  /// `When the broker does not start`
  String get bakOffline {
    return Intl.message(
      'When the broker does not start',
      name: 'bakOffline',
      desc: '',
      args: [],
    );
  }

  /// `Back up…`
  String get actBackUp {
    return Intl.message('Back up…', name: 'actBackUp', desc: '', args: []);
  }

  /// `One file with its settings, private data and package; restore it here or on another broker.`
  String get actBackUpNote {
    return Intl.message(
      'One file with its settings, private data and package; restore it here or on another broker.',
      name: 'actBackUpNote',
      desc: '',
      args: [],
    );
  }

  /// `Backup`
  String get groupBackup {
    return Intl.message('Backup', name: 'groupBackup', desc: '', args: []);
  }

  /// `Remove it from the broker`
  String get bakRemoveRow {
    return Intl.message(
      'Remove it from the broker',
      name: 'bakRemoveRow',
      desc: '',
      args: [],
    );
  }

  /// `From a backup`
  String get fromBackup {
    return Intl.message(
      'From a backup',
      name: 'fromBackup',
      desc: '',
      args: [],
    );
  }

  /// `A link backup (.wyrm-link) made by Back up… on a link: its settings, private data and package. It comes back under its own id or a new one.`
  String get fromBackupNote {
    return Intl.message(
      'A link backup (.wyrm-link) made by Back up… on a link: its settings, private data and package. It comes back under its own id or a new one.',
      name: 'fromBackupNote',
      desc: '',
      args: [],
    );
  }

  /// `Choose a .wyrm-link file`
  String get chooseBackupFile {
    return Intl.message(
      'Choose a .wyrm-link file',
      name: 'chooseBackupFile',
      desc: '',
      args: [],
    );
  }

  /// `A link {id} exists on this broker: it is replaced in place (same driver and mode), and a restore point of it is taken first.`
  String backupReplaces(Object id) {
    return Intl.message(
      'A link $id exists on this broker: it is replaced in place (same driver and mode), and a restore point of it is taken first.',
      name: 'backupReplaces',
      desc: '',
      args: [id],
    );
  }

  /// `Passphrase of the backup`
  String get backupPassphrase {
    return Intl.message(
      'Passphrase of the backup',
      name: 'backupPassphrase',
      desc: '',
      args: [],
    );
  }

  /// `Only for a backup sealed with one. One sealed for its site needs none and opens only on a broker with that site's keys. Studio never stores it.`
  String get backupPassphraseNote {
    return Intl.message(
      'Only for a backup sealed with one. One sealed for its site needs none and opens only on a broker with that site\'s keys. Studio never stores it.',
      name: 'backupPassphraseNote',
      desc: '',
      args: [],
    );
  }

  /// `Needed when the link has grants or a network allowlist: without it the broker lists them and installs nothing. Its token, certificate and requester key are new.`
  String get backupRightsNote {
    return Intl.message(
      'Needed when the link has grants or a network allowlist: without it the broker lists them and installs nothing. Its token, certificate and requester key are new.',
      name: 'backupRightsNote',
      desc: '',
      args: [],
    );
  }

  /// `the broker asks if needed`
  String get backupRightsAsk {
    return Intl.message(
      'the broker asks if needed',
      name: 'backupRightsAsk',
      desc: '',
      args: [],
    );
  }

  /// `A link backup is one file with what a link needs to come back. Studio reads its manifest here; the broker checks all of it as a new link.`
  String get whyBringBackup {
    return Intl.message(
      'A link backup is one file with what a link needs to come back. Studio reads its manifest here; the broker checks all of it as a new link.',
      name: 'whyBringBackup',
      desc: '',
      args: [],
    );
  }

  /// `Keep its id to restore it, or give a new one to make a second link. The mode is the one it ran in.`
  String get whyRunBackup {
    return Intl.message(
      'Keep its id to restore it, or give a new one to make a second link. The mode is the one it ran in.',
      name: 'whyRunBackup',
      desc: '',
      args: [],
    );
  }

  /// `Update {site} to wyrmd {version}`
  String bupTitle(Object site, Object version) {
    return Intl.message(
      'Update $site to wyrmd $version',
      name: 'bupTitle',
      desc: '',
      args: [site, version],
    );
  }

  /// `From the release channel of this broker · the broker restarts once`
  String get bupSub {
    return Intl.message(
      'From the release channel of this broker · the broker restarts once',
      name: 'bupSub',
      desc: '',
      args: [],
    );
  }

  /// `Checked before anything changes`
  String get bupChecked {
    return Intl.message(
      'Checked before anything changes',
      name: 'bupChecked',
      desc: '',
      args: [],
    );
  }

  /// `The release is signed`
  String get bupCheckSigned {
    return Intl.message(
      'The release is signed',
      name: 'bupCheckSigned',
      desc: '',
      args: [],
    );
  }

  /// `The Ed25519 signature of the release key and the SHA-256 of the archive.`
  String get bupCheckSignedNote {
    return Intl.message(
      'The Ed25519 signature of the release key and the SHA-256 of the archive.',
      name: 'bupCheckSignedNote',
      desc: '',
      args: [],
    );
  }

  /// `The new binary accepts this configuration`
  String get bupCheckConfig {
    return Intl.message(
      'The new binary accepts this configuration',
      name: 'bupCheckConfig',
      desc: '',
      args: [],
    );
  }

  /// `The new wyrmd runs its check on the configuration of this broker.`
  String get bupCheckConfigNote {
    return Intl.message(
      'The new wyrmd runs its check on the configuration of this broker.',
      name: 'bupCheckConfigNote',
      desc: '',
      args: [],
    );
  }

  /// `Room for it`
  String get bupCheckRoom {
    return Intl.message(
      'Room for it',
      name: 'bupCheckRoom',
      desc: '',
      args: [],
    );
  }

  /// `The binary and the pre-update backup fit the disk.`
  String get bupCheckRoomNote {
    return Intl.message(
      'The binary and the pre-update backup fit the disk.',
      name: 'bupCheckRoomNote',
      desc: '',
      args: [],
    );
  }

  /// `A store format may move`
  String get bupCheckSchema {
    return Intl.message(
      'A store format may move',
      name: 'bupCheckSchema',
      desc: '',
      args: [],
    );
  }

  /// `If the new version writes a newer SCHEMA, {version} cannot read it afterwards: a rollback restores the pre-update backup of the control plane, so changes made after the update are lost on rollback.`
  String bupCheckSchemaNote(Object version) {
    return Intl.message(
      'If the new version writes a newer SCHEMA, $version cannot read it afterwards: a rollback restores the pre-update backup of the control plane, so changes made after the update are lost on rollback.',
      name: 'bupCheckSchemaNote',
      desc: '',
      args: [version],
    );
  }

  /// `A standby is updated first`
  String get bupCheckStandby {
    return Intl.message(
      'A standby is updated first',
      name: 'bupCheckStandby',
      desc: '',
      args: [],
    );
  }

  /// `When a standby follows this broker and the release changes the replication protocol, the broker refuses until the standby runs the new version.`
  String get bupCheckStandbyNote {
    return Intl.message(
      'When a standby follows this broker and the release changes the replication protocol, the broker refuses until the standby runs the new version.',
      name: 'bupCheckStandbyNote',
      desc: '',
      args: [],
    );
  }

  /// `How it goes`
  String get bupHow {
    return Intl.message('How it goes', name: 'bupHow', desc: '', args: []);
  }

  /// `Pre-update backup of the control plane, secrets sealed (kept until the update is confirmed).`
  String get bupStep1 {
    return Intl.message(
      'Pre-update backup of the control plane, secrets sealed (kept until the update is confirmed).',
      name: 'bupStep1',
      desc: '',
      args: [],
    );
  }

  /// `The new binary is staged beside the current one; {version} stays on disk.`
  String bupStep2(Object version) {
    return Intl.message(
      'The new binary is staged beside the current one; $version stays on disk.',
      name: 'bupStep2',
      desc: '',
      args: [version],
    );
  }

  /// `The broker stops cleanly and the service manager starts {version} (about 5–15 s without the broker).`
  String bupStep3(Object version) {
    return Intl.message(
      'The broker stops cleanly and the service manager starts $version (about 5–15 s without the broker).',
      name: 'bupStep3',
      desc: '',
      args: [version],
    );
  }

  /// `{version} runs on trial: it must have the router, the gateway and its links back within 3 min.`
  String bupStep4(Object version) {
    return Intl.message(
      '$version runs on trial: it must have the router, the gateway and its links back within 3 min.',
      name: 'bupStep4',
      desc: '',
      args: [version],
    );
  }

  /// `Then it confirms itself. If it does not, the next start goes back to {version} with the backup of step 1.`
  String bupStep5(Object version) {
    return Intl.message(
      'Then it confirms itself. If it does not, the next start goes back to $version with the backup of step 1.',
      name: 'bupStep5',
      desc: '',
      args: [version],
    );
  }

  /// `Type {site} to confirm`
  String bupType(Object site) {
    return Intl.message(
      'Type $site to confirm',
      name: 'bupType',
      desc: '',
      args: [site],
    );
  }

  /// `Needs config on sys · audited`
  String get bupNeedsConfig {
    return Intl.message(
      'Needs config on sys · audited',
      name: 'bupNeedsConfig',
      desc: '',
      args: [],
    );
  }

  /// `Back up and update`
  String get bupDo {
    return Intl.message(
      'Back up and update',
      name: 'bupDo',
      desc: '',
      args: [],
    );
  }

  /// `Updating {site}`
  String bupUpdating(Object site) {
    return Intl.message(
      'Updating $site',
      name: 'bupUpdating',
      desc: '',
      args: [site],
    );
  }

  /// `restarting`
  String get bupPillRestarting {
    return Intl.message(
      'restarting',
      name: 'bupPillRestarting',
      desc: '',
      args: [],
    );
  }

  /// `This screen reconnects by itself.`
  String get bupUpdatingSub {
    return Intl.message(
      'This screen reconnects by itself.',
      name: 'bupUpdatingSub',
      desc: '',
      args: [],
    );
  }

  /// `{site} is restarting on {version}`
  String bupRestarting(Object site, Object version) {
    return Intl.message(
      '$site is restarting on $version',
      name: 'bupRestarting',
      desc: '',
      args: [site, version],
    );
  }

  /// `The gateway is back; the new version is on trial.`
  String get bupOnTrial {
    return Intl.message(
      'The gateway is back; the new version is on trial.',
      name: 'bupOnTrial',
      desc: '',
      args: [],
    );
  }

  /// `Studio lost the gateway and tries again by itself · {time}`
  String bupLost(Object time) {
    return Intl.message(
      'Studio lost the gateway and tries again by itself · $time',
      name: 'bupLost',
      desc: '',
      args: [time],
    );
  }

  /// `Pre-update backup`
  String get bupDonePreBackup {
    return Intl.message(
      'Pre-update backup',
      name: 'bupDonePreBackup',
      desc: '',
      args: [],
    );
  }

  /// `{version} staged`
  String bupDoneStaged(Object version) {
    return Intl.message(
      '$version staged',
      name: 'bupDoneStaged',
      desc: '',
      args: [version],
    );
  }

  /// `Stopped on {from}, started on {to}`
  String bupDoneRestart(Object from, Object to) {
    return Intl.message(
      'Stopped on $from, started on $to',
      name: 'bupDoneRestart',
      desc: '',
      args: [from, to],
    );
  }

  /// `Router, gateway, links back`
  String get bupDoneBack {
    return Intl.message(
      'Router, gateway, links back',
      name: 'bupDoneBack',
      desc: '',
      args: [],
    );
  }

  /// `Confirmed`
  String get bupDoneConfirmed {
    return Intl.message(
      'Confirmed',
      name: 'bupDoneConfirmed',
      desc: '',
      args: [],
    );
  }

  /// `Links on other machines walk to their next endpoint or wait; devices keep their last outputs. Values recorded by links during the restart are not lost if the link buffers them.`
  String get bupMeanwhile {
    return Intl.message(
      'Links on other machines walk to their next endpoint or wait; devices keep their last outputs. Values recorded by links during the restart are not lost if the link buffers them.',
      name: 'bupMeanwhile',
      desc: '',
      args: [],
    );
  }

  /// `Closing Studio does not stop it.`
  String get bupClosing {
    return Intl.message(
      'Closing Studio does not stop it.',
      name: 'bupClosing',
      desc: '',
      args: [],
    );
  }

  /// `Hide`
  String get bupHide {
    return Intl.message('Hide', name: 'bupHide', desc: '', args: []);
  }

  /// `Reconnecting…`
  String get bupReconnecting {
    return Intl.message(
      'Reconnecting…',
      name: 'bupReconnecting',
      desc: '',
      args: [],
    );
  }

  /// `{site} updated`
  String bupUpdated(Object site) {
    return Intl.message(
      '$site updated',
      name: 'bupUpdated',
      desc: '',
      args: [site],
    );
  }

  /// `{site} runs {version}`
  String bupRuns(Object site, Object version) {
    return Intl.message(
      '$site runs $version',
      name: 'bupRuns',
      desc: '',
      args: [site, version],
    );
  }

  /// `The update is confirmed; {version} and the pre-update backup are kept for a rollback.`
  String bupRunsNote(Object version) {
    return Intl.message(
      'The update is confirmed; $version and the pre-update backup are kept for a rollback.',
      name: 'bupRunsNote',
      desc: '',
      args: [version],
    );
  }

  /// `Version`
  String get bupFactVersion {
    return Intl.message('Version', name: 'bupFactVersion', desc: '', args: []);
  }

  /// `Without the broker`
  String get bupFactDown {
    return Intl.message(
      'Without the broker',
      name: 'bupFactDown',
      desc: '',
      args: [],
    );
  }

  /// `{n} s`
  String bupSeconds(Object n) {
    return Intl.message('$n s', name: 'bupSeconds', desc: '', args: [n]);
  }

  /// `Links back`
  String get bupFactLinks {
    return Intl.message('Links back', name: 'bupFactLinks', desc: '', args: []);
  }

  /// `{back} of {all} in {seconds} s`
  String bupLinksBack(Object back, Object all, Object seconds) {
    return Intl.message(
      '$back of $all in $seconds s',
      name: 'bupLinksBack',
      desc: '',
      args: [back, all, seconds],
    );
  }

  /// `Roll back`
  String get bupFactRollBack {
    return Intl.message(
      'Roll back',
      name: 'bupFactRollBack',
      desc: '',
      args: [],
    );
  }

  /// `possible until {when}`
  String bupRollBackUntil(Object when) {
    return Intl.message(
      'possible until $when',
      name: 'bupRollBackUntil',
      desc: '',
      args: [when],
    );
  }

  /// `Audit`
  String get bupFactAudit {
    return Intl.message('Audit', name: 'bupFactAudit', desc: '', args: []);
  }

  /// `Update rolled back`
  String get bupRolledBack {
    return Intl.message(
      'Update rolled back',
      name: 'bupRolledBack',
      desc: '',
      args: [],
    );
  }

  /// `Back on {version}`
  String bupBackOn(Object version) {
    return Intl.message(
      'Back on $version',
      name: 'bupBackOn',
      desc: '',
      args: [version],
    );
  }

  /// `{tried} did not pass its trial start. The next start went back to {version} and restored the control plane from the pre-update backup.`
  String bupBackOnNote(Object tried, Object version) {
    return Intl.message(
      '$tried did not pass its trial start. The next start went back to $version and restored the control plane from the pre-update backup.',
      name: 'bupBackOnNote',
      desc: '',
      args: [tried, version],
    );
  }

  /// `Tried`
  String get bupFactTried {
    return Intl.message('Tried', name: 'bupFactTried', desc: '', args: []);
  }

  /// `Reason`
  String get bupFactReason {
    return Intl.message('Reason', name: 'bupFactReason', desc: '', args: []);
  }

  /// `Now`
  String get bupFactNow {
    return Intl.message('Now', name: 'bupFactNow', desc: '', args: []);
  }

  /// `Open the log of {version}`
  String bupOpenLog(Object version) {
    return Intl.message(
      'Open the log of $version',
      name: 'bupOpenLog',
      desc: '',
      args: [version],
    );
  }

  /// `container`
  String get bupPillContainer {
    return Intl.message(
      'container',
      name: 'bupPillContainer',
      desc: '',
      args: [],
    );
  }

  /// `This broker does not replace itself (updates.mode: "external": a container or a distribution package). The image is changed where the container is defined, and the data volume carries the state across.`
  String get bupExternal {
    return Intl.message(
      'This broker does not replace itself (updates.mode: "external": a container or a distribution package). The image is changed where the container is defined, and the data volume carries the state across.',
      name: 'bupExternal',
      desc: '',
      args: [],
    );
  }

  /// `Studio still makes the backup for you before you do it.`
  String get bupExternalBackup {
    return Intl.message(
      'Studio still makes the backup for you before you do it.',
      name: 'bupExternalBackup',
      desc: '',
      args: [],
    );
  }

  /// `Make the backup`
  String get bupMakeBackup {
    return Intl.message(
      'Make the backup',
      name: 'bupMakeBackup',
      desc: '',
      args: [],
    );
  }

  /// `Roll back {site} to {version}?`
  String bupRollBackTitle(Object site, Object version) {
    return Intl.message(
      'Roll back $site to $version?',
      name: 'bupRollBackTitle',
      desc: '',
      args: [site, version],
    );
  }

  /// `The broker restarts on the version before and restores the pre-update backup of its control plane. Changes made after the update are lost.`
  String get bupRollBackNote {
    return Intl.message(
      'The broker restarts on the version before and restores the pre-update backup of its control plane. Changes made after the update are lost.',
      name: 'bupRollBackNote',
      desc: '',
      args: [],
    );
  }

  /// `Broker version`
  String get bupCard {
    return Intl.message('Broker version', name: 'bupCard', desc: '', args: []);
  }

  /// `{version} · {latest} is available`
  String bupCardAvailable(Object version, Object latest) {
    return Intl.message(
      '$version · $latest is available',
      name: 'bupCardAvailable',
      desc: '',
      args: [version, latest],
    );
  }

  /// `{version} · up to date`
  String bupCardCurrent(Object version) {
    return Intl.message(
      '$version · up to date',
      name: 'bupCardCurrent',
      desc: '',
      args: [version],
    );
  }

  /// `{version} is on trial`
  String bupCardTrial(Object version) {
    return Intl.message(
      '$version is on trial',
      name: 'bupCardTrial',
      desc: '',
      args: [version],
    );
  }

  /// `{version} · the update was rolled back`
  String bupCardRolledBack(Object version) {
    return Intl.message(
      '$version · the update was rolled back',
      name: 'bupCardRolledBack',
      desc: '',
      args: [version],
    );
  }

  /// `Update…`
  String get bupUpdate {
    return Intl.message('Update…', name: 'bupUpdate', desc: '', args: []);
  }

  /// `Show…`
  String get bupShow {
    return Intl.message('Show…', name: 'bupShow', desc: '', args: []);
  }

  /// `The offline way, for a broker that does not start or a host without Studio: a copy of data_dir made on the host. The steps, ready to copy:`
  String get bakOfflineNote {
    return Intl.message(
      'The offline way, for a broker that does not start or a host without Studio: a copy of data_dir made on the host. The steps, ready to copy:',
      name: 'bakOfflineNote',
      desc: '',
      args: [],
    );
  }

  /// `The backup was applied; the broker runs on it`
  String get rstApplied {
    return Intl.message(
      'The backup was applied; the broker runs on it',
      name: 'rstApplied',
      desc: '',
      args: [],
    );
  }

  /// `The restore was not applied`
  String get rstNotApplied {
    return Intl.message(
      'The restore was not applied',
      name: 'rstNotApplied',
      desc: '',
      args: [],
    );
  }

  /// `The broker put everything back and runs on the state it had. The plan and the reason are kept on the host in data_dir/restore.failed.`
  String get rstNotAppliedNote {
    return Intl.message(
      'The broker put everything back and runs on the state it had. The plan and the reason are kept on the host in data_dir/restore.failed.',
      name: 'rstNotAppliedNote',
      desc: '',
      args: [],
    );
  }

  /// `The broker is back`
  String get rstUnknown {
    return Intl.message(
      'The broker is back',
      name: 'rstUnknown',
      desc: '',
      args: [],
    );
  }

  /// `Its audit shows neither restore_applied nor restore_failed yet. Look at System › Log before you rely on the restore.`
  String get rstUnknownNote {
    return Intl.message(
      'Its audit shows neither restore_applied nor restore_failed yet. Look at System › Log before you rely on the restore.',
      name: 'rstUnknownNote',
      desc: '',
      args: [],
    );
  }

  /// `The broker did not come back for this session`
  String get rstLost {
    return Intl.message(
      'The broker did not come back for this session',
      name: 'rstLost',
      desc: '',
      args: [],
    );
  }

  /// `It may still be starting, or it runs with other keys: after a restore of Keys and secrets this session is no longer the site's. Log in again; if the gateway does not answer, look at the broker on its host.`
  String get rstLostNote {
    return Intl.message(
      'It may still be starting, or it runs with other keys: after a restore of Keys and secrets this session is no longer the site\'s. Log in again; if the gateway does not answer, look at the broker on its host.',
      name: 'rstLostNote',
      desc: '',
      args: [],
    );
  }

  /// `Log in again`
  String get rstLogIn {
    return Intl.message('Log in again', name: 'rstLogIn', desc: '', args: []);
  }

  /// `Versions of {package}`
  String updVersionsOf(Object package) {
    return Intl.message(
      'Versions of $package',
      name: 'updVersionsOf',
      desc: '',
      args: [package],
    );
  }

  /// `This package was not updated on this broker yet.`
  String get updNeverUpdated {
    return Intl.message(
      'This package was not updated on this broker yet.',
      name: 'updNeverUpdated',
      desc: '',
      args: [],
    );
  }

  /// `This broker makes no backups for Studio (a wyrmd before ADR 0048).`
  String get bakNoBackups {
    return Intl.message(
      'This broker makes no backups for Studio (a wyrmd before ADR 0048).',
      name: 'bakNoBackups',
      desc: '',
      args: [],
    );
  }

  /// `Plan · {n} steps`
  String planSteps(Object n) {
    return Intl.message(
      'Plan · $n steps',
      name: 'planSteps',
      desc: '',
      args: [n],
    );
  }

  /// `awaiting approval · checked`
  String get planChecked {
    return Intl.message(
      'awaiting approval · checked',
      name: 'planChecked',
      desc: '',
      args: [],
    );
  }

  /// `The lines after “why” and under “the assistant says” come from the model; a warning on the yellow band is the link's own check. Read the key and the arguments of each step: they are what runs.`
  String get planWhyNote {
    return Intl.message(
      'The lines after “why” and under “the assistant says” come from the model; a warning on the yellow band is the link\'s own check. Read the key and the arguments of each step: they are what runs.',
      name: 'planWhyNote',
      desc: '',
      args: [],
    );
  }

  /// `checked against the live tree`
  String get checkNow {
    return Intl.message(
      'checked against the live tree',
      name: 'checkNow',
      desc: '',
      args: [],
    );
  }

  /// `checked when it runs: an earlier step makes this node`
  String get checkAtRun {
    return Intl.message(
      'checked when it runs: an earlier step makes this node',
      name: 'checkAtRun',
      desc: '',
      args: [],
    );
  }

  /// `needs step {n}`
  String planNeedsStep(Object n) {
    return Intl.message(
      'needs step $n',
      name: 'planNeedsStep',
      desc: '',
      args: [n],
    );
  }

  /// `{s} s`
  String planSleep(Object s) {
    return Intl.message('$s s', name: 'planSleep', desc: '', args: [s]);
  }

  /// `timeout {s} s`
  String planTimeout(Object s) {
    return Intl.message(
      'timeout $s s',
      name: 'planTimeout',
      desc: '',
      args: [s],
    );
  }

  /// `awaiting your answer`
  String get taskAwaitingAnswer {
    return Intl.message(
      'awaiting your answer',
      name: 'taskAwaitingAnswer',
      desc: '',
      args: [],
    );
  }

  /// `The plan waits for approval. Nothing runs before it.`
  String get planWaiting {
    return Intl.message(
      'The plan waits for approval. Nothing runs before it.',
      name: 'planWaiting',
      desc: '',
      args: [],
    );
  }

  /// `by {who}`
  String taskBy(Object who) {
    return Intl.message('by $who', name: 'taskBy', desc: '', args: [who]);
  }

  /// `failed at step {n}`
  String taskFailedAt(Object n) {
    return Intl.message(
      'failed at step $n',
      name: 'taskFailedAt',
      desc: '',
      args: [n],
    );
  }

  /// `nothing changed`
  String get taskNoChanges {
    return Intl.message(
      'nothing changed',
      name: 'taskNoChanges',
      desc: '',
      args: [],
    );
  }

  /// `{n, plural, =1{Approve 1 change and run} other{Approve {n} changes and run}}`
  String approveCount(num n) {
    return Intl.plural(
      n,
      one: 'Approve 1 change and run',
      other: 'Approve $n changes and run',
      name: 'approveCount',
      desc: '',
      args: [n],
    );
  }

  /// `Signs one token per ticked step with your rights ({role}). Unticked steps are left out.`
  String approveSigns(Object role) {
    return Intl.message(
      'Signs one token per ticked step with your rights ($role). Unticked steps are left out.',
      name: 'approveSigns',
      desc: '',
      args: [role],
    );
  }

  /// `Tick at least one step.`
  String get approveNone {
    return Intl.message(
      'Tick at least one step.',
      name: 'approveNone',
      desc: '',
      args: [],
    );
  }

  /// `This task is on site {site}. This gateway signs approvals only for tasks of its own site. Approve it through the gateway of {site}.`
  String approveOtherSite(Object site) {
    return Intl.message(
      'This task is on site $site. This gateway signs approvals only for tasks of its own site. Approve it through the gateway of $site.',
      name: 'approveOtherSite',
      desc: '',
      args: [site],
    );
  }

  /// `The approval was refused; the task still waits. {why}`
  String approveRefused(Object why) {
    return Intl.message(
      'The approval was refused; the task still waits. $why',
      name: 'approveRefused',
      desc: '',
      args: [why],
    );
  }

  /// `Untick the step it names and approve the rest. When the plan is done, ask for the steps left out as a follow-up: they are approved then.`
  String get approveRefusedHint {
    return Intl.message(
      'Untick the step it names and approve the rest. When the plan is done, ask for the steps left out as a follow-up: they are approved then.',
      name: 'approveRefusedHint',
      desc: '',
      args: [],
    );
  }

  /// `skipped: needs step {n}`
  String stepSkippedNeeds(Object n) {
    return Intl.message(
      'skipped: needs step $n',
      name: 'stepSkippedNeeds',
      desc: '',
      args: [n],
    );
  }

  /// `left out: it will not run`
  String get stepLeftOut {
    return Intl.message(
      'left out: it will not run',
      name: 'stepLeftOut',
      desc: '',
      args: [],
    );
  }

  /// `Reject the plan?`
  String get rejectPlanTitle {
    return Intl.message(
      'Reject the plan?',
      name: 'rejectPlanTitle',
      desc: '',
      args: [],
    );
  }

  /// `The plan is not run. The reason is kept in the task's record.`
  String get rejectPlanNote {
    return Intl.message(
      'The plan is not run. The reason is kept in the task\'s record.',
      name: 'rejectPlanNote',
      desc: '',
      args: [],
    );
  }

  /// `Reason`
  String get rejectPlanHint {
    return Intl.message('Reason', name: 'rejectPlanHint', desc: '', args: []);
  }

  /// `Ask for the steps left out`
  String get followUpLeftOut {
    return Intl.message(
      'Ask for the steps left out',
      name: 'followUpLeftOut',
      desc: '',
      args: [],
    );
  }

  /// `Do the steps that were left out of the plan of task {task}: {steps}.`
  String followUpAsk(Object task, Object steps) {
    return Intl.message(
      'Do the steps that were left out of the plan of task $task: $steps.',
      name: 'followUpAsk',
      desc: '',
      args: [task, steps],
    );
  }

  /// `The task is done. Steps left out: {steps}. Ask for them as a follow-up; its plan is approved on its own.`
  String doneLeftOutNote(Object steps) {
    return Intl.message(
      'The task is done. Steps left out: $steps. Ask for them as a follow-up; its plan is approved on its own.',
      name: 'doneLeftOutNote',
      desc: '',
      args: [steps],
    );
  }

  /// `Run · step {n} of {of}`
  String runTitle(Object n, Object of) {
    return Intl.message(
      'Run · step $n of $of',
      name: 'runTitle',
      desc: '',
      args: [n, of],
    );
  }

  /// `Run · {of} steps`
  String runTitleEnded(Object of) {
    return Intl.message(
      'Run · $of steps',
      name: 'runTitleEnded',
      desc: '',
      args: [of],
    );
  }

  /// `running…`
  String get runRunning {
    return Intl.message('running…', name: 'runRunning', desc: '', args: []);
  }

  /// `waiting`
  String get runWaiting {
    return Intl.message('waiting', name: 'runWaiting', desc: '', args: []);
  }

  /// `not run`
  String get runNotRun {
    return Intl.message('not run', name: 'runNotRun', desc: '', args: []);
  }

  /// `stops at the first step that fails`
  String get runStopsNote {
    return Intl.message(
      'stops at the first step that fails',
      name: 'runStopsNote',
      desc: '',
      args: [],
    );
  }

  /// `all steps passed`
  String get runPassed {
    return Intl.message(
      'all steps passed',
      name: 'runPassed',
      desc: '',
      args: [],
    );
  }

  /// `all steps passed · {s} s`
  String runPassedIn(Object s) {
    return Intl.message(
      'all steps passed · $s s',
      name: 'runPassedIn',
      desc: '',
      args: [s],
    );
  }

  /// `done · steps left out: {steps}`
  String runPassedLeftOut(Object steps) {
    return Intl.message(
      'done · steps left out: $steps',
      name: 'runPassedLeftOut',
      desc: '',
      args: [steps],
    );
  }

  /// `stopped · steps {steps} changed something and stay done`
  String runStopped(Object steps) {
    return Intl.message(
      'stopped · steps $steps changed something and stay done',
      name: 'runStopped',
      desc: '',
      args: [steps],
    );
  }

  /// `stopped · nothing was changed`
  String get runStoppedFirst {
    return Intl.message(
      'stopped · nothing was changed',
      name: 'runStoppedFirst',
      desc: '',
      args: [],
    );
  }

  /// `Stopped at step {n}`
  String stoppedAt(Object n) {
    return Intl.message(
      'Stopped at step $n',
      name: 'stoppedAt',
      desc: '',
      args: [n],
    );
  }

  /// `{why}\nWhat was done before it stays done; nothing is reversed by itself.`
  String stoppedNote(Object why) {
    return Intl.message(
      '$why\nWhat was done before it stays done; nothing is reversed by itself.',
      name: 'stoppedNote',
      desc: '',
      args: [why],
    );
  }

  /// `Result`
  String get resultTitle {
    return Intl.message('Result', name: 'resultTitle', desc: '', args: []);
  }

  /// `The keys the plan touched, with their values now.`
  String get resultNote {
    return Intl.message(
      'The keys the plan touched, with their values now.',
      name: 'resultNote',
      desc: '',
      args: [],
    );
  }

  /// `—`
  String get resultNoValue {
    return Intl.message('—', name: 'resultNoValue', desc: '', args: []);
  }

  /// `Open {node} in Explorer`
  String openNodeInExplorer(Object node) {
    return Intl.message(
      'Open $node in Explorer',
      name: 'openNodeInExplorer',
      desc: '',
      args: [node],
    );
  }

  /// `Save as a plan`
  String get saveAsPlan {
    return Intl.message(
      'Save as a plan',
      name: 'saveAsPlan',
      desc: '',
      args: [],
    );
  }

  /// `Save the plan of {task}`
  String savePlanTitle(Object task) {
    return Intl.message(
      'Save the plan of $task',
      name: 'savePlanTitle',
      desc: '',
      args: [task],
    );
  }

  /// `Saved {path}. Run it with wyrm-agent run.`
  String planSaved(Object path) {
    return Intl.message(
      'Saved $path. Run it with wyrm-agent run.',
      name: 'planSaved',
      desc: '',
      args: [path],
    );
  }

  /// `Show steps`
  String get showSteps {
    return Intl.message('Show steps', name: 'showSteps', desc: '', args: []);
  }

  /// `Hide steps`
  String get hideSteps {
    return Intl.message('Hide steps', name: 'hideSteps', desc: '', args: []);
  }

  /// `The assistant asks`
  String get choicesTitle {
    return Intl.message(
      'The assistant asks',
      name: 'choicesTitle',
      desc: '',
      args: [],
    );
  }

  /// `Write the plan`
  String get choicesConfirm {
    return Intl.message(
      'Write the plan',
      name: 'choicesConfirm',
      desc: '',
      args: [],
    );
  }

  /// `Or answer in your own words below.`
  String get choicesNote {
    return Intl.message(
      'Or answer in your own words below.',
      name: 'choicesNote',
      desc: '',
      args: [],
    );
  }

  /// `Pick an option, or answer in your own words below.`
  String get choicesPickOne {
    return Intl.message(
      'Pick an option, or answer in your own words below.',
      name: 'choicesPickOne',
      desc: '',
      args: [],
    );
  }

  /// `from the card: {answer}`
  String choicesFromCard(Object answer) {
    return Intl.message(
      'from the card: $answer',
      name: 'choicesFromCard',
      desc: '',
      args: [answer],
    );
  }

  /// `in your own words: {answer}`
  String choicesOwnWords(Object answer) {
    return Intl.message(
      'in your own words: $answer',
      name: 'choicesOwnWords',
      desc: '',
      args: [answer],
    );
  }

  /// `no answer`
  String get choicesNoAnswer {
    return Intl.message(
      'no answer',
      name: 'choicesNoAnswer',
      desc: '',
      args: [],
    );
  }

  /// `Answer in your own words (Cmd+Enter)`
  String get answerHint {
    return Intl.message(
      'Answer in your own words (Cmd+Enter)',
      name: 'answerHint',
      desc: '',
      args: [],
    );
  }

  /// `Answer`
  String get answerButton {
    return Intl.message('Answer', name: 'answerButton', desc: '', args: []);
  }

  /// `The assistant waits for your answer. Nothing is planned before it. A restart of the broker ends a task that waits.`
  String get answerWaitingNote {
    return Intl.message(
      'The assistant waits for your answer. Nothing is planned before it. A restart of the broker ends a task that waits.',
      name: 'answerWaitingNote',
      desc: '',
      args: [],
    );
  }

  /// `awaiting approval · {now} checked now, {atRun} when it runs`
  String planCheckedPartly(Object now, Object atRun) {
    return Intl.message(
      'awaiting approval · $now checked now, $atRun when it runs',
      name: 'planCheckedPartly',
      desc: '',
      args: [now, atRun],
    );
  }

  /// `A secret argument is not shown. The approval is still for the value the plan holds.`
  String get planSecretNote {
    return Intl.message(
      'A secret argument is not shown. The approval is still for the value the plan holds.',
      name: 'planSecretNote',
      desc: '',
      args: [],
    );
  }

  /// `runs with the agent's key: this mode needs no person for it, and it cannot be left out`
  String get stepByAgent {
    return Intl.message(
      'runs with the agent\'s key: this mode needs no person for it, and it cannot be left out',
      name: 'stepByAgent',
      desc: '',
      args: [],
    );
  }

  /// `{n, plural, =1{1 step without a tick changes something and runs with the agent's own key; it cannot be left out. Reject the plan to stop it.} other{{n} steps without a tick change something and run with the agent's own key; they cannot be left out. Reject the plan to stop them.}}`
  String approveByAgent(num n) {
    return Intl.plural(
      n,
      one: '1 step without a tick changes something and runs with the agent\'s own key; it cannot be left out. Reject the plan to stop it.',
      other:
          '$n steps without a tick change something and run with the agent\'s own key; they cannot be left out. Reject the plan to stop them.',
      name: 'approveByAgent',
      desc: '',
      args: [n],
    );
  }

  /// `stopped · step {n} changed something and stays done`
  String runStoppedOne(Object n) {
    return Intl.message(
      'stopped · step $n changed something and stays done',
      name: 'runStoppedOne',
      desc: '',
      args: [n],
    );
  }

  /// `Secret arguments are not in the file: {steps}. Add them before you run it.`
  String planSavedSecrets(Object steps) {
    return Intl.message(
      'Secret arguments are not in the file: $steps. Add them before you run it.',
      name: 'planSavedSecrets',
      desc: '',
      args: [steps],
    );
  }

  /// `Answer, or ask something else…`
  String get hintPlanning {
    return Intl.message(
      'Answer, or ask something else…',
      name: 'hintPlanning',
      desc: '',
      args: [],
    );
  }

  /// `Ask to change the plan, e.g. “skip step 4”… (a new plan replaces this one)`
  String get hintAwaiting {
    return Intl.message(
      'Ask to change the plan, e.g. “skip step 4”… (a new plan replaces this one)',
      name: 'hintAwaiting',
      desc: '',
      args: [],
    );
  }

  /// `You can write while it runs…`
  String get hintRunning {
    return Intl.message(
      'You can write while it runs…',
      name: 'hintRunning',
      desc: '',
      args: [],
    );
  }

  /// `What next?`
  String get hintDone {
    return Intl.message('What next?', name: 'hintDone', desc: '', args: []);
  }

  /// `Tell it what you know about {node}…`
  String hintFailed(Object node) {
    return Intl.message(
      'Tell it what you know about $node…',
      name: 'hintFailed',
      desc: '',
      args: [node],
    );
  }

  /// `+ from Explorer`
  String get addFromExplorer {
    return Intl.message(
      '+ from Explorer',
      name: 'addFromExplorer',
      desc: '',
      args: [],
    );
  }

  /// `Select a node in Explorer first; it is added here as @ chip.`
  String get addFromExplorerNone {
    return Intl.message(
      'Select a node in Explorer first; it is added here as @ chip.',
      name: 'addFromExplorerNone',
      desc: '',
      args: [],
    );
  }

  /// `the assistant says`
  String get modelSays {
    return Intl.message(
      'the assistant says',
      name: 'modelSays',
      desc: '',
      args: [],
    );
  }

  /// `what the assistant read about it`
  String get modelReviewed {
    return Intl.message(
      'what the assistant read about it',
      name: 'modelReviewed',
      desc: '',
      args: [],
    );
  }

  /// `replaces this plan`
  String get fixReplaces {
    return Intl.message(
      'replaces this plan',
      name: 'fixReplaces',
      desc: '',
      args: [],
    );
  }

  /// `{n, plural, =0{nothing · its guess} =1{1 change · its guess} other{{n} changes · its guess}}`
  String changesGuess(num n) {
    return Intl.plural(
      n,
      zero: 'nothing · its guess',
      one: '1 change · its guess',
      other: '$n changes · its guess',
      name: 'changesGuess',
      desc: '',
      args: [n],
    );
  }

  /// `Ways out`
  String get waysOut {
    return Intl.message('Ways out', name: 'waysOut', desc: '', args: []);
  }

  /// `The assistant reads why it stopped…`
  String get reviewingNote {
    return Intl.message(
      'The assistant reads why it stopped…',
      name: 'reviewingNote',
      desc: '',
      args: [],
    );
  }

  /// `A pick is a new ask. Its plan is checked and waits for your approval, step by step.`
  String get waysNote {
    return Intl.message(
      'A pick is a new ask. Its plan is checked and waits for your approval, step by step.',
      name: 'waysNote',
      desc: '',
      args: [],
    );
  }

  /// `With require_approval “{mode}”, the plan of a pick runs its write steps without a person. The tag is the assistant's guess, not a check. Read a tile before you pick it.`
  String waysCaution(Object mode) {
    return Intl.message(
      'With require_approval “$mode”, the plan of a pick runs its write steps without a person. The tag is the assistant\'s guess, not a check. Read a tile before you pick it.',
      name: 'waysCaution',
      desc: '',
      args: [mode],
    );
  }

  /// `{n, plural, =0{Make a plan} =1{Make a plan for 1 unit} other{Make a plan for {n} units}}`
  String moreButton(num n) {
    return Intl.plural(
      n,
      zero: 'Make a plan',
      one: 'Make a plan for 1 unit',
      other: 'Make a plan for $n units',
      name: 'moreButton',
      desc: '',
      args: [n],
    );
  }

  /// `Tick the nodes the plan is for.`
  String get moreNone {
    return Intl.message(
      'Tick the nodes the plan is for.',
      name: 'moreNone',
      desc: '',
      args: [],
    );
  }

  /// `The rows are the assistant's. Its plan for them waits for your approval.`
  String get moreNote {
    return Intl.message(
      'The rows are the assistant\'s. Its plan for them waits for your approval.',
      name: 'moreNote',
      desc: '',
      args: [],
    );
  }

  /// `replaced`
  String get replacedTitle {
    return Intl.message('replaced', name: 'replacedTitle', desc: '', args: []);
  }

  /// `This plan was replaced by tasks/{id} and cannot be approved. Approve the plan of that task instead.`
  String replacedNote(Object id) {
    return Intl.message(
      'This plan was replaced by tasks/$id and cannot be approved. Approve the plan of that task instead.',
      name: 'replacedNote',
      desc: '',
      args: [id],
    );
  }

  /// `Open tasks/{id}`
  String openReplacement(Object id) {
    return Intl.message(
      'Open tasks/$id',
      name: 'openReplacement',
      desc: '',
      args: [id],
    );
  }

  /// `replaced by {id}`
  String taskReplaced(Object id) {
    return Intl.message(
      'replaced by $id',
      name: 'taskReplaced',
      desc: '',
      args: [id],
    );
  }

  /// `only the asker of this task, or config on the agent link, can follow it up`
  String get followNeeds {
    return Intl.message(
      'only the asker of this task, or config on the agent link, can follow it up',
      name: 'followNeeds',
      desc: '',
      args: [],
    );
  }

  /// `The schema of this step is not known yet (an earlier step makes its node): its arguments are masked, and none goes into a saved plan.`
  String get argsMasked {
    return Intl.message(
      'The schema of this step is not known yet (an earlier step makes its node): its arguments are masked, and none goes into a saved plan.',
      name: 'argsMasked',
      desc: '',
      args: [],
    );
  }

  /// `Show arguments`
  String get showArgs {
    return Intl.message('Show arguments', name: 'showArgs', desc: '', args: []);
  }

  /// `Hide arguments`
  String get hideArgs {
    return Intl.message('Hide arguments', name: 'hideArgs', desc: '', args: []);
  }

  /// `Stopped at step {n} · {code}`
  String stoppedAtCode(Object n, Object code) {
    return Intl.message(
      'Stopped at step $n · $code',
      name: 'stoppedAtCode',
      desc: '',
      args: [n, code],
    );
  }

  /// `replaces this plan; with require_approval “{mode}” the new plan's write steps run without a person`
  String fixReplacesNoPerson(Object mode) {
    return Intl.message(
      'replaces this plan; with require_approval “$mode” the new plan\'s write steps run without a person',
      name: 'fixReplacesNoPerson',
      desc: '',
      args: [mode],
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
