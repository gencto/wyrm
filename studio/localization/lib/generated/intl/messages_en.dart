// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(key) => "Go to ${key}";

  static String m1(level, have) => "Needs ${level} · you have ${have}";

  static String m2(level) => "Needs ${level} · you have it";

  static String m3(count) =>
      "${Intl.plural(count, zero: 'No staged changes', one: '1 staged change', other: '${count} staged changes')}";

  static String m4(site) => "via ${site}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "_locale": MessageLookupByLibrary.simpleMessage("en"),
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Apply"),
    "brokerRefused": MessageLookupByLibrary.simpleMessage(
      "The broker refused a change; the ones after it were not applied.",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "cannotReachGateway": MessageLookupByLibrary.simpleMessage(
      "Cannot reach the gateway",
    ),
    "checkYourConnection": MessageLookupByLibrary.simpleMessage(
      "Check your connection and try again.",
    ),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t connect to internet.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Dark theme"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Design gallery"),
    "discard": MessageLookupByLibrary.simpleMessage("Discard"),
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("Gateway URL"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445, or several separated by commas",
    ),
    "goTo": m0,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Not a gateway URL (http:// or https:// and a host)",
    ),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Light theme"),
    "logIn": MessageLookupByLibrary.simpleMessage("Log in"),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Sign in to a WYRM gateway.",
    ),
    "logOut": MessageLookupByLibrary.simpleMessage("Log out"),
    "more": MessageLookupByLibrary.simpleMessage("More"),
    "needsLevelYouHave": m1,
    "needsLevelYouHaveIt": m2,
    "networkError": MessageLookupByLibrary.simpleMessage("Connection problem"),
    "nothingStaged": MessageLookupByLibrary.simpleMessage(
      "Nothing staged. Edit a value or a parameter to stage it.",
    ),
    "offline": MessageLookupByLibrary.simpleMessage(
      "The gateway connection is lost. Reconnecting; values on screen are the last ones received.",
    ),
    "ok": MessageLookupByLibrary.simpleMessage("OK"),
    "password": MessageLookupByLibrary.simpleMessage("Password"),
    "pleaseCheckYourNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Please check your network settings.",
    ),
    "pleaseLogInAgain": MessageLookupByLibrary.simpleMessage(
      "Please log in again.",
    ),
    "requiredField": MessageLookupByLibrary.simpleMessage("Required field"),
    "review": MessageLookupByLibrary.simpleMessage("Review"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage("Review and apply"),
    "searchHint": MessageLookupByLibrary.simpleMessage(
      "Go to a node, action or link",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Session expired"),
    "somethingWentWrong": MessageLookupByLibrary.simpleMessage(
      "Something went wrong",
    ),
    "stagedChanges": m3,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Nothing is written until you apply. Each change runs with your own rights.",
    ),
    "thisBroker": MessageLookupByLibrary.simpleMessage("this broker"),
    "tryAgainLater": MessageLookupByLibrary.simpleMessage(
      "Please try again later.",
    ),
    "upstream": MessageLookupByLibrary.simpleMessage("upstream"),
    "user": MessageLookupByLibrary.simpleMessage("User"),
    "viaSite": m4,
    "wsAccess": MessageLookupByLibrary.simpleMessage("Access"),
    "wsAssistant": MessageLookupByLibrary.simpleMessage("Assistant"),
    "wsExplorer": MessageLookupByLibrary.simpleMessage("Explorer"),
    "wsFlows": MessageLookupByLibrary.simpleMessage("Flows"),
    "wsHistory": MessageLookupByLibrary.simpleMessage("History"),
    "wsLinks": MessageLookupByLibrary.simpleMessage("Links"),
    "wsSites": MessageLookupByLibrary.simpleMessage("Sites"),
    "wsSystem": MessageLookupByLibrary.simpleMessage("System"),
  };
}
