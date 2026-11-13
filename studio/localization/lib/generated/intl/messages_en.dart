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

  static String m1(version) => "Update to ${version}";

  static String m2(n) => "${n} in";

  static String m3(n) => "${n} d ago";

  static String m4(n) => "${n} h ago";

  static String m5(n) => "${n} min ago";

  static String m6(count) =>
      "${Intl.plural(count, one: 'Apply 1 change', other: 'Apply ${count} changes')}";

  static String m7(count) => "Ask an admin for ${count}";

  static String m8(n) => "asks to join · relays ${n}";

  static String m9(sites) => "asks to relay: ${sites}";

  static String m10(code) => "refused (${code})";

  static String m11(n) =>
      "${Intl.plural(n, one: '1 block', other: '${n} blocks')}";

  static String m12(brokers, devices) =>
      "${brokers} brokers · ${devices} devices";

  static String m13(driver) => "built-in driver ${driver}";

  static String m14(site) => "CA-signed · ${site} CA";

  static String m15(n) =>
      "${Intl.plural(n, one: '1 block becomes', other: '${n} blocks become')} one block of this flow. Wires that cross its edge become its inputs and outputs.";

  static String m16(count) =>
      "${Intl.plural(count, zero: 'no children', one: '1 child', other: '${count} children')}";

  static String m17(site) =>
      "${site} dials out to it; it authorizes ${site} there.";

  static String m18(size) => "data_dir ${size}";

  static String m19(id) => "Deauthorize ${id}?";

  static String m20(flow) =>
      "The draft of “${flow}” replaces the version that runs now.";

  static String m21(who) => "deployed by ${who}";

  static String m22(device) =>
      "It runs on ${device}; the broker cannot start or stop it.";

  static String m23(id) => "Edit params of ${id}";

  static String m24(time) =>
      "The broker log around ${time} has the rest of the story.";

  static String m25(field) =>
      "Back in the form, the field ${field} is marked; correct it and send again.";

  static String m26(role, site) =>
      "Your role is ${role}. Nothing was changed on ${site}.";

  static String m27(call, key) => "${call} on ${key}";

  static String m28(type) => "studio · ${type}";

  static String m29(thing) => "deploy ${thing}";

  static String m30(thing) => "install ${thing}";

  static String m31(thing) => "list ${thing}";

  static String m32(thing) => "log in to ${thing}";

  static String m33(thing) => "open ${thing}";

  static String m34(thing) => "read ${thing}";

  static String m35(thing) => "remove ${thing}";

  static String m36(call, thing) => "run ${call} on ${thing}";

  static String m37(thing) => "save ${thing}";

  static String m38(thing) => "start ${thing}";

  static String m39(step) => "finish “${step}”";

  static String m40(thing) => "stop ${thing}";

  static String m41(thing) => "write ${thing}";

  static String m42(thing) => "Deploying ${thing}";

  static String m43(thing) => "Installing ${thing}";

  static String m44(thing) => "Listing ${thing}";

  static String m45(thing) => "Logging in to ${thing}";

  static String m46(thing) => "Opening ${thing}";

  static String m47(thing) => "Reading ${thing}";

  static String m48(thing) => "Removing ${thing}";

  static String m49(call, thing) => "${call} on ${thing}";

  static String m50(thing) => "Saving ${thing}";

  static String m51(thing) => "Starting ${thing}";

  static String m52(thing) => "Stopping ${thing}";

  static String m53(thing) => "Writing ${thing}";

  static String m54(call) => "${call}";

  static String m55(site) => "No answer from the broker at ${site}.";

  static String m56(status) =>
      "The broker answered ${status} and sent no message.";

  static String m57(status, message) => "${status}: ${message}";

  static String m58(time) => "${time} (local)";

  static String m59(doing, site) => "${doing} failed on ${site}";

  static String m60(doing) => "${doing} failed";

  static String m61(site, what) => "${site} is busy, ${what} did not start";

  static String m62(thing) => "${thing} is not there anymore";

  static String m63(thing) => "History of ${thing} unavailable";

  static String m64(site) => "${site} did not answer";

  static String m65(thing) => "Reading ${thing} failed";

  static String m66(what) => "You can’t ${what}";

  static String m67(site) => "Live values from ${site} stopped";

  static String m68(what) => "Studio could not ${what}";

  static String m69(thing, call) => "${thing} does not support ${call}";

  static String m70(seconds) => "Try again in ${seconds} s";

  static String m71(user, role) => "${user} (${role})";

  static String m72(s) => "every ${s} s";

  static String m73(reason) =>
      "The unreadable file could not be moved aside: ${reason}";

  static String m74(name) =>
      "Fresh settings keep the unreadable file beside the new one as ${name}. You add your gateways and log in again.";

  static String m75(panel) => "Studio could not draw ${panel}";

  static String m76(panel) => "The ${panel} could not be drawn";

  static String m77(when) => "first seen ${when}";

  static String m78(v) => "v${v} deployed";

  static String m79(v) => "v${v} · error";

  static String m80(v) => "v${v} stopped";

  static String m81(v) => "Version ${v}";

  static String m82(site) => "Flows on ${site}";

  static String m83(count) => "${count} blocks";

  static String m84(label) => "Unpin “${label}” from block";

  static String m85(address) => "from ${address}";

  static String m86(host, ms) => "${host} · answered in ${ms} ms";

  static String m87(host) => "No answer from ${host}";

  static String m88(key) => "Go to ${key}";

  static String m89(id) => "Grant access to ${id}";

  static String m90(days) => "raw kept ${days} d";

  static String m91(n) => "${n} series";

  static String m92(size) => "Historian ${size}";

  static String m93(id) => "Params history of ${id}";

  static String m94(status) =>
      "Reading the history failed: ${status}. Details in Problems.";

  static String m95(n) =>
      "${Intl.plural(n, one: '1 input', other: '${n} inputs')}";

  static String m96(name, broker) => "${name} is installed on ${broker}.";

  static String m97(n) =>
      "${Intl.plural(n, zero: 'no instance in this flow', one: '1 instance in this flow', other: '${n} instances in this flow')} · a change here changes them all";

  static String m98(count) => "${count} keys copied";

  static String m99(lag) => "lag ${lag}";

  static String m100(time) => "last read ${time}";

  static String m101(n) =>
      "${Intl.plural(n, one: '1 link already', other: '${n} links already')}";

  static String m102(n) =>
      "${Intl.plural(n, one: '1 link', other: '${n} links')}";

  static String m103(site) =>
      "Started and watched by ${site}: built-in drivers and installed packages. You can stop, change, upgrade and remove them.";

  static String m104(site) => "Links on ${site}";

  static String m105(first, last) => "${first} and ${last}";

  static String m106(status) =>
      "Reading the list of children failed: ${status}. Details in Problems.";

  static String m107(id) => "Log of ${id}";

  static String m108(n) =>
      "${Intl.plural(n, one: '1 instance uses it', other: '${n} instances use it')}";

  static String m109(n) => "library v${n}";

  static String m110(n) => "${n} used";

  static String m111(n) => "v${n}";

  static String m112(kind, count) => "${kind} · ${count} actions";

  static String m113(status) =>
      "Reading the description failed: ${status}. Details in Problems.";

  static String m114(count) =>
      "${Intl.plural(count, one: '… 1 more byte', other: '… ${count} more bytes')}";

  static String m115(count) =>
      "${Intl.plural(count, one: '1 more line', other: '${count} more lines')}";

  static String m116(count) => "${count} selected";

  static String m117(level, have) => "Needs ${level} · you have ${have}";

  static String m118(level) => "Needs ${level} · you have it";

  static String m119(action) => "This node has no ${action} action.";

  static String m120(param) => "The driver has no ${param} parameter.";

  static String m121(site) => "none: ${site} is the top";

  static String m122(site) => "Explorer shows wy/${site}.";

  static String m123(site) => "Opening the tree of ${site}…";

  static String m124(name) => "package ${name}";

  static String m125(n) =>
      "${Intl.plural(n, one: '1 case', other: '${n} cases')}";

  static String m126(n) =>
      "${Intl.plural(n, zero: 'no parameters', one: '1 parameter', other: '${n} parameters')}";

  static String m127(rev) => "Parameters (revision ${rev}, JSON)";

  static String m128(detail) => "Not JSON: ${detail}";

  static String m129(n) =>
      "${Intl.plural(n, one: '1 point', other: '${n} points')}";

  static String m130(n) =>
      "${Intl.plural(n, one: '1 port', other: '${n} ports')}";

  static String m131(step) => "${step} · later";

  static String m132(site) => "Reading the tree of ${site}";

  static String m133(message) => "The draft does not run: ${message}";

  static String m134(count) =>
      "${Intl.plural(count, one: '1 problem', other: '${count} problems')}";

  static String m135(name) => "${name} is installed";

  static String m136(name) => "Installing ${name}…";

  static String m137(sites) => "reaches ${sites}";

  static String m138(status) =>
      "Reading the value failed: ${status}. Details in Problems.";

  static String m139(field) =>
      "This broker cannot bind ${field} (its flow engine is older than ADR 0040)";

  static String m140(field) => "${field} takes no input: type its value";

  static String m141(from, to) => "${from} does not fit ${to}";

  static String m142(cn) => "Reject ${cn}?";

  static String m143(n) =>
      "${Intl.plural(n, one: 'relays 1 site', other: 'relays ${n} sites')}";

  static String m144(id) => "Remove ${id}?";

  static String m145(name) => "Remove ${name}?";

  static String m146(action) => "Result · ${action}";

  static String m147(what) => "returns ${what}";

  static String m148(audit) =>
      "Each write is checked by the link and recorded in ${audit}. A value shows only after it is read back.";

  static String m149(rev) => "Revision ${rev}";

  static String m150(rev) => "Revision ${rev} · in use";

  static String m151(site, user, role, level) =>
      "Site ${site} · applied with your rights: ${user}, ${role} (${level})";

  static String m152(role, site) => "${role} on ${site}";

  static String m153(rev) => "Roll back to revision ${rev}?";

  static String m154(n) =>
      "${Intl.plural(n, one: '1 row', other: '${n} rows')}";

  static String m155(user) =>
      "Runs as ${user}. Nothing else in the tree changes unless the result is used.";

  static String m156(site) => "Runs on ${site}";

  static String m157(name) => "${name}";

  static String m158(level) => "Log level ${level}";

  static String m159(site) => "Sites around ${site}";

  static String m160(site) =>
      "What ${site} connects to and what connects to it: brokers above and below, platforms it sends to, and devices whose links run outside any broker.";

  static String m161(count) =>
      "${Intl.plural(count, one: '1 byte', other: '${count} bytes')}";

  static String m162(count) =>
      "${Intl.plural(count, one: '1 char', other: '${count} chars')}";

  static String m163(count) =>
      "${Intl.plural(count, one: '1 column', other: '${count} columns')}";

  static String m164(count) =>
      "${Intl.plural(count, one: '1 item', other: '${count} items')}";

  static String m165(count) =>
      "${Intl.plural(count, one: '1 key', other: '${count} keys')}";

  static String m166(count) =>
      "${Intl.plural(count, one: '1 line', other: '${count} lines')}";

  static String m167(count) =>
      "${Intl.plural(count, one: '1 row', other: '${count} rows')}";

  static String m168(count) =>
      "${Intl.plural(count, zero: 'No staged changes', one: '1 staged change', other: '${count} staged changes')}";

  static String m169(was) => "staged · was ${was}";

  static String m170(host) => "Standby: ${host}";

  static String m171(n, total) => "Step ${n} of ${total}";

  static String m172(host) => "Reaching ${host}";

  static String m173(version, os) => "${version} (${os})";

  static String m174(version, language) => "Studio ${version} · ${language}";

  static String m175(n) => "ACL denials grew by ${n}";

  static String m176(from) =>
      "acl_denied was ${from} when this screen was last shown";

  static String m177(n) => "Standby is ${n} records behind";

  static String m178(n) => "Forks moved aside after a split: ${n}";

  static String m179(site) => "${site} waits for Authorize";

  static String m180(n) => "A downstream broker that relays sites: ${n}";

  static String m181(id) => "sys/links/${id}/state is failed; its log says why";

  static String m182(id) => "${id} failed";

  static String m183(cn) => "${cn} waits in quarantine";

  static String m184(cn) => "Unknown certificate CN ${cn}";

  static String m185(cn, t) => "Unknown certificate CN ${cn} since ${t}";

  static String m186(size) =>
      "Everything the broker owns is in its `data_dir` (here ${size}). Studio does not take backups: they hold the site\'s keys and are made on the host. The steps, ready to copy:";

  static String m187(n) =>
      "Sets of records moved aside after both brokers were active (a healed split): ${n}. The audit record `standby_forked` says which.";

  static String m188(n) =>
      "${n} registry records are not on the standby yet: a takeover now would lose them.";

  static String m189(n) => "Clear disconnected links (${n})…";

  static String m190(ids) =>
      "${ids}\n\nTheir ids are retired and cannot be used again.";

  static String m191(n) => "Clear ${n} disconnected links…";

  static String m192(ids) => "Removed: ${ids}";

  static String m193(title) => "Copy: ${title}";

  static String m194(url) => "Link to the guide copied: ${url}";

  static String m195(id) => "link: ${id}";

  static String m196(n) => "Lines copied: ${n}";

  static String m197(path) => "Saved ${path}";

  static String m198(n) =>
      "${n} lines from the broker\'s ring · newest first · `sys/~act/get_log`";

  static String m199(n, m, time) =>
      "${n} of ${m} lines within 2 min of ${time} UTC · newest first · `sys/~act/get_log`";

  static String m200(t) => "started ${t}";

  static String m201(n) => "Needs a look · ${n}";

  static String m202(m, time) =>
      "None of the newest ${m} lines is within 2 min of ${time} UTC. Ask for more lines, or clear the time.";

  static String m203(standby) =>
      "2. In `wyrmd.json5` on both hosts: `${standby}` and `peers.listen`; a lease `arbiter` on a third host is recommended.";

  static String m204(t) => "${t} · now";

  static String m205(n) => "of ${n}";

  static String m206(name) =>
      "File ${name}. A .cbor file is sent as it is; a JSON file is encoded first.";

  static String m207(name) => "Profile ${name} put";

  static String m208(name) => "Profile ${name} removed";

  static String m209(reason) =>
      "This broker does not list its profiles through the gateway (${reason}). You can still put one; it is then served at pub/<name>.";

  static String m210(name) => "Remove profile ${name}";

  static String m211(name) =>
      "The broker stops serving pub/${name} and records it in the audit journal (profile_remove).";

  static String m212(cn) => "external · CN ${cn}";

  static String m213(size) => "history ${size} · open History";

  static String m214(id) => "${id} failed · open Links";

  static String m215(site) => "${site} · open Sites";

  static String m216(cn) => "${cn} waits · open Quarantine";

  static String m217(measure, from, to) =>
      "${measure} in and out per second from ${from} to ${to}";

  static String m218(shown, total) => "${shown} of ${total} rows";

  static String m219(level) => "needs ${level}";

  static String m220(agent) => "Each task is a node: ${agent}/tasks/<id>";

  static String m221(site) => "TLS · certificate of the ${site} CA";

  static String m222(seconds) => "hides in ${seconds} s";

  static String m223(site) => "stays until ${site} is back";

  static String m224(site) => "Tree · ${site}";

  static String m225(step) => "${step} avg";

  static String m226(rollup, from, to) => "${rollup} · ${from}–${to}";

  static String m227(at, delta, key, over) =>
      "Δ from A (${at}): ${delta} ${key} over ${over}";

  static String m228(what, range) =>
      "${what}, ${range}. Use the window below to choose the range.";

  static String m229(h, m) => "${h} h ${m} min";

  static String m230(key) => "You may not read ${key}";

  static String m231(t) => "A · ${t}";

  static String m232(min, max) => "min ${min} · max ${max}";

  static String m233(m) => "${m} min";

  static String m234(t) => "raw · ${t}";

  static String m235(s) => "${s} s";

  static String m236(name) => "Show or hide ${name}";

  static String m237(n) => "${n} d";

  static String m238(n) => "${n} h";

  static String m239(n) => "${n} min";

  static String m240(unit) => "unit ${unit}";

  static String m241(d) => "up ${d}";

  static String m242(n) => "Update links: ${n}";

  static String m243(version) => "${version} stays, a link did not answer";

  static String m244(package) =>
      "Bring a zip of the package ${package} with a higher version. The broker checks it as any install and updates every link of the package.";

  static String m245(links) => "Hot start, no restart: ${links}";

  static String m246(version, when) =>
      "${version} stays installed until ${when}. A restore point is sealed for this broker and stays on it.";

  static String m247(n) => "links: ${n}";

  static String m248(n, links) => "Links that restart (${n}): ${links}";

  static String m249(link) => "Open ${link}";

  static String m250(link) => "${link} · before a restore from a backup";

  static String m251(link, version) => "${link} · ${version} · before update";

  static String m252(version, links) =>
      "These links stop and start on ${version} with the data of their restore points: ${links}. After it no version is kept: there is no second rollback.";

  static String m253(package, version) => "Roll back ${package} to ${version}?";

  static String m254(version) => "Roll back to ${version}…";

  static String m255(version) => "Rolled back to ${version}";

  static String m256(version) => "The links run ${version}";

  static String m257(links) => "${links}: back with all their nodes.";

  static String m258(state) =>
      "It changes the store format (from state ${state})";

  static String m259(state) => "Store format: same (state ${state})";

  static String m260(back, gone) =>
      "declared again: ${back} · not back yet or gone: ${gone}";

  static String m261(n) => "Custom package · links that run it: ${n}";

  static String m262(n) =>
      "Package of the repository · links that run it: ${n}";

  static String m263(package, from, to) => "Update ${package} ${from} → ${to}";

  static String m264(package, from) => "Update ${package} ${from} from a file";

  static String m265(package) => "${package} updated";

  static String m266(package) => "${package} update rolled back";

  static String m267(package) => "Updating ${package}";

  static String m268(version) => "What is new in ${version}";

  static String m269(v) => "Version ${v} · deployed";

  static String m270(site) => "via ${site}";

  static String m271(delimiter, header) =>
      "Read as the block reads it: delimiter ${delimiter}, ${header}";

  static String m272(keys) => "${keys} saves · Esc cancels";

  static String m273(keys) => "${keys} saves · Esc discards the changes";

  static String m274(n, who) => "${n} waiting to be let in: ${who}";

  static String m275(value) => "was ${value}";

  static String m276(n) => "Watch groups · ${n}";

  static String m277(user) => "Welcome, ${user}";

  static String m278(value) => "would run on ${value}";

  static String m279(value) => "would send ${value}";

  static String m280(value) => "would write ${value}";

  static String m281(level) => "Turning this on needs ${level} level";

  static String m282(site) => "wyrmd on ${site}";

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
    "actUpdateFromFile": MessageLookupByLibrary.simpleMessage(
      "Update from file…",
    ),
    "actUpdateFromFileNote": MessageLookupByLibrary.simpleMessage(
      "A custom package: bring a newer archive of it.",
    ),
    "actUpdateTo": m1,
    "actUpdateToNote": MessageLookupByLibrary.simpleMessage(
      "A newer version of its package is in the repository. Review what changes first.",
    ),
    "actUpgrade": MessageLookupByLibrary.simpleMessage("Upgrade"),
    "actUpgradeNote": MessageLookupByLibrary.simpleMessage(
      "Install a newer version of its package.",
    ),
    "actUpgradeParamsLog": MessageLookupByLibrary.simpleMessage(
      "Upgrade, params, log",
    ),
    "actVersions": MessageLookupByLibrary.simpleMessage(
      "Versions and restore points",
    ),
    "actVersionsNote": MessageLookupByLibrary.simpleMessage(
      "The last update, the restore points of this link, roll back to the kept version.",
    ),
    "actViewLog": MessageLookupByLibrary.simpleMessage("View log"),
    "actViewLogNote": MessageLookupByLibrary.simpleMessage(
      "Its last lines and its own log level.",
    ),
    "actionInputs": m2,
    "addALink": MessageLookupByLibrary.simpleMessage("Add a link"),
    "addAgent": MessageLookupByLibrary.simpleMessage("Add the agent link"),
    "addAnother": MessageLookupByLibrary.simpleMessage("Add another"),
    "addGrant": MessageLookupByLibrary.simpleMessage("Add a grant"),
    "addInput": MessageLookupByLibrary.simpleMessage("Add an input"),
    "addPair": MessageLookupByLibrary.simpleMessage("Add a case"),
    "addPoint": MessageLookupByLibrary.simpleMessage("Add point"),
    "addPort": MessageLookupByLibrary.simpleMessage("Add a port"),
    "addStandby": MessageLookupByLibrary.simpleMessage("Add a standby gateway"),
    "addUser": MessageLookupByLibrary.simpleMessage("Add a user"),
    "addWatchPath": MessageLookupByLibrary.simpleMessage("Add a point"),
    "addWatchPathNote": MessageLookupByLibrary.simpleMessage(
      "Record one more point (a key under downstream, dataflows or storage).",
    ),
    "adminsOnly": MessageLookupByLibrary.simpleMessage(
      "Users are managed by the gateway\'s administrators.",
    ),
    "agoDays": m3,
    "agoHours": m4,
    "agoMinutes": m5,
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
    "applyChanges": m6,
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
    "askAdminFor": m7,
    "askAdminReason": MessageLookupByLibrary.simpleMessage(
      "The broker has no call to send a request to an admin yet.",
    ),
    "askButton": MessageLookupByLibrary.simpleMessage("Ask"),
    "askHint": MessageLookupByLibrary.simpleMessage(
      "Ask for a change, or a question about the network (Cmd+Enter)",
    ),
    "asksToJoin": MessageLookupByLibrary.simpleMessage("asks to join"),
    "asksToJoinRelays": m8,
    "asksToRelay": m9,
    "auditDone": MessageLookupByLibrary.simpleMessage("done"),
    "auditNeeds": MessageLookupByLibrary.simpleMessage(
      "The audit needs config on sys/audit.",
    ),
    "auditRefused": m10,
    "back": MessageLookupByLibrary.simpleMessage("Back"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("Back to Links"),
    "bindHint": MessageLookupByLibrary.simpleMessage(
      "Drag an output here to bind",
    ),
    "block": MessageLookupByLibrary.simpleMessage("Block"),
    "blockForm": MessageLookupByLibrary.simpleMessage("Form"),
    "blockInputs": MessageLookupByLibrary.simpleMessage("Inputs"),
    "blockOutputs": MessageLookupByLibrary.simpleMessage("Outputs"),
    "blocksCount": m11,
    "boundMark": MessageLookupByLibrary.simpleMessage("bound"),
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
    "brokersDevices": m12,
    "builtIn": MessageLookupByLibrary.simpleMessage("built in"),
    "builtInDriver": m13,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Built into wyrmd · nothing to download",
    ),
    "caSigned": m14,
    "canDoNothing": MessageLookupByLibrary.simpleMessage(
      "nothing: no read, no write",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "cancelTask": MessageLookupByLibrary.simpleMessage("Cancel task"),
    "cannotReachGateway": MessageLookupByLibrary.simpleMessage(
      "Cannot reach the gateway",
    ),
    "cantReachGateway": MessageLookupByLibrary.simpleMessage(
      "Can’t reach this gateway",
    ),
    "catalogNote": MessageLookupByLibrary.simpleMessage(
      "Built in: in wyrmd, nothing to download. Package: from the index in packages.repository, SHA-256 checked; a broker lists only packages it can install.",
    ),
    "cbBadName": MessageLookupByLibrary.simpleMessage(
      "A name has letters, digits and _ only",
    ),
    "cbBadPort": MessageLookupByLibrary.simpleMessage(
      "A port\'s name has letters, digits and _ only",
    ),
    "cbCreate": MessageLookupByLibrary.simpleMessage("Create"),
    "cbDefault": MessageLookupByLibrary.simpleMessage("default"),
    "cbDescription": MessageLookupByLibrary.simpleMessage("Description"),
    "cbDuplicate": MessageLookupByLibrary.simpleMessage(
      "Two ports have the same name",
    ),
    "cbInputs": MessageLookupByLibrary.simpleMessage("Inputs"),
    "cbLimit": MessageLookupByLibrary.simpleMessage(
      "At most 64 blocks, and 64 inputs and 64 outputs each",
    ),
    "cbName": MessageLookupByLibrary.simpleMessage("Name"),
    "cbNone": MessageLookupByLibrary.simpleMessage("none"),
    "cbNote": m15,
    "cbOutputs": MessageLookupByLibrary.simpleMessage("Outputs"),
    "cbTaken": MessageLookupByLibrary.simpleMessage(
      "This flow already has a block of this name",
    ),
    "cbTitle": MessageLookupByLibrary.simpleMessage("Create custom block"),
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
    "checkingGateway": MessageLookupByLibrary.simpleMessage(
      "Checking the gateway",
    ),
    "childCount": m16,
    "childrenNote": MessageLookupByLibrary.simpleMessage(
      "Select a row: a node opens in the tree, a value opens in the inspector.",
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
    "colKind": MessageLookupByLibrary.simpleMessage("Kind"),
    "colLevel": MessageLookupByLibrary.simpleMessage("Level"),
    "colLink": MessageLookupByLibrary.simpleMessage("Link"),
    "colLinkDevice": MessageLookupByLibrary.simpleMessage("Link · device"),
    "colMode": MessageLookupByLibrary.simpleMessage("Mode"),
    "colName": MessageLookupByLibrary.simpleMessage("Name"),
    "colOp": MessageLookupByLibrary.simpleMessage("What"),
    "colPoint": MessageLookupByLibrary.simpleMessage("Point"),
    "colPoll": MessageLookupByLibrary.simpleMessage("Poll"),
    "colQuality": MessageLookupByLibrary.simpleMessage("Quality"),
    "colReadRows": MessageLookupByLibrary.simpleMessage("Values on the trend"),
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
    "commandNote": MessageLookupByLibrary.simpleMessage(
      "A sample on its wire presses it. Wire an event into it (a timer, a change, a point); Studio cannot press it in a running flow.",
    ),
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
    "connectNote": m17,
    "connectUpstream": MessageLookupByLibrary.simpleMessage(
      "Connect to an upstream",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("connected"),
    "continueLabel": MessageLookupByLibrary.simpleMessage("Continue"),
    "controlPlane": MessageLookupByLibrary.simpleMessage("Control plane"),
    "copiedValue": MessageLookupByLibrary.simpleMessage("Copied"),
    "copyKey": MessageLookupByLibrary.simpleMessage("Copy key"),
    "copyKeys": MessageLookupByLibrary.simpleMessage("Copy keys"),
    "copyValue": MessageLookupByLibrary.simpleMessage("Copy"),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t connect to internet.",
    ),
    "customPackage": MessageLookupByLibrary.simpleMessage("Custom package"),
    "customPackageNote": MessageLookupByLibrary.simpleMessage(
      "A package archive you bring: a zip, a URL, a Git repository or one .wasm. It is checked before install.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Dark theme"),
    "dataDir": m18,
    "dataflow": MessageLookupByLibrary.simpleMessage("Dataflow"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Its rights here are cut now and its next connection waits in quarantine. Its sites stay below it.",
    ),
    "deauthorizeTitle": m19,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Decide in Links"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "A link in quarantine is approved or rejected in Links › Quarantine.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("decide in Sites"),
    "deploy": MessageLookupByLibrary.simpleMessage("Deploy"),
    "deployAskMessage": m20,
    "deployAskTitle": MessageLookupByLibrary.simpleMessage("Deploy this flow?"),
    "deployInside": MessageLookupByLibrary.simpleMessage(
      "Go back to the flow to deploy",
    ),
    "deployedByWho": m21,
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
    "doneOnTheDevice": m22,
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
    "dropRead": MessageLookupByLibrary.simpleMessage("Read"),
    "dropWrite": MessageLookupByLibrary.simpleMessage("Write"),
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
    "editParamsOf": m23,
    "enableUser": MessageLookupByLibrary.simpleMessage("Enable"),
    "errAdviceBroker": m24,
    "errAdviceBrokerSaid": MessageLookupByLibrary.simpleMessage(
      "The call reached the broker and it answered no. Check what it names above.",
    ),
    "errAdviceBusy": MessageLookupByLibrary.simpleMessage(
      "Wait a moment and try again.",
    ),
    "errAdviceBusyAuto": MessageLookupByLibrary.simpleMessage(
      "Studio can try again by itself when the broker is ready.",
    ),
    "errAdviceGone": MessageLookupByLibrary.simpleMessage(
      "Someone removed or renamed it after this screen loaded. Refresh to see what is there now.",
    ),
    "errAdviceInput": MessageLookupByLibrary.simpleMessage(
      "Back in the form, correct the values and send again.",
    ),
    "errAdviceInputField": m25,
    "errAdviceReach": MessageLookupByLibrary.simpleMessage(
      "Try again; if it keeps failing, look at the link’s status in Links.",
    ),
    "errAdviceReachLogin": MessageLookupByLibrary.simpleMessage(
      "Log in again: Studio has no session with a gateway.",
    ),
    "errAdviceReport": MessageLookupByLibrary.simpleMessage(
      "Copy the report and send it to us: it holds no values or passwords.",
    ),
    "errAdviceRights": MessageLookupByLibrary.simpleMessage(
      "Ask an administrator for the right, or ask one to do it.",
    ),
    "errAdviceRightsRole": m26,
    "errAdviceStudio": MessageLookupByLibrary.simpleMessage(
      "Try it again; restart Studio if it keeps happening.",
    ),
    "errAdviceUnsupported": MessageLookupByLibrary.simpleMessage(
      "This broker or link does not have this call; it may be older than Studio expects.",
    ),
    "errBackToForm": MessageLookupByLibrary.simpleMessage("Back to the form"),
    "errCallOn": m27,
    "errChipStudio": m28,
    "errCopied": MessageLookupByLibrary.simpleMessage("Copied"),
    "errCopyDetails": MessageLookupByLibrary.simpleMessage("Copy details"),
    "errCopyReport": MessageLookupByLibrary.simpleMessage("Copy report"),
    "errDetails": MessageLookupByLibrary.simpleMessage("Details"),
    "errDetailsCopied": MessageLookupByLibrary.simpleMessage(
      "The details are on the clipboard.",
    ),
    "errDoDeploy": m29,
    "errDoInstall": m30,
    "errDoList": m31,
    "errDoLogIn": m32,
    "errDoOpen": m33,
    "errDoRead": m34,
    "errDoRemove": m35,
    "errDoRun": m36,
    "errDoSave": m37,
    "errDoStart": m38,
    "errDoStep": m39,
    "errDoStop": m40,
    "errDoWrite": m41,
    "errDoingDeploy": m42,
    "errDoingInstall": m43,
    "errDoingList": m44,
    "errDoingLogIn": m45,
    "errDoingOpen": m46,
    "errDoingRead": m47,
    "errDoingRemove": m48,
    "errDoingRun": m49,
    "errDoingSave": m50,
    "errDoingStart": m51,
    "errDoingStop": m52,
    "errDoingWrite": m53,
    "errFaultMessage": MessageLookupByLibrary.simpleMessage(
      "Something in Studio failed here. This is a fault in Studio, not on the broker; nothing more was sent.",
    ),
    "errNounDeploy": MessageLookupByLibrary.simpleMessage("the deploy"),
    "errNounInstall": MessageLookupByLibrary.simpleMessage("the install"),
    "errNounList": MessageLookupByLibrary.simpleMessage("the list"),
    "errNounLogIn": MessageLookupByLibrary.simpleMessage("the log-in"),
    "errNounOpen": MessageLookupByLibrary.simpleMessage("the opening"),
    "errNounRead": MessageLookupByLibrary.simpleMessage("the read"),
    "errNounRemove": MessageLookupByLibrary.simpleMessage("the removal"),
    "errNounRun": m54,
    "errNounSave": MessageLookupByLibrary.simpleMessage("the save"),
    "errNounStart": MessageLookupByLibrary.simpleMessage("the start"),
    "errNounStop": MessageLookupByLibrary.simpleMessage("the stop"),
    "errNounWrite": MessageLookupByLibrary.simpleMessage("the write"),
    "errOpenLog": MessageLookupByLibrary.simpleMessage("Open the log"),
    "errRefresh": MessageLookupByLibrary.simpleMessage("Refresh"),
    "errReportCopied": MessageLookupByLibrary.simpleMessage(
      "The report is on the clipboard.",
    ),
    "errReportNote": MessageLookupByLibrary.simpleMessage(
      "the stack trace is in the copied report only",
    ),
    "errRowAs": MessageLookupByLibrary.simpleMessage("As"),
    "errRowCall": MessageLookupByLibrary.simpleMessage("Call"),
    "errRowError": MessageLookupByLibrary.simpleMessage("Error"),
    "errRowGateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "errRowIn": MessageLookupByLibrary.simpleMessage("In"),
    "errRowReport": MessageLookupByLibrary.simpleMessage("Report"),
    "errRowScreen": MessageLookupByLibrary.simpleMessage("Screen"),
    "errRowSite": MessageLookupByLibrary.simpleMessage("Site"),
    "errRowStatus": MessageLookupByLibrary.simpleMessage("Status"),
    "errRowStudio": MessageLookupByLibrary.simpleMessage("Studio"),
    "errRowTime": MessageLookupByLibrary.simpleMessage("Time"),
    "errSaidBroker": MessageLookupByLibrary.simpleMessage("The broker said"),
    "errSaidNoAnswer": MessageLookupByLibrary.simpleMessage("Studio waited"),
    "errSaidStudio": MessageLookupByLibrary.simpleMessage("What happened"),
    "errSeeAccess": MessageLookupByLibrary.simpleMessage("See my access"),
    "errSilentReach": m55,
    "errSilentStatus": m56,
    "errStatusLine": m57,
    "errThingBroker": MessageLookupByLibrary.simpleMessage("the broker"),
    "errThingThis": MessageLookupByLibrary.simpleMessage("this"),
    "errTimeLocal": m58,
    "errTitleBroker": m59,
    "errTitleBrokerNoSite": m60,
    "errTitleBusy": m61,
    "errTitleGone": m62,
    "errTitleHistory": m63,
    "errTitleInput": MessageLookupByLibrary.simpleMessage(
      "The broker refused these parameters",
    ),
    "errTitleInputValue": MessageLookupByLibrary.simpleMessage(
      "The broker refused this value",
    ),
    "errTitleNotConnected": MessageLookupByLibrary.simpleMessage(
      "Studio is not connected to a gateway",
    ),
    "errTitlePlain": MessageLookupByLibrary.simpleMessage(
      "Studio could not finish this",
    ),
    "errTitleReach": m64,
    "errTitleReachNoSite": MessageLookupByLibrary.simpleMessage(
      "The broker did not answer",
    ),
    "errTitleRead": m65,
    "errTitleRights": m66,
    "errTitleStream": m67,
    "errTitleStudio": m68,
    "errTitleUnsupported": m69,
    "errTryAgain": MessageLookupByLibrary.simpleMessage("Try again"),
    "errTryAgainIn": m70,
    "errUserRole": m71,
    "errWhatYouCanDo": MessageLookupByLibrary.simpleMessage("What you can do"),
    "errWriteNote": MessageLookupByLibrary.simpleMessage(
      "A write that timed out may still have been applied. Check the value before you send it again.",
    ),
    "eventNone": MessageLookupByLibrary.simpleMessage("not yet"),
    "everySeconds": m72,
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
    "factRestorePoints": MessageLookupByLibrary.simpleMessage("Restore points"),
    "factRowsWritten": MessageLookupByLibrary.simpleMessage("Rows written"),
    "factRunning": MessageLookupByLibrary.simpleMessage("Running"),
    "factRunsAs": MessageLookupByLibrary.simpleMessage("Runs as"),
    "factSeen": MessageLookupByLibrary.simpleMessage("Seen"),
    "factSince": MessageLookupByLibrary.simpleMessage("Since"),
    "factStarted": MessageLookupByLibrary.simpleMessage("Started"),
    "factStatus": MessageLookupByLibrary.simpleMessage("Status"),
    "factSubject": MessageLookupByLibrary.simpleMessage("Subject"),
    "factTask": MessageLookupByLibrary.simpleMessage("Task"),
    "factTaskState": MessageLookupByLibrary.simpleMessage("State"),
    "factThrough": MessageLookupByLibrary.simpleMessage("Through"),
    "factTree": MessageLookupByLibrary.simpleMessage("Tree"),
    "factUpstreams": MessageLookupByLibrary.simpleMessage("Upstreams"),
    "factValues": MessageLookupByLibrary.simpleMessage("Values"),
    "factVersion": MessageLookupByLibrary.simpleMessage("Version"),
    "factWrites": MessageLookupByLibrary.simpleMessage("Writes"),
    "failed": MessageLookupByLibrary.simpleMessage("failed"),
    "failedNote": MessageLookupByLibrary.simpleMessage(
      "The task stopped. What was done stays done.",
    ),
    "fatalBody": MessageLookupByLibrary.simpleMessage(
      "The settings it saved on this computer are unreadable, so it cannot tell which gateways you use. Your brokers are not affected: nothing on them depends on Studio.",
    ),
    "fatalFile": MessageLookupByLibrary.simpleMessage("File"),
    "fatalFresh": MessageLookupByLibrary.simpleMessage(
      "Start with fresh settings",
    ),
    "fatalMoveFailed": m73,
    "fatalNote": m74,
    "fatalQuit": MessageLookupByLibrary.simpleMessage("Quit"),
    "fatalTitle": MessageLookupByLibrary.simpleMessage(
      "Studio could not start",
    ),
    "faultBody": MessageLookupByLibrary.simpleMessage(
      "The rest of Studio still works; values and actions elsewhere are not affected.",
    ),
    "faultDrawAgain": MessageLookupByLibrary.simpleMessage("Draw it again"),
    "faultProblem": m75,
    "faultThisPart": MessageLookupByLibrary.simpleMessage("this part"),
    "faultTitle": m76,
    "faultTitleThis": MessageLookupByLibrary.simpleMessage(
      "This part could not be drawn",
    ),
    "faultUncaught": MessageLookupByLibrary.simpleMessage(
      "Studio hit a fault in the background",
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
    "firesAtStartNote": MessageLookupByLibrary.simpleMessage(
      "This field sends its value when the flow starts, so this wire writes at every deploy.",
    ),
    "firstSeen": m77,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "The draft does not validate.",
    ),
    "flowBack": MessageLookupByLibrary.simpleMessage("Back"),
    "flowDeployed": m78,
    "flowError": m79,
    "flowName": MessageLookupByLibrary.simpleMessage("Flow id"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.",
    ),
    "flowPropertiesNote2": MessageLookupByLibrary.simpleMessage(
      "A bound field shows the value that comes in; its wire and source light when you point at it. The link icon goes to the source or unbinds.",
    ),
    "flowStopped": m80,
    "flowVersion": m81,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "A deploy needs config on dataflows; the gateway adds your proofs for each target. Viewers can open a flow and only look.",
    ),
    "flowsOn": m82,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Each flow runs in the broker. You edit a draft; nothing changes until you deploy it.",
    ),
    "fmBlocks": m83,
    "fmBound": MessageLookupByLibrary.simpleMessage("bound"),
    "fmCanvas": MessageLookupByLibrary.simpleMessage("Canvas"),
    "fmCreateCustom": MessageLookupByLibrary.simpleMessage(
      "Create custom block…",
    ),
    "fmEditCustom": MessageLookupByLibrary.simpleMessage("Edit custom block"),
    "fmFields": MessageLookupByLibrary.simpleMessage("Fields"),
    "fmFieldsTitle": MessageLookupByLibrary.simpleMessage(
      "Fields on the block",
    ),
    "fmNeedsBroker": MessageLookupByLibrary.simpleMessage(
      "This broker has no custom blocks (its flow engine is older than ADR 0040)",
    ),
    "fmNeedsEngine": MessageLookupByLibrary.simpleMessage(
      "Needs custom blocks in the engine",
    ),
    "fmNotCustom": MessageLookupByLibrary.simpleMessage("Not a custom block"),
    "fmNothingSelected": MessageLookupByLibrary.simpleMessage(
      "Select a block first",
    ),
    "fmNothingToRedo": MessageLookupByLibrary.simpleMessage("Nothing to redo"),
    "fmNothingToUndo": MessageLookupByLibrary.simpleMessage("Nothing to undo"),
    "fmUnpin": MessageLookupByLibrary.simpleMessage("Unpin from block"),
    "fmUnpinField": m84,
    "fromAddress": m85,
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "From the official list",
    ),
    "gateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "gatewayAnswered": m86,
    "gatewayNoAnswer": m87,
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("Gateway URL"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445, or several separated by commas",
    ),
    "gatewayUser": MessageLookupByLibrary.simpleMessage("Gateway user"),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git repository (HTTPS)",
    ),
    "goTo": m88,
    "goToSource": MessageLookupByLibrary.simpleMessage("Go to source"),
    "goUp": MessageLookupByLibrary.simpleMessage("Go up"),
    "grantFor": m89,
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
    "grpArguments": MessageLookupByLibrary.simpleMessage("Arguments"),
    "grpBehaviour": MessageLookupByLibrary.simpleMessage("Behaviour"),
    "grpEvents": MessageLookupByLibrary.simpleMessage("Events"),
    "grpState": MessageLookupByLibrary.simpleMessage("State"),
    "grpTarget": MessageLookupByLibrary.simpleMessage("Target"),
    "heroHeadline1": MessageLookupByLibrary.simpleMessage(
      "Every device, link and site",
    ),
    "heroHeadline2": MessageLookupByLibrary.simpleMessage(
      "in one living tree.",
    ),
    "heroLead": MessageLookupByLibrary.simpleMessage(
      "Browse what your brokers hold, add links, let devices in, connect sites and build flows. Nothing changes until you apply it.",
    ),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Hide password"),
    "historianKeep": m90,
    "historianSeries": m91,
    "historianSize": m92,
    "historyFooter": MessageLookupByLibrary.simpleMessage(
      "Sync links read the historian\'s change journal, so nothing is lost while a database is down.",
    ),
    "historyOf": m93,
    "historyUnavailable": MessageLookupByLibrary.simpleMessage(
      "history unavailable",
    ),
    "historyUnavailableTip": m94,
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
    "inputsCount": m95,
    "insAction": MessageLookupByLibrary.simpleMessage("Action"),
    "insBroker": MessageLookupByLibrary.simpleMessage("Broker"),
    "insConnection": MessageLookupByLibrary.simpleMessage("Connection"),
    "insDevice": MessageLookupByLibrary.simpleMessage("Device"),
    "insFolder": MessageLookupByLibrary.simpleMessage("Folder"),
    "insLink": MessageLookupByLibrary.simpleMessage("Link"),
    "insNode": MessageLookupByLibrary.simpleMessage("Node"),
    "insPoint": MessageLookupByLibrary.simpleMessage("Point"),
    "insStorage": MessageLookupByLibrary.simpleMessage("Storage"),
    "install": MessageLookupByLibrary.simpleMessage("Install"),
    "installRailNote": MessageLookupByLibrary.simpleMessage(
      "Installing needs config on sys (the admin role). Nothing is installed before you press Install.",
    ),
    "installedOn": m96,
    "instancesInFlow": m97,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Not a gateway URL (http:// or https:// and a host)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Issue"),
    "keyCopied": MessageLookupByLibrary.simpleMessage("Key copied"),
    "keysCopied": m98,
    "kindAction": MessageLookupByLibrary.simpleMessage("Action"),
    "kindBlockPorts": MessageLookupByLibrary.simpleMessage("Custom block"),
    "kindBroker": MessageLookupByLibrary.simpleMessage("broker"),
    "kindConnection": MessageLookupByLibrary.simpleMessage("connection"),
    "kindDataflow": MessageLookupByLibrary.simpleMessage("dataflow"),
    "kindDevice": MessageLookupByLibrary.simpleMessage("device"),
    "kindFlow": MessageLookupByLibrary.simpleMessage("Flow"),
    "kindFolder": MessageLookupByLibrary.simpleMessage("folder"),
    "kindLink": MessageLookupByLibrary.simpleMessage("link"),
    "kindLogic": MessageLookupByLibrary.simpleMessage("Logic block"),
    "kindMyBlock": MessageLookupByLibrary.simpleMessage("My block"),
    "kindNode": MessageLookupByLibrary.simpleMessage("node"),
    "kindSink": MessageLookupByLibrary.simpleMessage("Sink"),
    "kindStorage": MessageLookupByLibrary.simpleMessage("storage"),
    "kindTreeNode": MessageLookupByLibrary.simpleMessage("Tree node"),
    "lag": m99,
    "languageName": MessageLookupByLibrary.simpleMessage("English"),
    "lastRead": m100,
    "legendCommands": MessageLookupByLibrary.simpleMessage("commands"),
    "legendConnected": MessageLookupByLibrary.simpleMessage("connected"),
    "legendFree": MessageLookupByLibrary.simpleMessage("free field"),
    "legendNote": MessageLookupByLibrary.simpleMessage(
      "The animation is decoration; it stops when the system asks for less motion.",
    ),
    "legendOffline": MessageLookupByLibrary.simpleMessage("offline"),
    "legendPlatform": MessageLookupByLibrary.simpleMessage("platform"),
    "legendReadOnly": MessageLookupByLibrary.simpleMessage(
      "no left port = read-only point",
    ),
    "legendReads": MessageLookupByLibrary.simpleMessage("reads a value"),
    "legendValues": MessageLookupByLibrary.simpleMessage("values flowing"),
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
    "linksAlready": m101,
    "linksCount": m102,
    "linksLocalNote": m103,
    "linksOn": m104,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "Connections with a certificate from this site that no link is set up for. They can read and write nothing until you approve them.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "They run on their own machines and connect with a certificate from this site. You decide what they may reach and whether they may stay; the device itself is updated where it runs.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.",
    ),
    "listAnd": m105,
    "listFailedTip": m106,
    "liveRefused": MessageLookupByLibrary.simpleMessage(
      "You cannot read every source and target of this flow",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Loading…"),
    "logEmpty": MessageLookupByLibrary.simpleMessage("No lines."),
    "logIn": MessageLookupByLibrary.simpleMessage("Log in"),
    "logInLead": MessageLookupByLibrary.simpleMessage(
      "to a broker’s gateway. Your role there decides what you can change.",
    ),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Sign in to a WYRM gateway.",
    ),
    "logOf": m107,
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
    "mbBackFirst": MessageLookupByLibrary.simpleMessage(
      "Go back to the flow first",
    ),
    "mbDelete": MessageLookupByLibrary.simpleMessage("Delete"),
    "mbEdit": MessageLookupByLibrary.simpleMessage("Edit custom block"),
    "mbInUse": m108,
    "mbInsideItself": MessageLookupByLibrary.simpleMessage(
      "A block cannot contain itself",
    ),
    "mbNotInLibrary": MessageLookupByLibrary.simpleMessage(
      "The library has no block of this name",
    ),
    "mbRemoveLibrary": MessageLookupByLibrary.simpleMessage(
      "Delete from library",
    ),
    "mbRename": MessageLookupByLibrary.simpleMessage("Rename"),
    "mbSameVersion": MessageLookupByLibrary.simpleMessage(
      "The flow has the library\'s version",
    ),
    "mbSave": MessageLookupByLibrary.simpleMessage("Save to library"),
    "mbUpdate": MessageLookupByLibrary.simpleMessage("Update from library"),
    "mbUpdateTo": m109,
    "mbUsed": m110,
    "mbVersion": m111,
    "menuLanguage": MessageLookupByLibrary.simpleMessage("Language"),
    "menuOther": MessageLookupByLibrary.simpleMessage("Other"),
    "menuSubtitle": m112,
    "menuTheme": MessageLookupByLibrary.simpleMessage("Theme"),
    "messagesPerSecond": MessageLookupByLibrary.simpleMessage(
      "Router messages per second",
    ),
    "metaFailedTip": m113,
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
    "moreBytes": m114,
    "moreLines": m115,
    "myBlocksEmpty": MessageLookupByLibrary.simpleMessage(
      "No custom blocks yet. Select blocks on the canvas and choose Create custom block… in their menu.",
    ),
    "myBlocksLibrary": MessageLookupByLibrary.simpleMessage("Site library"),
    "myBlocksOff": MessageLookupByLibrary.simpleMessage(
      "This broker has no custom blocks: its flow engine is older than ADR 0040.",
    ),
    "myBlocksReason": MessageLookupByLibrary.simpleMessage(
      "Needs own blocks in the engine",
    ),
    "myBlocksThisFlow": MessageLookupByLibrary.simpleMessage("This flow"),
    "nSelected": m116,
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
    "needsLevelYouHave": m117,
    "needsLevelYouHaveIt": m118,
    "networkError": MessageLookupByLibrary.simpleMessage("Connection problem"),
    "newCertificate": MessageLookupByLibrary.simpleMessage("new certificate"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("New dataflow"),
    "newTask": MessageLookupByLibrary.simpleMessage("New task"),
    "newValue": MessageLookupByLibrary.simpleMessage("New value"),
    "no": MessageLookupByLibrary.simpleMessage("no"),
    "noActionReason": m119,
    "noAgent": MessageLookupByLibrary.simpleMessage(
      "No assistant on this site. The assistant is the agent link: add it, give it an API key, then ask here.",
    ),
    "noAudit": MessageLookupByLibrary.simpleMessage(
      "No audit records you may read.",
    ),
    "noAuditHere": MessageLookupByLibrary.simpleMessage(
      "No records for this node in the last 500 of sys/audit.",
    ),
    "noChildren": MessageLookupByLibrary.simpleMessage(
      "Nothing under this node.",
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
    "noParamReason": m120,
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
    "noReadFlow": MessageLookupByLibrary.simpleMessage(
      "Opening the editor needs read on this flow.",
    ),
    "noRemoteLinks": MessageLookupByLibrary.simpleMessage(
      "No device connects as an external link.",
    ),
    "noRevisions": MessageLookupByLibrary.simpleMessage("No revisions."),
    "noTasks": MessageLookupByLibrary.simpleMessage(
      "Ask for a change. The agent reads the tree, writes a plan and waits for your approval. Nothing changes until you approve.",
    ),
    "noUpstream": m121,
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
    "noteActionBlock": MessageLookupByLibrary.simpleMessage(
      "An action of the tree. It runs on its trigger, on a changed argument, on a period, or by Run.",
    ),
    "noteBlockInputs": MessageLookupByLibrary.simpleMessage(
      "What the block takes. Drag from an input to every inner field it feeds; type its default here. + adds an input.",
    ),
    "noteBlockOutputs": MessageLookupByLibrary.simpleMessage(
      "What the block gives. Drag an inner output onto each. + adds an output.",
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
    "officialMark": MessageLookupByLibrary.simpleMessage("official"),
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
    "openInside": MessageLookupByLibrary.simpleMessage("Open inside"),
    "openItsTree": MessageLookupByLibrary.simpleMessage("Open its tree"),
    "openItsTreeNote": m122,
    "openingTree": MessageLookupByLibrary.simpleMessage("Opening the tree"),
    "openingTreeOf": m123,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Operate · runs now",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Runs on the device with your rights and is written to the audit.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("package"),
    "packageNamed": m124,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Package from your repository · SHA-256 checked against the index on download",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("Package URL (HTTPS)"),
    "pairsCount": m125,
    "paletteBlocks": MessageLookupByLibrary.simpleMessage("Blocks"),
    "paletteMyBlocks": MessageLookupByLibrary.simpleMessage("My blocks"),
    "paletteTree": MessageLookupByLibrary.simpleMessage("Tree"),
    "panelCanvas": MessageLookupByLibrary.simpleMessage("editor canvas"),
    "panelDrawer": MessageLookupByLibrary.simpleMessage("drawer"),
    "panelInspector": MessageLookupByLibrary.simpleMessage("inspector"),
    "panelMayDo": MessageLookupByLibrary.simpleMessage("What it may do"),
    "panelThisTask": MessageLookupByLibrary.simpleMessage("This task"),
    "panelTree": MessageLookupByLibrary.simpleMessage("tree"),
    "panelWorkspace": MessageLookupByLibrary.simpleMessage("workspace"),
    "paramCount": m126,
    "paramsJson": m127,
    "paramsNotJson": m128,
    "paramsNotObject": MessageLookupByLibrary.simpleMessage(
      "The parameters must be one JSON object.",
    ),
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
    "pickPointHint": MessageLookupByLibrary.simpleMessage(
      "Click a point to see its trend; ⌘/Ctrl-click adds up to three.",
    ),
    "pickPointTrend": MessageLookupByLibrary.simpleMessage(
      "Pick a point to see its trend",
    ),
    "pinField": MessageLookupByLibrary.simpleMessage("Pin to block"),
    "pinLocked": MessageLookupByLibrary.simpleMessage(
      "A bound field stays on the block",
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
    "pointsCount": m129,
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Values update live. Edits are staged in this session; nothing is written to the device until you apply.",
    ),
    "portsCount": m130,
    "preloadBlocks": MessageLookupByLibrary.simpleMessage(
      "Reading the flow blocks",
    ),
    "preloadFlows": MessageLookupByLibrary.simpleMessage("Reading the flows"),
    "preloadLater": m131,
    "preloadLinks": MessageLookupByLibrary.simpleMessage("Reading the links"),
    "preloadSites": MessageLookupByLibrary.simpleMessage("Reading the sites"),
    "preloadTree": m132,
    "previewInvalid": m133,
    "previewTag": MessageLookupByLibrary.simpleMessage("preview"),
    "problems": MessageLookupByLibrary.simpleMessage("Problems"),
    "problemsClear": MessageLookupByLibrary.simpleMessage("Clear all"),
    "problemsClose": MessageLookupByLibrary.simpleMessage("Close problems"),
    "problemsCount": m134,
    "problemsEmpty": MessageLookupByLibrary.simpleMessage(
      "No problems in this session.",
    ),
    "problemsNote": MessageLookupByLibrary.simpleMessage(
      "Failures of things Studio did on its own (reads, refreshes, live values) and every dialog you closed. Kept until Studio quits; newest first.",
    ),
    "problemsShown": MessageLookupByLibrary.simpleMessage("shown as a dialog"),
    "problemsTitle": MessageLookupByLibrary.simpleMessage(
      "Problems · this session",
    ),
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
    "qInstalled": m135,
    "qInstalling": m136,
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
    "reachesSites": m137,
    "readAgain": MessageLookupByLibrary.simpleMessage("Read again"),
    "readFailed": MessageLookupByLibrary.simpleMessage("read failed"),
    "readFailedTip": m138,
    "readsNote": MessageLookupByLibrary.simpleMessage(
      "Reading needs no approval. What it reads stays inside your rights and its own.",
    ),
    "recordInHistory": MessageLookupByLibrary.simpleMessage(
      "Record in history…",
    ),
    "recorded": MessageLookupByLibrary.simpleMessage("recorded"),
    "refresh": MessageLookupByLibrary.simpleMessage("Refresh"),
    "refuseLoop": MessageLookupByLibrary.simpleMessage(
      "This closes a loop (only a delay may)",
    ),
    "refuseNeedsBroker": m139,
    "refuseNoInput": m140,
    "refuseOutput": MessageLookupByLibrary.simpleMessage(
      "Outputs cannot be bound",
    ),
    "refuseSelf": MessageLookupByLibrary.simpleMessage(
      "A block cannot feed itself",
    ),
    "refuseType": m141,
    "reject": MessageLookupByLibrary.simpleMessage("Reject"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "This certificate is refused from now on.",
    ),
    "rejectTitle": m142,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Nothing to do from here: it came in with its relay. Deauthorize the relay to cut it off.",
    ),
    "relaysSites": m143,
    "rememberGatewayAndUser": MessageLookupByLibrary.simpleMessage(
      "Remember the gateway and user on this computer",
    ),
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
    "removeLinkTitle": m144,
    "removePair": MessageLookupByLibrary.simpleMessage("Remove the last case"),
    "removePort": MessageLookupByLibrary.simpleMessage("Remove the last port"),
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "It stops, its tree is deleted, and its id is retired: it cannot be used again.",
    ),
    "removeUser": MessageLookupByLibrary.simpleMessage("Remove user"),
    "removeUserNote": MessageLookupByLibrary.simpleMessage(
      "They cannot log in again; their sessions end.",
    ),
    "removeUserTitle": m145,
    "requiredField": MessageLookupByLibrary.simpleMessage("Required field"),
    "resultOf": m146,
    "returns": m147,
    "review": MessageLookupByLibrary.simpleMessage("Review"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage("Review and apply"),
    "reviewNote": m148,
    "revision": m149,
    "revisionNow": m150,
    "rightsLine": m151,
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Without this the broker installs nothing. Grants change later with Grant access; other values with the link\'s params.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "The package asks for these rights",
    ),
    "roleOnSite": m152,
    "rollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Its parameters become a new revision and the link restarts with them.",
    ),
    "rollBackTo": m153,
    "rowsAdd": MessageLookupByLibrary.simpleMessage("Add a row"),
    "rowsAnswered": m154,
    "rowsEmpty": MessageLookupByLibrary.simpleMessage("No rows yet"),
    "rowsRemove": MessageLookupByLibrary.simpleMessage("Remove this row"),
    "runBlock": MessageLookupByLibrary.simpleMessage("Run"),
    "runDraft": MessageLookupByLibrary.simpleMessage(
      "Deploy first: Run acts on the deployed version, and the draft differs from it",
    ),
    "runNoBroker": MessageLookupByLibrary.simpleMessage(
      "This broker has no trigger action (its flow engine is older than ADR 0040)",
    ),
    "runNoInstance": MessageLookupByLibrary.simpleMessage(
      "Open the block from an instance to run it",
    ),
    "runNotDeployed": MessageLookupByLibrary.simpleMessage(
      "Deploy the flow first",
    ),
    "runNow": MessageLookupByLibrary.simpleMessage("Run now"),
    "runNowNote": m155,
    "runOff": MessageLookupByLibrary.simpleMessage("The block is disabled"),
    "runOnStartTitle": MessageLookupByLibrary.simpleMessage(
      "Run on every start?",
    ),
    "running": MessageLookupByLibrary.simpleMessage("Running"),
    "runningNote": MessageLookupByLibrary.simpleMessage(
      "The agent works on it. Cancel stops it; what was done stays done.",
    ),
    "runsOn": m156,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Runs on another device",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Same call from the CLI",
    ),
    "scAddToSelection": MessageLookupByLibrary.simpleMessage(
      "Add to or take from the selection",
    ),
    "scClick": MessageLookupByLibrary.simpleMessage("click"),
    "scCopy": MessageLookupByLibrary.simpleMessage("Copy"),
    "scCut": MessageLookupByLibrary.simpleMessage("Cut"),
    "scDelete": MessageLookupByLibrary.simpleMessage("Delete"),
    "scDeploy": MessageLookupByLibrary.simpleMessage("Deploy (asks first)"),
    "scDoubleClick": MessageLookupByLibrary.simpleMessage("double click"),
    "scDrag": MessageLookupByLibrary.simpleMessage("drag"),
    "scDragEmpty": MessageLookupByLibrary.simpleMessage("drag on empty canvas"),
    "scDragHeader": MessageLookupByLibrary.simpleMessage("drag a header"),
    "scDuplicate": MessageLookupByLibrary.simpleMessage("Duplicate"),
    "scEscape": MessageLookupByLibrary.simpleMessage(
      "Cancel, clear the selection",
    ),
    "scGroupEdit": MessageLookupByLibrary.simpleMessage("Editing"),
    "scGroupSelect": MessageLookupByLibrary.simpleMessage("Selection"),
    "scGroupView": MessageLookupByLibrary.simpleMessage("View and flow"),
    "scHelp": MessageLookupByLibrary.simpleMessage("This card"),
    "scMarquee": MessageLookupByLibrary.simpleMessage("Select with a marquee"),
    "scMiddleDrag": MessageLookupByLibrary.simpleMessage("middle button drag"),
    "scMoveSelection": MessageLookupByLibrary.simpleMessage(
      "Move the selection",
    ),
    "scNote": MessageLookupByLibrary.simpleMessage(
      "Keys work while no text field has the focus.",
    ),
    "scNudge": MessageLookupByLibrary.simpleMessage("Move by one grid step"),
    "scNudgeFar": MessageLookupByLibrary.simpleMessage("10 steps"),
    "scOr": MessageLookupByLibrary.simpleMessage("or"),
    "scPan": MessageLookupByLibrary.simpleMessage("Pan"),
    "scPaste": MessageLookupByLibrary.simpleMessage("Paste"),
    "scPinch": MessageLookupByLibrary.simpleMessage("pinch"),
    "scRedo": MessageLookupByLibrary.simpleMessage("Redo"),
    "scScroll": MessageLookupByLibrary.simpleMessage("wheel / two fingers"),
    "scSearchPalette": MessageLookupByLibrary.simpleMessage("Find a block"),
    "scSelectAll": MessageLookupByLibrary.simpleMessage("Select all"),
    "scSpace": MessageLookupByLibrary.simpleMessage("Space"),
    "scTitle": MessageLookupByLibrary.simpleMessage("Keyboard and mouse"),
    "scUnbind": MessageLookupByLibrary.simpleMessage("Unbind a field"),
    "scUndo": MessageLookupByLibrary.simpleMessage("Undo"),
    "scViewValue": MessageLookupByLibrary.simpleMessage(
      "View the value under the pointer",
    ),
    "scWheel": MessageLookupByLibrary.simpleMessage("wheel"),
    "scZoom": MessageLookupByLibrary.simpleMessage("Zoom"),
    "scZoomFit": MessageLookupByLibrary.simpleMessage("Fit all blocks"),
    "scZoomIn": MessageLookupByLibrary.simpleMessage("Zoom in"),
    "scZoomOut": MessageLookupByLibrary.simpleMessage("Zoom out"),
    "scZoomReset": MessageLookupByLibrary.simpleMessage("Zoom to 100 %"),
    "scopeEdit": MessageLookupByLibrary.simpleMessage("Edit the scope"),
    "scopeEmpty": MessageLookupByLibrary.simpleMessage(
      "Type a scope: a key from a wire needs one",
    ),
    "scopeNote": MessageLookupByLibrary.simpleMessage(
      "A key that comes on the wire is read only inside this scope. Whoever deploys must be able to read all of it.",
    ),
    "scopeOtherSite": MessageLookupByLibrary.simpleMessage(
      "A scope lies in this site",
    ),
    "scopeSection": MessageLookupByLibrary.simpleMessage(
      "A scope starts with downstream, dataflows or storage",
    ),
    "scopeSegment": MessageLookupByLibrary.simpleMessage(
      "Not a key expression: segments of letters, digits, _ . - or * and **",
    ),
    "scopeTitle": MessageLookupByLibrary.simpleMessage(
      "This block may read keys under",
    ),
    "screenOf": m157,
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
    "secState": MessageLookupByLibrary.simpleMessage("State"),
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
    "setLogLevel": m158,
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
    "showPassword": MessageLookupByLibrary.simpleMessage("Show password"),
    "signingIn": MessageLookupByLibrary.simpleMessage("Signing in…"),
    "siteRelayedBelow": MessageLookupByLibrary.simpleMessage(
      "Site relayed below",
    ),
    "sitesAround": m159,
    "sitesSubtitle": m160,
    "sizeBytes": m161,
    "sizeChars": m162,
    "sizeColumns": m163,
    "sizeItems": m164,
    "sizeKeys": m165,
    "sizeLines": m166,
    "sizeRows": m167,
    "stage": MessageLookupByLibrary.simpleMessage("Stage"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "Stage puts it into Review and apply with your other edits.",
    ),
    "stagedChanges": m168,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Nothing is written until you apply. Each change runs with your own rights.",
    ),
    "stagedWas": m169,
    "stale": MessageLookupByLibrary.simpleMessage("stale"),
    "standbyAnswersAt": MessageLookupByLibrary.simpleMessage(
      "Its standby answers at",
    ),
    "standbyGateway": MessageLookupByLibrary.simpleMessage("Standby gateway"),
    "standbyIs": m170,
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
    "stepChecking": MessageLookupByLibrary.simpleMessage(
      "Checking user and password",
    ),
    "stepChoose": MessageLookupByLibrary.simpleMessage("Choose"),
    "stepInstall": MessageLookupByLibrary.simpleMessage("Install"),
    "stepOf": m171,
    "stepReaching": m172,
    "stepReading": MessageLookupByLibrary.simpleMessage(
      "Reading your role and sites",
    ),
    "stepWhere": MessageLookupByLibrary.simpleMessage("Where it runs"),
    "stopRecording": MessageLookupByLibrary.simpleMessage("Stop recording"),
    "studioAbout": m173,
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio is signed in here",
    ),
    "studioVersion": m174,
    "suggestPick": MessageLookupByLibrary.simpleMessage("Choose a value"),
    "sysActiveNote": MessageLookupByLibrary.simpleMessage(
      "Serves links, flows, the gateway and peers. Answers `sys/replication/**` for its standby.",
    ),
    "sysAdminOnly": MessageLookupByLibrary.simpleMessage("sys/**, admin only"),
    "sysArbiterLease": MessageLookupByLibrary.simpleMessage("Arbiter lease"),
    "sysAround": MessageLookupByLibrary.simpleMessage("Around (UTC)"),
    "sysAroundBad": MessageLookupByLibrary.simpleMessage(
      "Type a time as hh:mm or hh:mm:ss.",
    ),
    "sysAroundClear": MessageLookupByLibrary.simpleMessage("Show every time"),
    "sysAroundHint": MessageLookupByLibrary.simpleMessage("hh:mm:ss"),
    "sysAttnAcl": m175,
    "sysAttnAclDetail": m176,
    "sysAttnBehind": m177,
    "sysAttnBehindDetail": m178,
    "sysAttnBehindPlain": MessageLookupByLibrary.simpleMessage(
      "standby_lag is above 0: a takeover now loses records",
    ),
    "sysAttnBroker": m179,
    "sysAttnBrokerPlain": MessageLookupByLibrary.simpleMessage(
      "A downstream broker",
    ),
    "sysAttnBrokerRelays": m180,
    "sysAttnFork": MessageLookupByLibrary.simpleMessage(
      "The standby moved a fork aside",
    ),
    "sysAttnLinkDetail": m181,
    "sysAttnLinkFailed": m182,
    "sysAttnNoStandby": MessageLookupByLibrary.simpleMessage(
      "No standby follows this broker",
    ),
    "sysAttnNoStandbyDetail": MessageLookupByLibrary.simpleMessage(
      "standby_connected is 0",
    ),
    "sysAttnOpenAudit": MessageLookupByLibrary.simpleMessage("Open Audit ›"),
    "sysAttnOpenAvail": MessageLookupByLibrary.simpleMessage(
      "Open Availability ›",
    ),
    "sysAttnOpenLinks": MessageLookupByLibrary.simpleMessage("Open in Links ›"),
    "sysAttnOpenQuarantine": MessageLookupByLibrary.simpleMessage(
      "Open Quarantine ›",
    ),
    "sysAttnOpenSites": MessageLookupByLibrary.simpleMessage("Open in Sites ›"),
    "sysAttnQuarantine": m183,
    "sysAttnQuarantineDetail": m184,
    "sysAttnQuarantineSince": m185,
    "sysBackup": MessageLookupByLibrary.simpleMessage("Back up and restore"),
    "sysBackupNote": m186,
    "sysBackupNoteNoSize": MessageLookupByLibrary.simpleMessage(
      "Everything the broker owns is in its `data_dir`. Studio does not take backups: they hold the site\'s keys and are made on the host. The steps, ready to copy:",
    ),
    "sysBackupWarning": MessageLookupByLibrary.simpleMessage(
      "A backup holds the site CA and the gateway key: whoever reads it is an administrator. Encrypt it and keep it where only the broker\'s administrators can read it.",
    ),
    "sysBannerBehind": MessageLookupByLibrary.simpleMessage(
      "The standby is behind",
    ),
    "sysBannerBoth": MessageLookupByLibrary.simpleMessage(
      "The standby is behind and moved a fork aside",
    ),
    "sysBannerFork": MessageLookupByLibrary.simpleMessage(
      "The standby moved a fork aside",
    ),
    "sysBannerForks": m187,
    "sysBannerLag": m188,
    "sysBrokerAll": MessageLookupByLibrary.simpleMessage("broker (all)"),
    "sysBrokerLogLevel": MessageLookupByLibrary.simpleMessage(
      "Broker log level",
    ),
    "sysBytes": MessageLookupByLibrary.simpleMessage("Bytes"),
    "sysClear": m189,
    "sysClearAsk": MessageLookupByLibrary.simpleMessage(
      "Clear these disconnected links?",
    ),
    "sysClearAskBody": m190,
    "sysClearBoard": m191,
    "sysClearConfirm": MessageLookupByLibrary.simpleMessage("Clear"),
    "sysClearFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/clear_conns` · config · asks before it runs",
    ),
    "sysClearNone": MessageLookupByLibrary.simpleMessage(
      "Clear disconnected links…",
    ),
    "sysClearOne": MessageLookupByLibrary.simpleMessage(
      "Clear 1 disconnected link…",
    ),
    "sysCleared": m192,
    "sysClearedNone": MessageLookupByLibrary.simpleMessage(
      "The broker removed no link.",
    ),
    "sysCmdBackup": MessageLookupByLibrary.simpleMessage(
      "Back up (broker stopped)",
    ),
    "sysCmdBackupNote": MessageLookupByLibrary.simpleMessage(
      "Consistent and simplest. With a filesystem snapshot (LVM, btrfs, ZFS) the broker can keep running.",
    ),
    "sysCmdCheck": MessageLookupByLibrary.simpleMessage(
      "Before a restart with a changed file",
    ),
    "sysCmdCheckNote": MessageLookupByLibrary.simpleMessage(
      "The configuration parses and validates; exit code 1 otherwise.",
    ),
    "sysCmdVerify": MessageLookupByLibrary.simpleMessage("Check a copy"),
    "sysCmdVerifyNote": MessageLookupByLibrary.simpleMessage(
      "Checks every control-plane store offline: CRC, HMAC chain, anchors. Run it on the restored data_dir before a start.",
    ),
    "sysCollecting": MessageLookupByLibrary.simpleMessage("Collecting…"),
    "sysCommandCopied": MessageLookupByLibrary.simpleMessage("Commands copied"),
    "sysCopy": MessageLookupByLibrary.simpleMessage("Copy"),
    "sysCopyCommand": m193,
    "sysDownstream": MessageLookupByLibrary.simpleMessage("Downstream"),
    "sysElsewhere": MessageLookupByLibrary.simpleMessage(
      "Also broker settings, kept where they are used:",
    ),
    "sysElsewhereAccess": MessageLookupByLibrary.simpleMessage(
      "Roles and grants › Access",
    ),
    "sysElsewhereHistory": MessageLookupByLibrary.simpleMessage(
      "Retention and purge › History",
    ),
    "sysElsewhereLinks": MessageLookupByLibrary.simpleMessage(
      "Admission of new links › Links › Quarantine",
    ),
    "sysElsewhereSites": MessageLookupByLibrary.simpleMessage(
      "Tokens for sites below › Sites",
    ),
    "sysEvery5s": MessageLookupByLibrary.simpleMessage("every 5 s"),
    "sysFactLiveliness": MessageLookupByLibrary.simpleMessage("Liveliness"),
    "sysFactSite": MessageLookupByLibrary.simpleMessage("Site"),
    "sysFilter": MessageLookupByLibrary.simpleMessage("Filter"),
    "sysFilterHint": MessageLookupByLibrary.simpleMessage(
      "text in the target or message",
    ),
    "sysFlow": MessageLookupByLibrary.simpleMessage(
      "WAL, files, storage, history",
    ),
    "sysForks": MessageLookupByLibrary.simpleMessage("Forks moved aside"),
    "sysFrames": MessageLookupByLibrary.simpleMessage("Frames"),
    "sysGetLog": MessageLookupByLibrary.simpleMessage("Get log"),
    "sysGroupLinks": MessageLookupByLibrary.simpleMessage("Links and sites"),
    "sysGroupProcess": MessageLookupByLibrary.simpleMessage("Process and disk"),
    "sysGuideCopied": m194,
    "sysGuideLink": MessageLookupByLibrary.simpleMessage(
      "Guide: docs/operations.md › Warm standby ›",
    ),
    "sysHeld": MessageLookupByLibrary.simpleMessage("What the standby holds"),
    "sysHeldControl": MessageLookupByLibrary.simpleMessage("Control plane"),
    "sysHeldControlNote": MessageLookupByLibrary.simpleMessage(
      "Registry, flow definitions and gateway users: the WAL records themselves, checked against the HMAC chain.",
    ),
    "sysHeldHistory": MessageLookupByLibrary.simpleMessage("History"),
    "sysHeldHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Every series’ rows from the change journal, written into the standby’s own day files.",
    ),
    "sysHeldSecrets": MessageLookupByLibrary.simpleMessage(
      "Secrets and link data",
    ),
    "sysHeldSecretsNote": MessageLookupByLibrary.simpleMessage(
      "secrets.bin, link tokens, link data_dirs and packages: sealed parts of 1 MiB, files up to 64 MiB, removed when gone here.",
    ),
    "sysHeldStorage": MessageLookupByLibrary.simpleMessage("Broker storage"),
    "sysHeldStorageNote": MessageLookupByLibrary.simpleMessage(
      "The storage change journal, applied into the standby’s own storage (full tree beyond 20,000 changes).",
    ),
    "sysIn": MessageLookupByLibrary.simpleMessage("in"),
    "sysLag": MessageLookupByLibrary.simpleMessage("Lag"),
    "sysLevelMore": MessageLookupByLibrary.simpleMessage(
      "Level and more severe",
    ),
    "sysLines": MessageLookupByLibrary.simpleMessage("Lines"),
    "sysLinkSource": m195,
    "sysLogCopied": m196,
    "sysLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Staged in Review and apply; once applied it takes effect at once, no restart, and replaces `RUST_LOG`. Zenoh stays at warn below trace. Values and tokens are never logged below trace. A link\'s own level: Links › the link › Log.",
    ),
    "sysLogNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "The log is read with config on sys.",
    ),
    "sysLogNotSaved": MessageLookupByLibrary.simpleMessage(
      "Cannot save the log",
    ),
    "sysLogSaved": m197,
    "sysLogSummary": m198,
    "sysLogSummaryAround": m199,
    "sysLogSummaryNone": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/get_log` · config",
    ),
    "sysMessages": MessageLookupByLibrary.simpleMessage("Messages"),
    "sysMetaStarted": m200,
    "sysNeedsLook": m201,
    "sysNeedsLookNote": MessageLookupByLibrary.simpleMessage(
      "From the broker\'s own values. Each opens the screen where it is fixed.",
    ),
    "sysNoLines": MessageLookupByLibrary.simpleMessage(
      "No lines at this level.",
    ),
    "sysNoLinesAround": m202,
    "sysNoProfiles": MessageLookupByLibrary.simpleMessage("No profiles."),
    "sysNoStale": MessageLookupByLibrary.simpleMessage(
      "No disconnected links.",
    ),
    "sysNoStandbyBody": MessageLookupByLibrary.simpleMessage(
      "`sys/standby_connected` is 0. Either no warm standby is configured, or the one configured cannot reach this broker. If this host fails, the site stops until it is back; links on other machines walk to their next endpoint only if they have one.",
    ),
    "sysNoStandbyStep1": MessageLookupByLibrary.simpleMessage(
      "1. Copy the keys to the second host: `wyrmd keys export` here, `wyrmd keys import` there.",
    ),
    "sysNoStandbyStep2": m203,
    "sysNoStandbyStep3": MessageLookupByLibrary.simpleMessage(
      "3. Start the second host; this tab shows it within a second.",
    ),
    "sysNoStandbySteps": MessageLookupByLibrary.simpleMessage(
      "To add one (on the hosts, not in Studio)",
    ),
    "sysNoStandbyTitle": MessageLookupByLibrary.simpleMessage(
      "No standby is following this broker",
    ),
    "sysNotConnected": MessageLookupByLibrary.simpleMessage("not connected"),
    "sysNothing": MessageLookupByLibrary.simpleMessage("Nothing needs a look."),
    "sysNothingToClear": MessageLookupByLibrary.simpleMessage(
      "No disconnected links to clear",
    ),
    "sysNow": m204,
    "sysOfTotal": m205,
    "sysOpenAuditRecord": MessageLookupByLibrary.simpleMessage(
      "Open the audit record ›",
    ),
    "sysOut": MessageLookupByLibrary.simpleMessage("out"),
    "sysPackages": MessageLookupByLibrary.simpleMessage("Packages"),
    "sysProfileFile": m206,
    "sysProfileName": MessageLookupByLibrary.simpleMessage("Name"),
    "sysProfileNameHint": MessageLookupByLibrary.simpleMessage(
      "<vendor>:<model>",
    ),
    "sysProfilePut": m207,
    "sysProfileRemoved": m208,
    "sysProfiles": MessageLookupByLibrary.simpleMessage("Device profiles"),
    "sysProfilesFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/profiles` › Put Profile, Remove Profile · config",
    ),
    "sysProfilesNote": MessageLookupByLibrary.simpleMessage(
      "Models served as `pub/<vendor>:<model>`: points, units and ranges that links and the assistant inherit.",
    ),
    "sysProfilesUnlisted": m209,
    "sysPulled": MessageLookupByLibrary.simpleMessage("pulled every 1 s"),
    "sysPut": MessageLookupByLibrary.simpleMessage("Put profile"),
    "sysPutProfile": MessageLookupByLibrary.simpleMessage("Put profile…"),
    "sysRecords": MessageLookupByLibrary.simpleMessage("records"),
    "sysRemove": MessageLookupByLibrary.simpleMessage("Remove"),
    "sysRemoveProfile": m210,
    "sysRemoveProfileAsk": m211,
    "sysRunningActive": MessageLookupByLibrary.simpleMessage(
      "Running · active",
    ),
    "sysSaveLog": MessageLookupByLibrary.simpleMessage("Save as .log"),
    "sysSecondsLeft": MessageLookupByLibrary.simpleMessage("s left"),
    "sysSinceStart": MessageLookupByLibrary.simpleMessage("since start"),
    "sysSource": MessageLookupByLibrary.simpleMessage("Source"),
    "sysStale": MessageLookupByLibrary.simpleMessage("Disconnected links"),
    "sysStaleNote": MessageLookupByLibrary.simpleMessage(
      "Links admitted at runtime that run on other machines and are not connected now. Clearing removes them from the registry; their ids are retired and cannot be used again.",
    ),
    "sysStaleRow": m212,
    "sysStandbyBehind": MessageLookupByLibrary.simpleMessage(
      "Standby · behind",
    ),
    "sysStandbyConnected": MessageLookupByLibrary.simpleMessage(
      "Standby connected",
    ),
    "sysStandbyFollowing": MessageLookupByLibrary.simpleMessage(
      "Standby · following",
    ),
    "sysStandbyNote": MessageLookupByLibrary.simpleMessage(
      "Same keys, own `data_dir`. Takes over only if this broker stops answering and a witness still answers it.",
    ),
    "sysSubAcl": MessageLookupByLibrary.simpleMessage(
      "since the router started · open Audit",
    ),
    "sysSubAudit": MessageLookupByLibrary.simpleMessage(
      "who did what · open Audit",
    ),
    "sysSubCpu": MessageLookupByLibrary.simpleMessage("100 = one core"),
    "sysSubData": m213,
    "sysSubDisk": MessageLookupByLibrary.simpleMessage(
      "on the data_dir file system",
    ),
    "sysSubFollows": MessageLookupByLibrary.simpleMessage(
      "follows this broker over the peer link",
    ),
    "sysSubForks": MessageLookupByLibrary.simpleMessage(
      "after a healed split · audit standby_forked",
    ),
    "sysSubForksNone": MessageLookupByLibrary.simpleMessage(
      "no split since this broker started",
    ),
    "sysSubLag": MessageLookupByLibrary.simpleMessage(
      "not on the standby yet: a takeover now loses them",
    ),
    "sysSubLagNone": MessageLookupByLibrary.simpleMessage(
      "the standby has every registry record",
    ),
    "sysSubLease": MessageLookupByLibrary.simpleMessage(
      "renewed by the lease arbiter",
    ),
    "sysSubLeaseLate": MessageLookupByLibrary.simpleMessage(
      "renewing late: check the arbiter host",
    ),
    "sysSubLinkFailed": m214,
    "sysSubMemory": MessageLookupByLibrary.simpleMessage("resident"),
    "sysSubNoArbiter": MessageLookupByLibrary.simpleMessage(
      "no arbiter configured",
    ),
    "sysSubOpenHistory": MessageLookupByLibrary.simpleMessage("open History"),
    "sysSubOpenLinks": MessageLookupByLibrary.simpleMessage("open Links"),
    "sysSubOpenQuarantine": MessageLookupByLibrary.simpleMessage(
      "open Quarantine",
    ),
    "sysSubOpenSites": MessageLookupByLibrary.simpleMessage("open Sites"),
    "sysSubPackages": MessageLookupByLibrary.simpleMessage(
      "installed link packages",
    ),
    "sysSubPeer": m215,
    "sysSubSessions": MessageLookupByLibrary.simpleMessage(
      "network sessions; gateway users not counted",
    ),
    "sysSubWaits": m216,
    "sysTabAvailability": MessageLookupByLibrary.simpleMessage("Availability"),
    "sysTabLog": MessageLookupByLibrary.simpleMessage("Log"),
    "sysTabMaintenance": MessageLookupByLibrary.simpleMessage("Maintenance"),
    "sysTabOverview": MessageLookupByLibrary.simpleMessage("Overview"),
    "sysTabsLabel": MessageLookupByLibrary.simpleMessage("System sections"),
    "sysThisActive": MessageLookupByLibrary.simpleMessage(
      "This broker · active",
    ),
    "sysThisBroker": MessageLookupByLibrary.simpleMessage("This broker"),
    "sysTraffic": MessageLookupByLibrary.simpleMessage("Router traffic"),
    "sysTrafficDescribe": m217,
    "sysTrafficNote": MessageLookupByLibrary.simpleMessage(
      "Sampled from the `sys` rates while Studio is open (the broker keeps no history of them). Network sessions only: embedded links and gateway users talk in-process and are not counted.",
    ),
    "sysUnitConnected": MessageLookupByLibrary.simpleMessage("connected"),
    "sysUnreachable": MessageLookupByLibrary.simpleMessage("Unreachable"),
    "sysUpstream": MessageLookupByLibrary.simpleMessage("Upstream"),
    "systemFooter": MessageLookupByLibrary.simpleMessage(
      "wyrmd.json5 states the intent at first start; everything changed here since lives in its write-ahead log.",
    ),
    "tabActions": MessageLookupByLibrary.simpleMessage("Actions"),
    "tabAudit": MessageLookupByLibrary.simpleMessage("Audit"),
    "tabContents": MessageLookupByLibrary.simpleMessage("Contents"),
    "tabGrants": MessageLookupByLibrary.simpleMessage("Grants"),
    "tabHistory": MessageLookupByLibrary.simpleMessage("History"),
    "tabParameters": MessageLookupByLibrary.simpleMessage("Parameters"),
    "tabPoints": MessageLookupByLibrary.simpleMessage("Points"),
    "tabUsers": MessageLookupByLibrary.simpleMessage("Users"),
    "tableAddColumn": MessageLookupByLibrary.simpleMessage("Add column"),
    "tableAddRow": MessageLookupByLibrary.simpleMessage("Add row"),
    "tableFilter": MessageLookupByLibrary.simpleMessage("Filter rows"),
    "tableFiltered": m218,
    "tableMore": MessageLookupByLibrary.simpleMessage("More"),
    "tableNoColumns": MessageLookupByLibrary.simpleMessage(
      "a table with no columns",
    ),
    "tableNoColumnsEdit": MessageLookupByLibrary.simpleMessage(
      "No columns yet. Add one with Add column.",
    ),
    "tableNoRows": MessageLookupByLibrary.simpleMessage("No rows"),
    "tableRefusedBytes": MessageLookupByLibrary.simpleMessage(
      "Refused: the cells of a table hold at most 512 KiB.",
    ),
    "tableRefusedColumns": MessageLookupByLibrary.simpleMessage(
      "Refused: a table holds at most 128 columns.",
    ),
    "tableRefusedName": MessageLookupByLibrary.simpleMessage(
      "Refused: a column name has 1 to 256 bytes.",
    ),
    "tableRefusedNameTaken": MessageLookupByLibrary.simpleMessage(
      "Refused: the table already has a column with this name.",
    ),
    "tableRefusedRows": MessageLookupByLibrary.simpleMessage(
      "Refused: a table holds at most 10 000 rows.",
    ),
    "tableRemoveColumn": MessageLookupByLibrary.simpleMessage("Remove column"),
    "tableRemoveRow": MessageLookupByLibrary.simpleMessage("Remove row"),
    "tableRenameColumn": MessageLookupByLibrary.simpleMessage("Rename column"),
    "tagNeeds": m219,
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("runs now"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("staged"),
    "taskAwaiting": MessageLookupByLibrary.simpleMessage("awaiting approval"),
    "taskDone": MessageLookupByLibrary.simpleMessage("done"),
    "taskFailed": MessageLookupByLibrary.simpleMessage("failed or stopped"),
    "taskListNote": m220,
    "taskPlanning": MessageLookupByLibrary.simpleMessage("planning"),
    "taskRunning": MessageLookupByLibrary.simpleMessage("running"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("this broker"),
    "tlsCertificateOf": m221,
    "toAccept": MessageLookupByLibrary.simpleMessage("to accept"),
    "toastDismiss": MessageLookupByLibrary.simpleMessage("Dismiss"),
    "toastHidesIn": m222,
    "toastNotifications": MessageLookupByLibrary.simpleMessage("Notifications"),
    "toastStays": m223,
    "toastStream": MessageLookupByLibrary.simpleMessage(
      "Studio reopens the streams when it is back.",
    ),
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
    "treeActionNote2": MessageLookupByLibrary.simpleMessage(
      "a block that runs it: its parameters are fields you fill from other blocks, with a trigger.",
    ),
    "treeEmpty": MessageLookupByLibrary.simpleMessage("Nothing to show here."),
    "treeLoading": MessageLookupByLibrary.simpleMessage("Reading the tree…"),
    "treeNoteLead": MessageLookupByLibrary.simpleMessage(
      "The tree shows data only.",
    ),
    "treeNoteMiddle": MessageLookupByLibrary.simpleMessage("is edited in"),
    "treeOf": m224,
    "treePoint": MessageLookupByLibrary.simpleMessage("Point"),
    "treePointNote": MessageLookupByLibrary.simpleMessage(
      "on a block: adds it as a field. On the canvas: a new block of that node.",
    ),
    "treePointNote2": MessageLookupByLibrary.simpleMessage(
      "on the canvas: a block that reads it (a writable point asks Read or Write; Alt writes). On a field: wired into it.",
    ),
    "trendAll": MessageLookupByLibrary.simpleMessage("all"),
    "trendAllHidden": MessageLookupByLibrary.simpleMessage(
      "All series are hidden.",
    ),
    "trendAvg": m225,
    "trendBadRecorded": MessageLookupByLibrary.simpleMessage(
      "bad quality recorded",
    ),
    "trendBucket": m226,
    "trendClearMarker": MessageLookupByLibrary.simpleMessage(
      "Click A again to clear it",
    ),
    "trendDelta": m227,
    "trendDescribe": m228,
    "trendFollowNow": MessageLookupByLibrary.simpleMessage("Follow now"),
    "trendHint": MessageLookupByLibrary.simpleMessage(
      "Hover for values · drag on the chart to zoom · click to set marker A · drag or resize the window below · double-click resets · ← → move the focused handle",
    ),
    "trendHoursMinutes": m229,
    "trendLocked": m230,
    "trendMarker": m231,
    "trendMinMax": m232,
    "trendMinutes": m233,
    "trendMonths": MessageLookupByLibrary.simpleMessage(
      "Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec",
    ),
    "trendMoveWindow": MessageLookupByLibrary.simpleMessage(
      "Drag to move the window",
    ),
    "trendNoData": MessageLookupByLibrary.simpleMessage("no data"),
    "trendNoDataRecorded": MessageLookupByLibrary.simpleMessage(
      "no data recorded",
    ),
    "trendNothing": MessageLookupByLibrary.simpleMessage(
      "No values recorded in this range.",
    ),
    "trendNow": MessageLookupByLibrary.simpleMessage("now"),
    "trendRaw": MessageLookupByLibrary.simpleMessage("raw"),
    "trendRawAt": m234,
    "trendResetZoom": MessageLookupByLibrary.simpleMessage("Reset zoom"),
    "trendSeconds": m235,
    "trendSetMarker": MessageLookupByLibrary.simpleMessage(
      "Click to set marker A",
    ),
    "trendShowHide": m236,
    "trendStepDays": m237,
    "trendStepHours": m238,
    "trendStepMinutes": m239,
    "trendUncertain": MessageLookupByLibrary.simpleMessage(
      "uncertain · stale reads in this bucket",
    ),
    "trendWeekdays": MessageLookupByLibrary.simpleMessage(
      "Mon,Tue,Wed,Thu,Fri,Sat,Sun",
    ),
    "trendWindowEnd": MessageLookupByLibrary.simpleMessage("End of the window"),
    "trendWindowStart": MessageLookupByLibrary.simpleMessage(
      "Start of the window",
    ),
    "tryAgain": MessageLookupByLibrary.simpleMessage("Try again"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Turn on"),
    "unbind": MessageLookupByLibrary.simpleMessage("Unbind"),
    "unitNumber": m240,
    "unpinField": MessageLookupByLibrary.simpleMessage("Unpin from block"),
    "unreachableAdvice": MessageLookupByLibrary.simpleMessage(
      "The broker may be restarting or this computer is on another network.",
    ),
    "unsubscribeNote": MessageLookupByLibrary.simpleMessage(
      "The point stops being recorded; its rows stay.",
    ),
    "upFor": m241,
    "updAllOfficial": MessageLookupByLibrary.simpleMessage(
      "Update all official…",
    ),
    "updAsksMore": MessageLookupByLibrary.simpleMessage(
      "It asks for more rights",
    ),
    "updAuditRollback": MessageLookupByLibrary.simpleMessage(
      "Audit: update_rollback",
    ),
    "updAuditUpdate": MessageLookupByLibrary.simpleMessage(
      "Audit: package_update, restore_point",
    ),
    "updBefore": MessageLookupByLibrary.simpleMessage("Before it starts"),
    "updChecking": MessageLookupByLibrary.simpleMessage("health check"),
    "updChooseArchive": MessageLookupByLibrary.simpleMessage(
      "Choose the archive…",
    ),
    "updClose": MessageLookupByLibrary.simpleMessage("Close"),
    "updColPackage": MessageLookupByLibrary.simpleMessage("Package"),
    "updColVersion": MessageLookupByLibrary.simpleMessage("Version"),
    "updCustom": MessageLookupByLibrary.simpleMessage("custom"),
    "updDo": m242,
    "updFailed": m243,
    "updFailedNote": MessageLookupByLibrary.simpleMessage(
      "The health check ended without an answer from every link.",
    ),
    "updFromFile": MessageLookupByLibrary.simpleMessage("A newer archive"),
    "updFromFileNote": m244,
    "updFromFileRow": MessageLookupByLibrary.simpleMessage("Update from file…"),
    "updGoneTile": MessageLookupByLibrary.simpleMessage("gone"),
    "updHotStart": m245,
    "updHotStartNote": MessageLookupByLibrary.simpleMessage(
      "The running app gets the new code in place.",
    ),
    "updKept": MessageLookupByLibrary.simpleMessage(
      "Settings and nodes are kept",
    ),
    "updKeptNote": MessageLookupByLibrary.simpleMessage(
      "Each link keeps its private data; the new version reads it.",
    ),
    "updKeptTile": MessageLookupByLibrary.simpleMessage("kept"),
    "updKeptUntil": m246,
    "updLeave": MessageLookupByLibrary.simpleMessage(
      "You can leave this screen; it goes on.",
    ),
    "updLinksCount": m247,
    "updLinksRestart": m248,
    "updLinksRestartNote": MessageLookupByLibrary.simpleMessage(
      "Their values pause while each restarts; their nodes are declared again from the settings they keep.",
    ),
    "updNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "Needs config on sys/links",
    ),
    "updNewTile": MessageLookupByLibrary.simpleMessage("new"),
    "updNoNotes": MessageLookupByLibrary.simpleMessage(
      "The repository gives no notes for this version.",
    ),
    "updNoPoints": MessageLookupByLibrary.simpleMessage(
      "No restore point is kept for its links.",
    ),
    "updNodes": MessageLookupByLibrary.simpleMessage("Nodes before and after"),
    "updNothing": MessageLookupByLibrary.simpleMessage(
      "Every package is up to date.",
    ),
    "updOfficial": MessageLookupByLibrary.simpleMessage("official"),
    "updOpenLink": m249,
    "updOpenLog": MessageLookupByLibrary.simpleMessage("Open the log"),
    "updOptAccept": MessageLookupByLibrary.simpleMessage(
      "Accept the new rights it asks for",
    ),
    "updOptAuto": MessageLookupByLibrary.simpleMessage(
      "Roll back by itself if a link does not come back with all its nodes in 2 min",
    ),
    "updOptPoint": MessageLookupByLibrary.simpleMessage(
      "Save a restore point of each link (settings, secrets, private data)",
    ),
    "updOptPointLocked": MessageLookupByLibrary.simpleMessage(
      "The store format changes: a rollback needs the restore point",
    ),
    "updPillDone": MessageLookupByLibrary.simpleMessage("done"),
    "updPillFailed": MessageLookupByLibrary.simpleMessage("failed"),
    "updPillRolledBack": MessageLookupByLibrary.simpleMessage("rolled back"),
    "updPointBeforeRestore": m250,
    "updPointBeforeUpdate": m251,
    "updPoints": MessageLookupByLibrary.simpleMessage("Restore points"),
    "updRights": MessageLookupByLibrary.simpleMessage("Rights and network"),
    "updRightsNote": MessageLookupByLibrary.simpleMessage(
      "If the new version asks for more than the links have, the broker installs nothing and lists them here for you to accept.",
    ),
    "updRollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "updRollBackNote": m252,
    "updRollBackTitle": m253,
    "updRollBackTo": m254,
    "updRolledBackNote": MessageLookupByLibrary.simpleMessage(
      "The links run the kept version again with the data of their restore points.",
    ),
    "updRolledBackTo": m255,
    "updRowChecking": MessageLookupByLibrary.simpleMessage("being checked"),
    "updRuns": m256,
    "updRunsNote": m257,
    "updStateChanges": m258,
    "updStateChangesNote": MessageLookupByLibrary.simpleMessage(
      "The old version cannot read the new store: a rollback restores the store of the restore point.",
    ),
    "updStateCustom": MessageLookupByLibrary.simpleMessage(
      "Store format: the archive says",
    ),
    "updStateCustomNote": MessageLookupByLibrary.simpleMessage(
      "If the archive does not read the installed store format, the broker refuses an update without a restore point.",
    ),
    "updStateSame": m259,
    "updStateSameNote": MessageLookupByLibrary.simpleMessage(
      "The new version reads the store of the installed one.",
    ),
    "updStepNodes": MessageLookupByLibrary.simpleMessage(
      "Health: every link back with its nodes",
    ),
    "updStepNodesCount": m260,
    "updStepPackage": MessageLookupByLibrary.simpleMessage(
      "Package fetched, checked and unpacked beside the old version",
    ),
    "updStepPoint": MessageLookupByLibrary.simpleMessage(
      "Restore points saved",
    ),
    "updStepPointSaved": MessageLookupByLibrary.simpleMessage(
      "one for each link",
    ),
    "updStepRestart": MessageLookupByLibrary.simpleMessage("Links restarted"),
    "updStopAndRollBack": MessageLookupByLibrary.simpleMessage(
      "Stop and roll back",
    ),
    "updSubCustom": m261,
    "updSubOfficial": m262,
    "updTab": MessageLookupByLibrary.simpleMessage("Updates"),
    "updTabNote": MessageLookupByLibrary.simpleMessage(
      "Links whose package has a newer version. Every link of a package is updated together, and the broker keeps what it needs to go back.",
    ),
    "updThen": MessageLookupByLibrary.simpleMessage("Then"),
    "updTitle": m263,
    "updTitleCustom": m264,
    "updTitleDone": m265,
    "updTitleRolledBack": m266,
    "updTogether": MessageLookupByLibrary.simpleMessage("updated together"),
    "updUpdating": m267,
    "updUpdatingButton": MessageLookupByLibrary.simpleMessage("Updating…"),
    "updUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Values of its links pause while each restarts.",
    ),
    "updWhatChanges": MessageLookupByLibrary.simpleMessage(
      "What changes for the broker",
    ),
    "updWhatIsNew": m268,
    "updWorking": MessageLookupByLibrary.simpleMessage("installing"),
    "updating": MessageLookupByLibrary.simpleMessage("Updating…"),
    "upstream": MessageLookupByLibrary.simpleMessage("upstream"),
    "upstreamBroker": MessageLookupByLibrary.simpleMessage("Upstream broker"),
    "upstreamFooter": MessageLookupByLibrary.simpleMessage(
      "An upstream configured in wyrmd.json5 is changed there; one added here is removed with sys/upstream/<name> ▸ Remove.",
    ),
    "useStandby": MessageLookupByLibrary.simpleMessage("Use the standby"),
    "user": MessageLookupByLibrary.simpleMessage("User"),
    "userActive": MessageLookupByLibrary.simpleMessage("Active"),
    "userDisabled": MessageLookupByLibrary.simpleMessage("Disabled"),
    "validate": MessageLookupByLibrary.simpleMessage("Validate"),
    "valueCopied": MessageLookupByLibrary.simpleMessage("Value copied"),
    "valuesDeployed": MessageLookupByLibrary.simpleMessage(
      "the deployed version",
    ),
    "valuesPreview": MessageLookupByLibrary.simpleMessage(
      "a preview of the draft; nothing is written",
    ),
    "versionDeployed": m269,
    "viaSite": m270,
    "viewValue": MessageLookupByLibrary.simpleMessage("View value"),
    "viewerBadBool": MessageLookupByLibrary.simpleMessage("true or false"),
    "viewerBadJson": MessageLookupByLibrary.simpleMessage(
      "Not a JSON map or list",
    ),
    "viewerBadNumber": MessageLookupByLibrary.simpleMessage("Not a number"),
    "viewerCopyCsv": MessageLookupByLibrary.simpleMessage("Copy CSV"),
    "viewerCopyJson": MessageLookupByLibrary.simpleMessage("Copy JSON"),
    "viewerCsvHeaderOff": MessageLookupByLibrary.simpleMessage("no header row"),
    "viewerCsvHeaderOn": MessageLookupByLibrary.simpleMessage(
      "the first row names the columns",
    ),
    "viewerCsvRefused": MessageLookupByLibrary.simpleMessage(
      "The block refuses this text (parse_error): it has no row, or it passes a bound of a table.",
    ),
    "viewerCsvRules": m271,
    "viewerCsvWired": MessageLookupByLibrary.simpleMessage(
      "A wire feeds the delimiter or the header: the table uses the values they hold now.",
    ),
    "viewerDiscard": MessageLookupByLibrary.simpleMessage("Discard"),
    "viewerEdit": MessageLookupByLibrary.simpleMessage("Edit"),
    "viewerEditJson": MessageLookupByLibrary.simpleMessage("Edit as JSON"),
    "viewerEmpty": MessageLookupByLibrary.simpleMessage(
      "Empty: the field goes back to its default",
    ),
    "viewerLockedBound": MessageLookupByLibrary.simpleMessage(
      "Read only: a wire feeds this field. Unbind it to type a value.",
    ),
    "viewerLockedInput": MessageLookupByLibrary.simpleMessage(
      "Read only: this input holds no typed value. Bind an output to it.",
    ),
    "viewerLockedOutput": MessageLookupByLibrary.simpleMessage(
      "Read only: the block computes this output.",
    ),
    "viewerSave": MessageLookupByLibrary.simpleMessage("Save"),
    "viewerSaveHint": m272,
    "viewerTabTable": MessageLookupByLibrary.simpleMessage("As table"),
    "viewerTabText": MessageLookupByLibrary.simpleMessage("Text"),
    "viewerTableHint": m273,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Waiting in quarantine",
    ),
    "waitingToBeLetIn": m274,
    "wasValue": m275,
    "wasWord": MessageLookupByLibrary.simpleMessage("was"),
    "watchGroup": MessageLookupByLibrary.simpleMessage("Watch group"),
    "watchGroups": m276,
    "welcomeUser": m277,
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
    "windowClose": MessageLookupByLibrary.simpleMessage("Close window"),
    "windowMaximize": MessageLookupByLibrary.simpleMessage("Maximize"),
    "windowMinimize": MessageLookupByLibrary.simpleMessage("Minimize"),
    "windowRestore": MessageLookupByLibrary.simpleMessage("Restore"),
    "wordOrderReason": MessageLookupByLibrary.simpleMessage(
      "Set by the data type: its _wswap, _bswap or _wbswap suffix.",
    ),
    "wouldRun": m278,
    "wouldSend": m279,
    "wouldWrite": m280,
    "writableNeeds": m281,
    "wrongPassword": MessageLookupByLibrary.simpleMessage(
      "User or password is wrong. Ask an administrator to reset it; the gateway never sends it by mail.",
    ),
    "wsAccess": MessageLookupByLibrary.simpleMessage("Access"),
    "wsAssistant": MessageLookupByLibrary.simpleMessage("Assistant"),
    "wsExplorer": MessageLookupByLibrary.simpleMessage("Explorer"),
    "wsFlows": MessageLookupByLibrary.simpleMessage("Flows"),
    "wsHistory": MessageLookupByLibrary.simpleMessage("History"),
    "wsLinks": MessageLookupByLibrary.simpleMessage("Links"),
    "wsSites": MessageLookupByLibrary.simpleMessage("Sites"),
    "wsSystem": MessageLookupByLibrary.simpleMessage("System"),
    "wyrmdOn": m282,
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
