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

  static String m0(site) => "Access on ${site}";

  static String m1(n) => "${n} in";

  static String m2(n) => "${n} d ago";

  static String m3(n) => "${n} h ago";

  static String m4(n) => "${n} min ago";

  static String m5(count) =>
      "${Intl.plural(count, one: 'Apply 1 change', other: 'Apply ${count} changes')}";

  static String m6(count) => "Ask an admin for ${count}";

  static String m7(n) => "asks to join · relays ${n}";

  static String m8(sites) => "asks to relay: ${sites}";

  static String m9(code) => "refused (${code})";

  static String m10(n) =>
      "${Intl.plural(n, one: '1 block', other: '${n} blocks')}";

  static String m11(brokers, devices) =>
      "${brokers} brokers · ${devices} devices";

  static String m12(driver) => "built-in driver ${driver}";

  static String m13(site) => "CA-signed · ${site} CA";

  static String m14(site) =>
      "${site} dials out to it; it authorizes ${site} there.";

  static String m15(size) => "data_dir ${size}";

  static String m16(id) => "Deauthorize ${id}?";

  static String m17(device) =>
      "It runs on ${device}; the broker cannot start or stop it.";

  static String m18(id) => "Edit params of ${id}";

  static String m19(s) => "every ${s} s";

  static String m20(when) => "first seen ${when}";

  static String m21(v) => "v${v} deployed";

  static String m22(v) => "v${v} · error";

  static String m23(v) => "v${v} stopped";

  static String m24(v) => "Version ${v}";

  static String m25(site) => "Flows on ${site}";

  static String m26(address) => "from ${address}";

  static String m27(key) => "Go to ${key}";

  static String m28(id) => "Grant access to ${id}";

  static String m29(days) => "raw kept ${days} d";

  static String m30(n) => "${n} series";

  static String m31(size) => "Historian ${size}";

  static String m32(id) => "Params history of ${id}";

  static String m33(n) =>
      "${Intl.plural(n, one: '1 input', other: '${n} inputs')}";

  static String m34(name, broker) => "${name} is installed on ${broker}.";

  static String m35(count) => "${count} keys copied";

  static String m36(lag) => "lag ${lag}";

  static String m37(time) => "last read ${time}";

  static String m38(n) =>
      "${Intl.plural(n, one: '1 link already', other: '${n} links already')}";

  static String m39(site) =>
      "Started and watched by ${site}: built-in drivers and installed packages. You can stop, change, upgrade and remove them.";

  static String m40(site) => "Links on ${site}";

  static String m41(id) => "Log of ${id}";

  static String m42(kind, count) => "${kind} · ${count} actions";

  static String m43(count) => "${count} selected";

  static String m44(level, have) => "Needs ${level} · you have ${have}";

  static String m45(level) => "Needs ${level} · you have it";

  static String m46(action) => "This node has no ${action} action.";

  static String m47(param) => "The driver has no ${param} parameter.";

  static String m48(site) => "none: ${site} is the top";

  static String m49(site) => "Explorer shows wy/${site}.";

  static String m50(name) => "package ${name}";

  static String m51(n) =>
      "${Intl.plural(n, zero: 'no parameters', one: '1 parameter', other: '${n} parameters')}";

  static String m52(rev) => "Parameters (revision ${rev}, JSON)";

  static String m53(n) =>
      "${Intl.plural(n, one: '1 point', other: '${n} points')}";

  static String m54(name) => "${name} is installed";

  static String m55(name) => "Installing ${name}…";

  static String m56(cn) => "Reject ${cn}?";

  static String m57(n) =>
      "${Intl.plural(n, one: 'relays 1 site', other: 'relays ${n} sites')}";

  static String m58(id) => "Remove ${id}?";

  static String m59(name) => "Remove ${name}?";

  static String m60(action) => "Result · ${action}";

  static String m61(what) => "returns ${what}";

  static String m62(audit) =>
      "Each write is checked by the link and recorded in ${audit}. A value shows only after it is read back.";

  static String m63(rev) => "Revision ${rev}";

  static String m64(rev) => "Revision ${rev} · in use";

  static String m65(site, user, role, level) =>
      "Site ${site} · applied with your rights: ${user}, ${role} (${level})";

  static String m66(rev) => "Roll back to revision ${rev}?";

  static String m67(n) => "${Intl.plural(n, one: '1 row', other: '${n} rows')}";

  static String m68(user) =>
      "Runs as ${user}. Nothing else in the tree changes unless the result is used.";

  static String m69(site) => "Runs on ${site}";

  static String m70(level) => "Log level ${level}";

  static String m71(site) => "Sites around ${site}";

  static String m72(site) =>
      "What ${site} connects to and what connects to it: brokers above and below, platforms it sends to, and devices whose links run outside any broker.";

  static String m73(count) =>
      "${Intl.plural(count, zero: 'No staged changes', one: '1 staged change', other: '${count} staged changes')}";

  static String m74(was) => "staged · was ${was}";

  static String m75(n, total) => "Step ${n} of ${total}";

  static String m76(level) => "needs ${level}";

  static String m77(agent) => "Each task is a node: ${agent}/tasks/<id>";

  static String m78(site) => "Tree · ${site}";

  static String m79(unit) => "unit ${unit}";

  static String m80(d) => "up ${d}";

  static String m81(v) => "Version ${v} · deployed";

  static String m82(site) => "via ${site}";

  static String m83(n, who) => "${n} waiting to be let in: ${who}";

  static String m84(value) => "was ${value}";

  static String m85(n) => "Watch groups · ${n}";

  static String m86(level) => "Turning this on needs ${level} level";

  static String m87(site) => "wyrmd on ${site}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "_locale": MessageLookupByLibrary.simpleMessage("en"),
    "aCustomPackage": MessageLookupByLibrary.simpleMessage("A custom package"),
    "acceptFirst": MessageLookupByLibrary.simpleMessage(
      "Accept the requested rights first.",
    ),
    "acceptRequestedRights": MessageLookupByLibrary.simpleMessage(
      "Accept requested rights",
    ),
    "accepted": MessageLookupByLibrary.simpleMessage("accepted"),
    "accessOn": m0,
    "accessSubtitle": MessageLookupByLibrary.simpleMessage(
      "Who may log in to this gateway, what each role may reach, and what was done.",
    ),
    "actComesWithWyrmd": MessageLookupByLibrary.simpleMessage(
      "Comes with wyrmd",
    ),
    "actComesWithWyrmdNote": MessageLookupByLibrary.simpleMessage(
      "A built-in driver updates with the broker.",
    ),
    "actDeauthorize": MessageLookupByLibrary.simpleMessage("Deauthorize"),
    "actDeauthorizeNote": MessageLookupByLibrary.simpleMessage(
      "Block it now: its rights are cut and its next connection waits in quarantine. Its tree stays.",
    ),
    "actEditParams": MessageLookupByLibrary.simpleMessage("Edit params"),
    "actEditParamsNote": MessageLookupByLibrary.simpleMessage(
      "Link-wide parameters. Saved as a new revision.",
    ),
    "actGrant": MessageLookupByLibrary.simpleMessage("Grant access"),
    "actGrantNote": MessageLookupByLibrary.simpleMessage(
      "Read or write outside its own branch.",
    ),
    "actGrants": MessageLookupByLibrary.simpleMessage("Grants"),
    "actGrantsNote": MessageLookupByLibrary.simpleMessage(
      "Only its own branch. Add read or write elsewhere.",
    ),
    "actParamsHistory": MessageLookupByLibrary.simpleMessage("Params history"),
    "actParamsHistoryNote": MessageLookupByLibrary.simpleMessage(
      "The revisions of its parameters; roll back to any.",
    ),
    "actRemoveForGood": MessageLookupByLibrary.simpleMessage("Remove for good"),
    "actRemoveForGoodNote": MessageLookupByLibrary.simpleMessage(
      "Retire the id: this certificate never gets rights again. A new device needs a new certificate.",
    ),
    "actRemoveLink": MessageLookupByLibrary.simpleMessage("Remove link"),
    "actRemoveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Stops it and deletes its tree.",
    ),
    "actSecrets": MessageLookupByLibrary.simpleMessage("Secrets"),
    "actSecretsNote": MessageLookupByLibrary.simpleMessage(
      "Passwords and keys, sealed; never shown again.",
    ),
    "actStart": MessageLookupByLibrary.simpleMessage("Start"),
    "actStartNote": MessageLookupByLibrary.simpleMessage(
      "Run it again with its last parameters.",
    ),
    "actStartStopRestart": MessageLookupByLibrary.simpleMessage(
      "Start, stop, restart",
    ),
    "actStop": MessageLookupByLibrary.simpleMessage("Stop"),
    "actStopNote": MessageLookupByLibrary.simpleMessage(
      "Stays installed; its points go bad until you start it.",
    ),
    "actUpgrade": MessageLookupByLibrary.simpleMessage("Upgrade"),
    "actUpgradeNote": MessageLookupByLibrary.simpleMessage(
      "Install a newer version of its package.",
    ),
    "actUpgradeParamsLog": MessageLookupByLibrary.simpleMessage(
      "Upgrade, params, log",
    ),
    "actViewLog": MessageLookupByLibrary.simpleMessage("View log"),
    "actViewLogNote": MessageLookupByLibrary.simpleMessage(
      "Its last lines and its own log level.",
    ),
    "actionInputs": m1,
    "addALink": MessageLookupByLibrary.simpleMessage("Add a link"),
    "addAgent": MessageLookupByLibrary.simpleMessage("Add the agent link"),
    "addAnother": MessageLookupByLibrary.simpleMessage("Add another"),
    "addGrant": MessageLookupByLibrary.simpleMessage("Add a grant"),
    "addInput": MessageLookupByLibrary.simpleMessage("Add an input"),
    "addPoint": MessageLookupByLibrary.simpleMessage("Add point"),
    "addUser": MessageLookupByLibrary.simpleMessage("Add a user"),
    "addWatchPath": MessageLookupByLibrary.simpleMessage("Add a point"),
    "addWatchPathNote": MessageLookupByLibrary.simpleMessage(
      "Record one more point (a key under downstream, dataflows or storage).",
    ),
    "adminsOnly": MessageLookupByLibrary.simpleMessage(
      "Users are managed by the gateway\'s administrators.",
    ),
    "agoDays": m2,
    "agoHours": m3,
    "agoMinutes": m4,
    "agoNow": MessageLookupByLibrary.simpleMessage("just now"),
    "allowAllLinks": MessageLookupByLibrary.simpleMessage("Allow all links"),
    "allowAllLinksNote": MessageLookupByLibrary.simpleMessage(
      "Every new CN from this CA becomes a link at once, no approval. A leaked certificate gets in.",
    ),
    "andWord": MessageLookupByLibrary.simpleMessage("and"),
    "answerBroker": MessageLookupByLibrary.simpleMessage("Broker"),
    "answerFrom": MessageLookupByLibrary.simpleMessage("From"),
    "answerLink": MessageLookupByLibrary.simpleMessage("Link"),
    "answerName": MessageLookupByLibrary.simpleMessage("Name"),
    "answerRights": MessageLookupByLibrary.simpleMessage("Rights"),
    "answerRuns": MessageLookupByLibrary.simpleMessage("Runs"),
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Apply"),
    "applyChanges": m5,
    "applyProfile": MessageLookupByLibrary.simpleMessage("Apply profile"),
    "approve": MessageLookupByLibrary.simpleMessage("Approve"),
    "approveBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Approve admits it as a downstream broker with the relays above. Compare the key with its sys/upstream/<this site>/key first.",
    ),
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Approve makes it an external link with its own branch and a link token; copy the token to the device. The router reloads for about a second. Reject refuses this CN from now on.",
    ),
    "approveReasonNote": MessageLookupByLibrary.simpleMessage(
      "Approving needs the gateway to sign the steps for you (docs/studio.md §10 item 1). Approve with wyrm-agent for now.",
    ),
    "askAdminFor": m6,
    "askAdminReason": MessageLookupByLibrary.simpleMessage(
      "The broker has no call to send a request to an admin yet.",
    ),
    "askButton": MessageLookupByLibrary.simpleMessage("Ask"),
    "askHint": MessageLookupByLibrary.simpleMessage(
      "Ask for a change, or a question about the network (Cmd+Enter)",
    ),
    "asksToJoin": MessageLookupByLibrary.simpleMessage("asks to join"),
    "asksToJoinRelays": m7,
    "asksToRelay": m8,
    "auditDone": MessageLookupByLibrary.simpleMessage("done"),
    "auditNeeds": MessageLookupByLibrary.simpleMessage(
      "The audit needs config on sys/audit.",
    ),
    "auditRefused": m9,
    "back": MessageLookupByLibrary.simpleMessage("Back"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("Back to Links"),
    "bindHint": MessageLookupByLibrary.simpleMessage(
      "Drag an output here to bind",
    ),
    "block": MessageLookupByLibrary.simpleMessage("Block"),
    "blocksCount": m10,
    "branchOrTag": MessageLookupByLibrary.simpleMessage("branch or tag"),
    "bringOne": MessageLookupByLibrary.simpleMessage(
      "Choose a file or type where the package is.",
    ),
    "brokerLog": MessageLookupByLibrary.simpleMessage("Log"),
    "brokerRefused": MessageLookupByLibrary.simpleMessage(
      "The broker refused a change; the ones after it were not applied.",
    ),
    "brokerSays": MessageLookupByLibrary.simpleMessage("The broker says"),
    "brokerWaiting": MessageLookupByLibrary.simpleMessage("Broker waiting"),
    "brokersDevices": m11,
    "builtIn": MessageLookupByLibrary.simpleMessage("built in"),
    "builtInDriver": m12,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Built into wyrmd · nothing to download",
    ),
    "caSigned": m13,
    "canDoNothing": MessageLookupByLibrary.simpleMessage(
      "nothing: no read, no write",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "cancelTask": MessageLookupByLibrary.simpleMessage("Cancel task"),
    "cannotReachGateway": MessageLookupByLibrary.simpleMessage(
      "Cannot reach the gateway",
    ),
    "catalogNote": MessageLookupByLibrary.simpleMessage(
      "Built in: in wyrmd, nothing to download. Package: from the index in packages.repository, SHA-256 checked; a broker lists only packages it can install.",
    ),
    "cfgApiKey": MessageLookupByLibrary.simpleMessage("API key secret"),
    "cfgApproval": MessageLookupByLibrary.simpleMessage("Approval for"),
    "cfgBudget": MessageLookupByLibrary.simpleMessage("Tokens a day"),
    "cfgModel": MessageLookupByLibrary.simpleMessage("Model"),
    "cfgPrefixes": MessageLookupByLibrary.simpleMessage("May change"),
    "changeAnswers": MessageLookupByLibrary.simpleMessage("Change the answers"),
    "checkFailed": MessageLookupByLibrary.simpleMessage(
      "The package did not pass: bring another one.",
    ),
    "checkYourConnection": MessageLookupByLibrary.simpleMessage(
      "Check your connection and try again.",
    ),
    "checkedHere": MessageLookupByLibrary.simpleMessage(
      "Checked here; the broker checks again before it installs.",
    ),
    "chooseWasm": MessageLookupByLibrary.simpleMessage(
      "Choose a .wasm component",
    ),
    "chooseZip": MessageLookupByLibrary.simpleMessage("Choose a package .zip"),
    "clearConns": MessageLookupByLibrary.simpleMessage(
      "Clear disconnected links",
    ),
    "clearConnsNote": MessageLookupByLibrary.simpleMessage(
      "Removes external links that are not connected; their ids are retired.",
    ),
    "clearSelection": MessageLookupByLibrary.simpleMessage("Clear"),
    "closeLabel": MessageLookupByLibrary.simpleMessage("Close"),
    "colCertificate": MessageLookupByLibrary.simpleMessage("Certificate"),
    "colDeployedBy": MessageLookupByLibrary.simpleMessage("Deployed by"),
    "colFlow": MessageLookupByLibrary.simpleMessage("Flow"),
    "colFrom": MessageLookupByLibrary.simpleMessage("From"),
    "colKey": MessageLookupByLibrary.simpleMessage("Key"),
    "colLevel": MessageLookupByLibrary.simpleMessage("Level"),
    "colLink": MessageLookupByLibrary.simpleMessage("Link"),
    "colLinkDevice": MessageLookupByLibrary.simpleMessage("Link · device"),
    "colMode": MessageLookupByLibrary.simpleMessage("Mode"),
    "colOp": MessageLookupByLibrary.simpleMessage("What"),
    "colPoint": MessageLookupByLibrary.simpleMessage("Point"),
    "colPoll": MessageLookupByLibrary.simpleMessage("Poll"),
    "colQuality": MessageLookupByLibrary.simpleMessage("Quality"),
    "colReadsWrites": MessageLookupByLibrary.simpleMessage("Reads → writes"),
    "colRegister": MessageLookupByLibrary.simpleMessage("Register"),
    "colResult": MessageLookupByLibrary.simpleMessage("Result"),
    "colRole": MessageLookupByLibrary.simpleMessage("Role"),
    "colRoles": MessageLookupByLibrary.simpleMessage("Roles"),
    "colRows": MessageLookupByLibrary.simpleMessage("Rows shown"),
    "colRunsAs": MessageLookupByLibrary.simpleMessage("Runs as"),
    "colSource": MessageLookupByLibrary.simpleMessage("From"),
    "colState": MessageLookupByLibrary.simpleMessage("State"),
    "colTime": MessageLookupByLibrary.simpleMessage("Time"),
    "colType": MessageLookupByLibrary.simpleMessage("Type"),
    "colUnit": MessageLookupByLibrary.simpleMessage("Unit"),
    "colUser": MessageLookupByLibrary.simpleMessage("User"),
    "colValue": MessageLookupByLibrary.simpleMessage("Value"),
    "colVersionSource": MessageLookupByLibrary.simpleMessage(
      "Version · source",
    ),
    "colWatch": MessageLookupByLibrary.simpleMessage("Watch"),
    "colWho": MessageLookupByLibrary.simpleMessage("Who"),
    "colWhyHere": MessageLookupByLibrary.simpleMessage("Why here"),
    "colWrite": MessageLookupByLibrary.simpleMessage("Write"),
    "collecting": MessageLookupByLibrary.simpleMessage("Collecting values…"),
    "configAllowed": MessageLookupByLibrary.simpleMessage(
      "config allowed for this upstream",
    ),
    "configureStaged": MessageLookupByLibrary.simpleMessage(
      "Configure · staged",
    ),
    "configureStagedNote": MessageLookupByLibrary.simpleMessage(
      "Staged with your other edits; applied in Review.",
    ),
    "connect": MessageLookupByLibrary.simpleMessage("Connect"),
    "connectNote": m14,
    "connectUpstream": MessageLookupByLibrary.simpleMessage(
      "Connect to an upstream",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("connected"),
    "continueLabel": MessageLookupByLibrary.simpleMessage("Continue"),
    "controlPlane": MessageLookupByLibrary.simpleMessage("Control plane"),
    "copyKey": MessageLookupByLibrary.simpleMessage("Copy key"),
    "copyKeys": MessageLookupByLibrary.simpleMessage("Copy keys"),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t connect to internet.",
    ),
    "customPackage": MessageLookupByLibrary.simpleMessage("Custom package"),
    "customPackageNote": MessageLookupByLibrary.simpleMessage(
      "A package archive you bring: a zip, a URL, a Git repository or one .wasm. It is checked before install.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Dark theme"),
    "dataDir": m15,
    "dataflow": MessageLookupByLibrary.simpleMessage("Dataflow"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Its rights here are cut now and its next connection waits in quarantine. Its sites stay below it.",
    ),
    "deauthorizeTitle": m16,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Decide in Links"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "A link in quarantine is approved or rejected in Links › Quarantine.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("decide in Sites"),
    "deploy": MessageLookupByLibrary.simpleMessage("Deploy"),
    "deploying": MessageLookupByLibrary.simpleMessage("Deploying…"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Design gallery"),
    "designGalleryNote": MessageLookupByLibrary.simpleMessage(
      "Every part of the design system (development builds).",
    ),
    "disableUser": MessageLookupByLibrary.simpleMessage("Disable"),
    "disableUserNote": MessageLookupByLibrary.simpleMessage(
      "A disabled user cannot log in; their roles stay.",
    ),
    "discard": MessageLookupByLibrary.simpleMessage("Discard"),
    "discardAll": MessageLookupByLibrary.simpleMessage("Discard all"),
    "doneNote": MessageLookupByLibrary.simpleMessage(
      "The task is done. Its record keeps the plan and the log.",
    ),
    "doneOnTheDevice": m17,
    "doneOnTheDeviceUpgrade": MessageLookupByLibrary.simpleMessage(
      "Whoever runs the device updates it there; it reconnects with the same certificate.",
    ),
    "downstream": MessageLookupByLibrary.simpleMessage("downstream"),
    "downstreamBroker": MessageLookupByLibrary.simpleMessage(
      "Downstream broker",
    ),
    "downstreamBrokerQuic": MessageLookupByLibrary.simpleMessage(
      "downstream broker · over quic",
    ),
    "draftSaved": MessageLookupByLibrary.simpleMessage("Draft saved"),
    "draftValid": MessageLookupByLibrary.simpleMessage(
      "Draft · valid, not deployed",
    ),
    "editDataflow": MessageLookupByLibrary.simpleMessage("Edit dataflow"),
    "editDataflowNote": MessageLookupByLibrary.simpleMessage(
      "Open it in the editor; nothing changes until you deploy.",
    ),
    "editGroup": MessageLookupByLibrary.simpleMessage("Edit the group"),
    "editGroupNote": MessageLookupByLibrary.simpleMessage(
      "How and how often its points are recorded.",
    ),
    "editParamsNote": MessageLookupByLibrary.simpleMessage(
      "Stage applies with the other changes; the link restarts with the new revision.",
    ),
    "editParamsOf": m18,
    "enableUser": MessageLookupByLibrary.simpleMessage("Enable"),
    "everySeconds": m19,
    "factAbout": MessageLookupByLibrary.simpleMessage("About"),
    "factAgent": MessageLookupByLibrary.simpleMessage("Agent"),
    "factAllowConfig": MessageLookupByLibrary.simpleMessage("Config from it"),
    "factAskedBy": MessageLookupByLibrary.simpleMessage("Asked by"),
    "factBelow": MessageLookupByLibrary.simpleMessage("Below"),
    "factBlocks": MessageLookupByLibrary.simpleMessage("Blocks"),
    "factBranch": MessageLookupByLibrary.simpleMessage("Branch"),
    "factBuild": MessageLookupByLibrary.simpleMessage("Build"),
    "factCanDo": MessageLookupByLibrary.simpleMessage("Can do"),
    "factCertificate": MessageLookupByLibrary.simpleMessage("Certificate"),
    "factDeployedBy": MessageLookupByLibrary.simpleMessage("Deployed by"),
    "factDevice": MessageLookupByLibrary.simpleMessage("Device"),
    "factEvents": MessageLookupByLibrary.simpleMessage("Events"),
    "factFlush": MessageLookupByLibrary.simpleMessage("Flush"),
    "factFrom": MessageLookupByLibrary.simpleMessage("From"),
    "factGrants": MessageLookupByLibrary.simpleMessage("Grants"),
    "factHistory": MessageLookupByLibrary.simpleMessage("History"),
    "factInterval": MessageLookupByLibrary.simpleMessage("Interval"),
    "factKey": MessageLookupByLibrary.simpleMessage("Key"),
    "factKind": MessageLookupByLibrary.simpleMessage("Kind"),
    "factLive": MessageLookupByLibrary.simpleMessage("Live values"),
    "factLogLevel": MessageLookupByLibrary.simpleMessage("Log level"),
    "factMayWrite": MessageLookupByLibrary.simpleMessage("May write"),
    "factOldest": MessageLookupByLibrary.simpleMessage("Oldest day"),
    "factProblem": MessageLookupByLibrary.simpleMessage("Problem"),
    "factReads": MessageLookupByLibrary.simpleMessage("Reads"),
    "factRecord": MessageLookupByLibrary.simpleMessage("Record"),
    "factRelays": MessageLookupByLibrary.simpleMessage("Relays"),
    "factRowsWritten": MessageLookupByLibrary.simpleMessage("Rows written"),
    "factRunning": MessageLookupByLibrary.simpleMessage("Running"),
    "factRunsAs": MessageLookupByLibrary.simpleMessage("Runs as"),
    "factSeen": MessageLookupByLibrary.simpleMessage("Seen"),
    "factStarted": MessageLookupByLibrary.simpleMessage("Started"),
    "factStatus": MessageLookupByLibrary.simpleMessage("Status"),
    "factSubject": MessageLookupByLibrary.simpleMessage("Subject"),
    "factTask": MessageLookupByLibrary.simpleMessage("Task"),
    "factTaskState": MessageLookupByLibrary.simpleMessage("State"),
    "factThrough": MessageLookupByLibrary.simpleMessage("Through"),
    "factTree": MessageLookupByLibrary.simpleMessage("Tree"),
    "factUpstreams": MessageLookupByLibrary.simpleMessage("Upstreams"),
    "factVersion": MessageLookupByLibrary.simpleMessage("Version"),
    "factWrites": MessageLookupByLibrary.simpleMessage("Writes"),
    "failed": MessageLookupByLibrary.simpleMessage("failed"),
    "failedNote": MessageLookupByLibrary.simpleMessage(
      "The task stopped. What was done stays done.",
    ),
    "fieldAddress": MessageLookupByLibrary.simpleMessage("Address"),
    "fieldArea": MessageLookupByLibrary.simpleMessage("Area"),
    "fieldBit": MessageLookupByLibrary.simpleMessage("Bit"),
    "fieldDataType": MessageLookupByLibrary.simpleMessage("Data type"),
    "fieldOffset": MessageLookupByLibrary.simpleMessage("Offset"),
    "fieldPrecision": MessageLookupByLibrary.simpleMessage("Precision"),
    "fieldRegisters": MessageLookupByLibrary.simpleMessage("Registers"),
    "fieldScale": MessageLookupByLibrary.simpleMessage("Scale"),
    "fieldUnit": MessageLookupByLibrary.simpleMessage("Unit"),
    "fieldWordOrder": MessageLookupByLibrary.simpleMessage("Word order"),
    "fieldWritable": MessageLookupByLibrary.simpleMessage("Writable"),
    "fieldWritableByMaster": MessageLookupByLibrary.simpleMessage(
      "Writable by the master",
    ),
    "filter": MessageLookupByLibrary.simpleMessage("Filter"),
    "filterPoints": MessageLookupByLibrary.simpleMessage("Filter points"),
    "findBlock": MessageLookupByLibrary.simpleMessage("Find a block"),
    "findInTree": MessageLookupByLibrary.simpleMessage(
      "Find a point or action",
    ),
    "firesAtDeploy": MessageLookupByLibrary.simpleMessage("fires at deploy"),
    "firesAtDeployNote": MessageLookupByLibrary.simpleMessage(
      "A parameter sends its value when the flow starts, so this writes at every deploy.",
    ),
    "firstSeen": m20,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "The draft does not validate.",
    ),
    "flowDeployed": m21,
    "flowError": m22,
    "flowName": MessageLookupByLibrary.simpleMessage("Flow id"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.",
    ),
    "flowPropertiesNote2": MessageLookupByLibrary.simpleMessage(
      "A bound field shows its source here and in the block; click the link icon to unbind.",
    ),
    "flowStopped": m23,
    "flowVersion": m24,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "A deploy needs config on dataflows; the gateway adds your proofs for each target. Viewers can open a flow and only look.",
    ),
    "flowsOn": m25,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Each flow runs in the broker. You edit a draft; nothing changes until you deploy it.",
    ),
    "fromAddress": m26,
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "From the official list",
    ),
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("Gateway URL"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445, or several separated by commas",
    ),
    "gatewayUser": MessageLookupByLibrary.simpleMessage("Gateway user"),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git repository (HTTPS)",
    ),
    "goTo": m27,
    "goUp": MessageLookupByLibrary.simpleMessage("Go up"),
    "grantFor": m28,
    "grantLevel": MessageLookupByLibrary.simpleMessage("Level"),
    "grantPath": MessageLookupByLibrary.simpleMessage("Key or pattern"),
    "groupChange": MessageLookupByLibrary.simpleMessage("Change"),
    "groupOnTheDevice": MessageLookupByLibrary.simpleMessage(
      "Done on the device, not here",
    ),
    "groupRemove": MessageLookupByLibrary.simpleMessage("Remove"),
    "groupRun": MessageLookupByLibrary.simpleMessage("Run"),
    "groupVersion": MessageLookupByLibrary.simpleMessage("Version"),
    "groupWork": MessageLookupByLibrary.simpleMessage("Work with it"),
    "groupYouControl": MessageLookupByLibrary.simpleMessage(
      "What you control here",
    ),
    "historianKeep": m29,
    "historianSeries": m30,
    "historianSize": m31,
    "historyFooter": MessageLookupByLibrary.simpleMessage(
      "Sync links read the historian\'s change journal, so nothing is lost while a database is down.",
    ),
    "historyOf": m32,
    "holdUnknown": MessageLookupByLibrary.simpleMessage(
      "Hold unknown connections here",
    ),
    "holdUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Off (with Allow all links off too): unknown certificates are ignored.",
    ),
    "howItRunsThere": MessageLookupByLibrary.simpleMessage("How it runs there"),
    "importPoints": MessageLookupByLibrary.simpleMessage(
      "Import CSV or DSA tree",
    ),
    "inputsCount": m33,
    "insAction": MessageLookupByLibrary.simpleMessage("Action"),
    "insConnection": MessageLookupByLibrary.simpleMessage("Connection"),
    "insDevice": MessageLookupByLibrary.simpleMessage("Device"),
    "insLink": MessageLookupByLibrary.simpleMessage("Link"),
    "insNode": MessageLookupByLibrary.simpleMessage("Node"),
    "insPoint": MessageLookupByLibrary.simpleMessage("Point"),
    "install": MessageLookupByLibrary.simpleMessage("Install"),
    "installRailNote": MessageLookupByLibrary.simpleMessage(
      "Installing needs config on sys (the admin role). Nothing is installed before you press Install.",
    ),
    "installedOn": m34,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Not a gateway URL (http:// or https:// and a host)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Issue"),
    "keyCopied": MessageLookupByLibrary.simpleMessage("Key copied"),
    "keysCopied": m35,
    "kindAction": MessageLookupByLibrary.simpleMessage("Action"),
    "kindConnection": MessageLookupByLibrary.simpleMessage("connection"),
    "kindDevice": MessageLookupByLibrary.simpleMessage("device"),
    "kindFlow": MessageLookupByLibrary.simpleMessage("Flow"),
    "kindLink": MessageLookupByLibrary.simpleMessage("link"),
    "kindLogic": MessageLookupByLibrary.simpleMessage("Logic block"),
    "kindNode": MessageLookupByLibrary.simpleMessage("node"),
    "kindSink": MessageLookupByLibrary.simpleMessage("Sink"),
    "kindTreeNode": MessageLookupByLibrary.simpleMessage("Tree node"),
    "lag": m36,
    "lastRead": m37,
    "legendConnected": MessageLookupByLibrary.simpleMessage("connected"),
    "legendFree": MessageLookupByLibrary.simpleMessage("free field"),
    "legendOffline": MessageLookupByLibrary.simpleMessage("offline"),
    "legendPlatform": MessageLookupByLibrary.simpleMessage("platform"),
    "legendReadOnly": MessageLookupByLibrary.simpleMessage(
      "no left port = read-only point",
    ),
    "legendReads": MessageLookupByLibrary.simpleMessage("reads a value"),
    "legendWaiting": MessageLookupByLibrary.simpleMessage(
      "waiting in quarantine",
    ),
    "legendWrites": MessageLookupByLibrary.simpleMessage("writes to a device"),
    "letItIn": MessageLookupByLibrary.simpleMessage("Let it in"),
    "letOthersIn": MessageLookupByLibrary.simpleMessage("Let others in"),
    "letTheBrokerIn": MessageLookupByLibrary.simpleMessage("Let the broker in"),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Light theme"),
    "linkName": MessageLookupByLibrary.simpleMessage("Link name"),
    "linkOverTls": MessageLookupByLibrary.simpleMessage("link · over tls"),
    "linksAlready": m38,
    "linksLocalNote": m39,
    "linksOn": m40,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "Connections with a certificate from this site that no link is set up for. They can read and write nothing until you approve them.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "They run on their own machines and connect with a certificate from this site. You decide what they may reach and whether they may stay; the device itself is updated where it runs.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.",
    ),
    "liveRefused": MessageLookupByLibrary.simpleMessage(
      "You cannot read every source and target of this flow",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Loading…"),
    "logEmpty": MessageLookupByLibrary.simpleMessage("No lines."),
    "logIn": MessageLookupByLibrary.simpleMessage("Log in"),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Sign in to a WYRM gateway.",
    ),
    "logOf": m41,
    "logOut": MessageLookupByLibrary.simpleMessage("Log out"),
    "mAclDenials": MessageLookupByLibrary.simpleMessage("ACL denials"),
    "mAuditRecords": MessageLookupByLibrary.simpleMessage("Audit records"),
    "mFreeDisk": MessageLookupByLibrary.simpleMessage("Free disk"),
    "mInQuarantine": MessageLookupByLibrary.simpleMessage("In quarantine"),
    "mLinksConnected": MessageLookupByLibrary.simpleMessage("Links connected"),
    "mMemory": MessageLookupByLibrary.simpleMessage("Memory"),
    "mSessions": MessageLookupByLibrary.simpleMessage("Sessions"),
    "mStandby": MessageLookupByLibrary.simpleMessage("Standby"),
    "mUpDown": MessageLookupByLibrary.simpleMessage("Upstreams / below"),
    "manifest": MessageLookupByLibrary.simpleMessage("Manifest"),
    "mayDoNote": MessageLookupByLibrary.simpleMessage(
      "These are the agent link\'s own settings. Change them in Links › Edit params.",
    ),
    "menuOther": MessageLookupByLibrary.simpleMessage("Other"),
    "menuSubtitle": m42,
    "messagesPerSecond": MessageLookupByLibrary.simpleMessage(
      "Router messages per second",
    ),
    "modeEmbedded": MessageLookupByLibrary.simpleMessage("Embedded"),
    "modeEmbeddedNote": MessageLookupByLibrary.simpleMessage(
      "Inside the broker: the lightest; it stops when the broker stops.",
    ),
    "modeExternal": MessageLookupByLibrary.simpleMessage("External"),
    "modeExternalNote": MessageLookupByLibrary.simpleMessage(
      "On another machine: it connects with a certificate from this site.",
    ),
    "modeProcess": MessageLookupByLibrary.simpleMessage("Process"),
    "modeProcessNote": MessageLookupByLibrary.simpleMessage(
      "Its own process on this host, watched and restarted by the broker.",
    ),
    "modeWasmNote": MessageLookupByLibrary.simpleMessage(
      "Inside the broker, in the sandbox: no files, only the network it is allowed, memory and time limits. Set by the package kind.",
    ),
    "more": MessageLookupByLibrary.simpleMessage("More"),
    "myBlocksReason": MessageLookupByLibrary.simpleMessage(
      "Needs own blocks in the engine",
    ),
    "nSelected": m43,
    "nameIt": MessageLookupByLibrary.simpleMessage("Give the link a name."),
    "nameRule": MessageLookupByLibrary.simpleMessage(
      "Letters, digits, . _ - · not used by another link, a removed link or a site",
    ),
    "nameTaken": MessageLookupByLibrary.simpleMessage(
      "Another link has this name.",
    ),
    "needsConfigOnSys": MessageLookupByLibrary.simpleMessage(
      "Needs config on sys",
    ),
    "needsLevelYouHave": m44,
    "needsLevelYouHaveIt": m45,
    "networkError": MessageLookupByLibrary.simpleMessage("Connection problem"),
    "newCertificate": MessageLookupByLibrary.simpleMessage("new certificate"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("New dataflow"),
    "newTask": MessageLookupByLibrary.simpleMessage("New task"),
    "newValue": MessageLookupByLibrary.simpleMessage("New value"),
    "no": MessageLookupByLibrary.simpleMessage("no"),
    "noActionReason": m46,
    "noAgent": MessageLookupByLibrary.simpleMessage(
      "No assistant on this site. The assistant is the agent link: add it, give it an API key, then ask here.",
    ),
    "noAudit": MessageLookupByLibrary.simpleMessage(
      "No audit records you may read.",
    ),
    "noAuditHere": MessageLookupByLibrary.simpleMessage(
      "No records for this node in the last 500 of sys/audit.",
    ),
    "noEditReason": MessageLookupByLibrary.simpleMessage(
      "This point has no edit action.",
    ),
    "noFlows": MessageLookupByLibrary.simpleMessage(
      "No flows on this site yet.",
    ),
    "noGrants": MessageLookupByLibrary.simpleMessage("No grants you may read."),
    "noHistory": MessageLookupByLibrary.simpleMessage(
      "No recorded values in this range. A watch in sys/history records a point.",
    ),
    "noHistoryAction": MessageLookupByLibrary.simpleMessage(
      "Recording a point is set up in History (watch groups).",
    ),
    "noLocalLinks": MessageLookupByLibrary.simpleMessage(
      "No links run on this broker yet. Add a link to connect a device.",
    ),
    "noParamReason": m47,
    "noPingReason": MessageLookupByLibrary.simpleMessage(
      "This node has no ping action: the driver pings by itself (cfg ping).",
    ),
    "noPoints": MessageLookupByLibrary.simpleMessage(
      "No values here. Open a branch in the tree.",
    ),
    "noPointsYet": MessageLookupByLibrary.simpleMessage("No points yet"),
    "noProfileReason": MessageLookupByLibrary.simpleMessage(
      "The broker has no action to apply a profile to a device yet.",
    ),
    "noRemoteLinks": MessageLookupByLibrary.simpleMessage(
      "No device connects as an external link.",
    ),
    "noRevisions": MessageLookupByLibrary.simpleMessage("No revisions."),
    "noTasks": MessageLookupByLibrary.simpleMessage(
      "Ask for a change. The agent reads the tree, writes a plan and waits for your approval. Nothing changes until you approve.",
    ),
    "noUpstream": m48,
    "noUsers": MessageLookupByLibrary.simpleMessage("No users you may see."),
    "noValue": MessageLookupByLibrary.simpleMessage("no value"),
    "noWatchGroups": MessageLookupByLibrary.simpleMessage(
      "No watch groups yet. Add one to record points.",
    ),
    "noWatchPaths": MessageLookupByLibrary.simpleMessage(
      "No points in this group.",
    ),
    "none": MessageLookupByLibrary.simpleMessage("none"),
    "noneAsked": MessageLookupByLibrary.simpleMessage("none asked"),
    "notApplied": MessageLookupByLibrary.simpleMessage("not applied"),
    "notBound": MessageLookupByLibrary.simpleMessage("not bound"),
    "notDeployed": MessageLookupByLibrary.simpleMessage("not deployed"),
    "notInstalled": MessageLookupByLibrary.simpleMessage(
      "The broker did not install it.",
    ),
    "notRecorded": MessageLookupByLibrary.simpleMessage("not recorded"),
    "notWritable": MessageLookupByLibrary.simpleMessage(
      "Read only: the driver does not take a value here.",
    ),
    "noteAction": MessageLookupByLibrary.simpleMessage(
      "Dragged from the tree. Runs when run when turns true.",
    ),
    "noteTreeNode": MessageLookupByLibrary.simpleMessage(
      "A point of the tree. A read-only point has no input; binding into a writable one writes ~set.",
    ),
    "nothingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Nothing waits in quarantine.",
    ),
    "nothingStaged": MessageLookupByLibrary.simpleMessage(
      "Nothing staged. Edit a value or a parameter to stage it.",
    ),
    "nothingToDeploy": MessageLookupByLibrary.simpleMessage(
      "Nothing to deploy",
    ),
    "now": MessageLookupByLibrary.simpleMessage("now"),
    "officialList": MessageLookupByLibrary.simpleMessage("Official list"),
    "officialListNote": MessageLookupByLibrary.simpleMessage(
      "Drivers built into wyrmd and packages from your repository. Pick one, choose where it runs, install.",
    ),
    "offline": MessageLookupByLibrary.simpleMessage(
      "The gateway connection is lost. Reconnecting; values on screen are the last ones received.",
    ),
    "ok": MessageLookupByLibrary.simpleMessage("OK"),
    "onOtherDevices": MessageLookupByLibrary.simpleMessage("On other devices"),
    "onThisBroker": MessageLookupByLibrary.simpleMessage("On this broker"),
    "onWhichBroker": MessageLookupByLibrary.simpleMessage("On which broker"),
    "openInExplorer": MessageLookupByLibrary.simpleMessage("Open in Explorer"),
    "openInLinks": MessageLookupByLibrary.simpleMessage("Open in Links"),
    "openInLinksNote": MessageLookupByLibrary.simpleMessage(
      "Grants, deauthorize and remove are in Links › On other devices.",
    ),
    "openItsTree": MessageLookupByLibrary.simpleMessage("Open its tree"),
    "openItsTreeNote": m49,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Operate · runs now",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Runs on the device with your rights and is written to the audit.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("package"),
    "packageNamed": m50,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Package from your repository · SHA-256 checked against the index on download",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("Package URL (HTTPS)"),
    "paletteBlocks": MessageLookupByLibrary.simpleMessage("Blocks"),
    "paletteMyBlocks": MessageLookupByLibrary.simpleMessage("My blocks"),
    "paletteTree": MessageLookupByLibrary.simpleMessage("Tree"),
    "panelMayDo": MessageLookupByLibrary.simpleMessage("What it may do"),
    "panelThisTask": MessageLookupByLibrary.simpleMessage("This task"),
    "paramCount": m51,
    "paramsJson": m52,
    "paramsNote": MessageLookupByLibrary.simpleMessage(
      "The node\'s ~meta as the broker declares it: its profile, cfg and attr.",
    ),
    "passed": MessageLookupByLibrary.simpleMessage("passed"),
    "password": MessageLookupByLibrary.simpleMessage("Password"),
    "pickAPoint": MessageLookupByLibrary.simpleMessage(
      "Select a point in the table to see its history.",
    ),
    "pickOne": MessageLookupByLibrary.simpleMessage(
      "Pick a link from the list.",
    ),
    "ping": MessageLookupByLibrary.simpleMessage("Ping"),
    "planCard": MessageLookupByLibrary.simpleMessage("Plan"),
    "planNote": MessageLookupByLibrary.simpleMessage(
      "The plan is in the task\'s record. Studio shows it when the gateway can read documents (docs/studio.md §10 item 11). Read it with wyrm-agent for now.",
    ),
    "platform": MessageLookupByLibrary.simpleMessage("Platform"),
    "platformNote": MessageLookupByLibrary.simpleMessage(
      "Its settings and counters are under downstream/uplink.",
    ),
    "pleaseCheckYourNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Please check your network settings.",
    ),
    "pleaseLogInAgain": MessageLookupByLibrary.simpleMessage(
      "Please log in again.",
    ),
    "pointsCount": m53,
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Values update live. Edits are staged in this session; nothing is written to the device until you apply.",
    ),
    "problems": MessageLookupByLibrary.simpleMessage("Problems"),
    "purgeHistory": MessageLookupByLibrary.simpleMessage("Purge a time range"),
    "purgeHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Deletes the recorded rows of a range, for every point.",
    ),
    "qCheckFailed": MessageLookupByLibrary.simpleMessage(
      "The package did not pass",
    ),
    "qCheckOk": MessageLookupByLibrary.simpleMessage("The package looks right"),
    "qChoose": MessageLookupByLibrary.simpleMessage("What do you want to add?"),
    "qFailed": MessageLookupByLibrary.simpleMessage(
      "The broker did not install it",
    ),
    "qInstalled": m54,
    "qInstalling": m55,
    "qRun": MessageLookupByLibrary.simpleMessage(
      "Where should it run, and under what name?",
    ),
    "quarantine": MessageLookupByLibrary.simpleMessage("Quarantine"),
    "quarantineAndAdmission": MessageLookupByLibrary.simpleMessage(
      "Quarantine and admission",
    ),
    "quarantineAndAdmissionNote": MessageLookupByLibrary.simpleMessage(
      "Unknown certificates wait in Links › Quarantine.",
    ),
    "readsNote": MessageLookupByLibrary.simpleMessage(
      "Reading needs no approval. What it reads stays inside your rights and its own.",
    ),
    "recordInHistory": MessageLookupByLibrary.simpleMessage(
      "Record in history…",
    ),
    "recorded": MessageLookupByLibrary.simpleMessage("recorded"),
    "refresh": MessageLookupByLibrary.simpleMessage("Refresh"),
    "reject": MessageLookupByLibrary.simpleMessage("Reject"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "This certificate is refused from now on.",
    ),
    "rejectTitle": m56,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Nothing to do from here: it came in with its relay. Deauthorize the relay to cut it off.",
    ),
    "relaysSites": m57,
    "remoteFooter": MessageLookupByLibrary.simpleMessage(
      "If the device is lost or stolen: Remove for good. Deauthorize is the pause: approve it again from quarantine and it keeps its name and tree.",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Remove"),
    "removeBlock": MessageLookupByLibrary.simpleMessage("Remove block"),
    "removeDeletesTree": MessageLookupByLibrary.simpleMessage(
      "It stops, and its tree is deleted. The name can be used again.",
    ),
    "removeEllipsis": MessageLookupByLibrary.simpleMessage("Remove…"),
    "removeGroup": MessageLookupByLibrary.simpleMessage("Remove the group"),
    "removeGroupNote": MessageLookupByLibrary.simpleMessage(
      "It stops recording; its rows stay unless you purge them.",
    ),
    "removeInput": MessageLookupByLibrary.simpleMessage(
      "Remove the last input",
    ),
    "removeLinkTitle": m58,
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "It stops, its tree is deleted, and its id is retired: it cannot be used again.",
    ),
    "removeUser": MessageLookupByLibrary.simpleMessage("Remove user"),
    "removeUserNote": MessageLookupByLibrary.simpleMessage(
      "They cannot log in again; their sessions end.",
    ),
    "removeUserTitle": m59,
    "requiredField": MessageLookupByLibrary.simpleMessage("Required field"),
    "resultOf": m60,
    "returns": m61,
    "review": MessageLookupByLibrary.simpleMessage("Review"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage("Review and apply"),
    "reviewNote": m62,
    "revision": m63,
    "revisionNow": m64,
    "rightsLine": m65,
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Without this the broker installs nothing. Grants change later with Grant access; other values with the link\'s params.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "The package asks for these rights",
    ),
    "rollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Its parameters become a new revision and the link restarts with them.",
    ),
    "rollBackTo": m66,
    "rowsAnswered": m67,
    "runNow": MessageLookupByLibrary.simpleMessage("Run now"),
    "runNowNote": m68,
    "running": MessageLookupByLibrary.simpleMessage("Running"),
    "runningNote": MessageLookupByLibrary.simpleMessage(
      "The agent works on it. Cancel stops it; what was done stays done.",
    ),
    "runsOn": m69,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Runs on another device",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Same call from the CLI",
    ),
    "searchHint": MessageLookupByLibrary.simpleMessage(
      "Go to a node, action or link",
    ),
    "searchLinks": MessageLookupByLibrary.simpleMessage("Search the list"),
    "secAttributes": MessageLookupByLibrary.simpleMessage("Attributes"),
    "secDiagnostics": MessageLookupByLibrary.simpleMessage("Diagnostics"),
    "secParameters": MessageLookupByLibrary.simpleMessage("Parameters"),
    "secPolling": MessageLookupByLibrary.simpleMessage("Polling"),
    "secPublish": MessageLookupByLibrary.simpleMessage(
      "What the tree will publish",
    ),
    "secRegister": MessageLookupByLibrary.simpleMessage("Register"),
    "secValue": MessageLookupByLibrary.simpleMessage("Value"),
    "secWrite": MessageLookupByLibrary.simpleMessage("Write"),
    "secretName": MessageLookupByLibrary.simpleMessage("Name"),
    "secretValue": MessageLookupByLibrary.simpleMessage(
      "Value (empty deletes it)",
    ),
    "secretsNote": MessageLookupByLibrary.simpleMessage(
      "A secret is sealed by the broker and never shown again; the link reads it by name.",
    ),
    "sectionEarlier": MessageLookupByLibrary.simpleMessage("Earlier"),
    "sectionNow": MessageLookupByLibrary.simpleMessage("Now"),
    "seeLinks": MessageLookupByLibrary.simpleMessage("see Links"),
    "selectANode": MessageLookupByLibrary.simpleMessage(
      "Select a node in the tree.",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Session expired"),
    "setLogLevel": m70,
    "setLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Takes effect at once, no restart. Staged with your other edits.",
    ),
    "setPassword": MessageLookupByLibrary.simpleMessage("Set password"),
    "setPasswordNote": MessageLookupByLibrary.simpleMessage(
      "Their open sessions stay until they expire.",
    ),
    "setPoll": MessageLookupByLibrary.simpleMessage("Set poll…"),
    "setRoles": MessageLookupByLibrary.simpleMessage("Set roles"),
    "setRolesNote": MessageLookupByLibrary.simpleMessage(
      "Roles decide what the user reaches (see Grants).",
    ),
    "setSecret": MessageLookupByLibrary.simpleMessage("Set"),
    "setValue": MessageLookupByLibrary.simpleMessage("Set value"),
    "siteRelayedBelow": MessageLookupByLibrary.simpleMessage(
      "Site relayed below",
    ),
    "sitesAround": m71,
    "sitesSubtitle": m72,
    "somethingWentWrong": MessageLookupByLibrary.simpleMessage(
      "Something went wrong",
    ),
    "stage": MessageLookupByLibrary.simpleMessage("Stage"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "Stage puts it into Review and apply with your other edits.",
    ),
    "stagedChanges": m73,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Nothing is written until you apply. Each change runs with your own rights.",
    ),
    "stagedWas": m74,
    "stale": MessageLookupByLibrary.simpleMessage("stale"),
    "stateConnected": MessageLookupByLibrary.simpleMessage("Connected"),
    "stateFailed": MessageLookupByLibrary.simpleMessage("Failed"),
    "stateInstalled": MessageLookupByLibrary.simpleMessage("Installed"),
    "stateOffline": MessageLookupByLibrary.simpleMessage("Offline"),
    "stateStarting": MessageLookupByLibrary.simpleMessage("Starting"),
    "stateStopped": MessageLookupByLibrary.simpleMessage("Stopped"),
    "stateStopping": MessageLookupByLibrary.simpleMessage("Stopping"),
    "stateWaiting": MessageLookupByLibrary.simpleMessage("Waiting"),
    "stepBring": MessageLookupByLibrary.simpleMessage("Bring"),
    "stepCheck": MessageLookupByLibrary.simpleMessage("Check"),
    "stepChoose": MessageLookupByLibrary.simpleMessage("Choose"),
    "stepInstall": MessageLookupByLibrary.simpleMessage("Install"),
    "stepOf": m75,
    "stepWhere": MessageLookupByLibrary.simpleMessage("Where it runs"),
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio is signed in here",
    ),
    "sysAdminOnly": MessageLookupByLibrary.simpleMessage("sys/**, admin only"),
    "systemFooter": MessageLookupByLibrary.simpleMessage(
      "wyrmd.json5 states the intent at first start; everything changed here since lives in its write-ahead log.",
    ),
    "tabActions": MessageLookupByLibrary.simpleMessage("Actions"),
    "tabAudit": MessageLookupByLibrary.simpleMessage("Audit"),
    "tabGrants": MessageLookupByLibrary.simpleMessage("Grants"),
    "tabHistory": MessageLookupByLibrary.simpleMessage("History"),
    "tabParameters": MessageLookupByLibrary.simpleMessage("Parameters"),
    "tabPoints": MessageLookupByLibrary.simpleMessage("Points"),
    "tabUsers": MessageLookupByLibrary.simpleMessage("Users"),
    "tagNeeds": m76,
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("runs now"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("staged"),
    "taskAwaiting": MessageLookupByLibrary.simpleMessage("awaiting approval"),
    "taskDone": MessageLookupByLibrary.simpleMessage("done"),
    "taskFailed": MessageLookupByLibrary.simpleMessage("failed or stopped"),
    "taskListNote": m77,
    "taskPlanning": MessageLookupByLibrary.simpleMessage("planning"),
    "taskRunning": MessageLookupByLibrary.simpleMessage("running"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("this broker"),
    "toAccept": MessageLookupByLibrary.simpleMessage("to accept"),
    "tokenForBelow": MessageLookupByLibrary.simpleMessage(
      "Token for a site below",
    ),
    "tokenHours": MessageLookupByLibrary.simpleMessage("Valid for hours"),
    "tokenNote": MessageLookupByLibrary.simpleMessage(
      "One token admits a broker at once. It is shown once; set its uses and hours.",
    ),
    "tokenUses": MessageLookupByLibrary.simpleMessage("Uses"),
    "treeAction": MessageLookupByLibrary.simpleMessage("Action"),
    "treeActionNote": MessageLookupByLibrary.simpleMessage(
      "a block that runs it when run when turns true; its arguments are fields.",
    ),
    "treeNoteLead": MessageLookupByLibrary.simpleMessage(
      "The tree shows data only.",
    ),
    "treeNoteMiddle": MessageLookupByLibrary.simpleMessage("is edited in"),
    "treeOf": m78,
    "treePoint": MessageLookupByLibrary.simpleMessage("Point"),
    "treePointNote": MessageLookupByLibrary.simpleMessage(
      "on a block: adds it as a field. On the canvas: a new block of that node.",
    ),
    "tryAgainLater": MessageLookupByLibrary.simpleMessage(
      "Please try again later.",
    ),
    "unbind": MessageLookupByLibrary.simpleMessage("Unbind"),
    "unitNumber": m79,
    "unsubscribeNote": MessageLookupByLibrary.simpleMessage(
      "The point stops being recorded; its rows stay.",
    ),
    "upFor": m80,
    "upstream": MessageLookupByLibrary.simpleMessage("upstream"),
    "upstreamBroker": MessageLookupByLibrary.simpleMessage("Upstream broker"),
    "upstreamFooter": MessageLookupByLibrary.simpleMessage(
      "An upstream configured in wyrmd.json5 is changed there; one added here is removed with sys/upstream/<name> ▸ Remove.",
    ),
    "user": MessageLookupByLibrary.simpleMessage("User"),
    "userActive": MessageLookupByLibrary.simpleMessage("Active"),
    "userDisabled": MessageLookupByLibrary.simpleMessage("Disabled"),
    "validate": MessageLookupByLibrary.simpleMessage("Validate"),
    "valueCopied": MessageLookupByLibrary.simpleMessage("Value copied"),
    "versionDeployed": m81,
    "viaSite": m82,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Waiting in quarantine",
    ),
    "waitingToBeLetIn": m83,
    "wasValue": m84,
    "wasWord": MessageLookupByLibrary.simpleMessage("was"),
    "watchGroup": MessageLookupByLibrary.simpleMessage("Watch group"),
    "watchGroups": m85,
    "whatItRead": MessageLookupByLibrary.simpleMessage("What it read"),
    "whyBring": MessageLookupByLibrary.simpleMessage(
      "Bring your own package only when it is not in the official list. A zip, a URL or a Git repository with a built package, or one component.",
    ),
    "whyBroker": MessageLookupByLibrary.simpleMessage("Broker"),
    "whyCheck": MessageLookupByLibrary.simpleMessage(
      "Before anything is installed, the archive and what is in it are checked: size, paths, the manifest and its fields, the protocol version, which hosts it has binaries for.",
    ),
    "whyChoose": MessageLookupByLibrary.simpleMessage(
      "Most links come from the official list: a driver built into wyrmd or a package from your repository. Bring your own package only when it is not there.",
    ),
    "whyDeauthorized": MessageLookupByLibrary.simpleMessage("Deauthorized"),
    "whyFailed": MessageLookupByLibrary.simpleMessage(
      "The broker answered success: false. Its message tells why.",
    ),
    "whyInstalled": MessageLookupByLibrary.simpleMessage(
      "It runs, has its own identity and has declared its branch.",
    ),
    "whyInstalling": MessageLookupByLibrary.simpleMessage(
      "This takes a few seconds. You can leave; it continues.",
    ),
    "whyNew": MessageLookupByLibrary.simpleMessage("New"),
    "whyRunCustom": MessageLookupByLibrary.simpleMessage(
      "Choose the broker. Only brokers whose host the package was built for can take it; how it runs is set by the package kind.",
    ),
    "whyRunOfficial": MessageLookupByLibrary.simpleMessage(
      "Choose the broker, then how the link runs on it. A built-in driver can run inside the broker, as its own process or on another machine.",
    ),
    "wordOrderReason": MessageLookupByLibrary.simpleMessage(
      "Set by the data type: its _wswap, _bswap or _wbswap suffix.",
    ),
    "writableNeeds": m86,
    "wsAccess": MessageLookupByLibrary.simpleMessage("Access"),
    "wsAssistant": MessageLookupByLibrary.simpleMessage("Assistant"),
    "wsExplorer": MessageLookupByLibrary.simpleMessage("Explorer"),
    "wsFlows": MessageLookupByLibrary.simpleMessage("Flows"),
    "wsHistory": MessageLookupByLibrary.simpleMessage("History"),
    "wsLinks": MessageLookupByLibrary.simpleMessage("Links"),
    "wsSites": MessageLookupByLibrary.simpleMessage("Sites"),
    "wsSystem": MessageLookupByLibrary.simpleMessage("System"),
    "wyrmdOn": m87,
    "yes": MessageLookupByLibrary.simpleMessage("yes"),
    "youTag": MessageLookupByLibrary.simpleMessage("YOU"),
    "yourAnswers": MessageLookupByLibrary.simpleMessage("Your answers"),
    "yourAnswersNote": MessageLookupByLibrary.simpleMessage(
      "Your answers. Click a step on the left to change one.",
    ),
    "yourUpstream": MessageLookupByLibrary.simpleMessage("your upstream"),
    "zipFile": MessageLookupByLibrary.simpleMessage("Zip file"),
  };
}
