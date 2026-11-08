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
