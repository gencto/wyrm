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

  static String m7(n) =>
      "${Intl.plural(n, one: '1 step without a tick changes something and runs with the agent\'s own key; it cannot be left out. Reject the plan to stop it.', other: '${n} steps without a tick change something and run with the agent\'s own key; they cannot be left out. Reject the plan to stop them.')}";

  static String m8(n) =>
      "${Intl.plural(n, one: 'Approve 1 change and run', other: 'Approve ${n} changes and run')}";

  static String m9(site) =>
      "This task is on site ${site}. This gateway signs approvals only for tasks of its own site. Approve it through the gateway of ${site}.";

  static String m10(why) =>
      "The approval was refused; the task still waits. ${why}";

  static String m11(role) =>
      "Signs one token per ticked step with your rights (${role}). Unticked steps are left out.";

  static String m12(count) => "Ask an admin for ${count}";

  static String m13(n) => "asks to join · relays ${n}";

  static String m14(sites) => "asks to relay: ${sites}";

  static String m15(code) => "refused (${code})";

  static String m16(id) =>
      "A link ${id} exists on this broker: it is replaced in place (same driver and mode), and a restore point of it is taken first.";

  static String m17(size, rights) => "About ${size} · ${rights}";

  static String m18(days) =>
      "Made while the broker runs, kept on it for ${days} days. Download one or send it to a file store.";

  static String m19(name) => "Choose the folder for ${name}";

  static String m20(link) => "Back up ${link}";

  static String m21(when) => "Kept on the broker until ${when} (Backups).";

  static String m22(done, size) => "Downloading: ${done} of ${size}";

  static String m23(what) => "Backup of ${what} failed";

  static String m24(site) =>
      "It holds the site\'s keys: whoever has the file and the passphrase is an administrator of ${site}.";

  static String m25(link) => "link ${link}";

  static String m26(n) => "At least ${n} characters";

  static String m27(what) => "Backing up ${what}";

  static String m28(name) => "Remove ${name}?";

  static String m29(percent) => "being made · ${percent} %";

  static String m30(percent) => "sending · ${percent} %";

  static String m31(name) => "Saved ${name}";

  static String m32(size, n) => "${size} · sections: ${n}";

  static String m33(path) => "Saved to ${path}; SHA-256 checked.";

  static String m34(site) =>
      "sealed for ${site}: opens only on a broker with its keys";

  static String m35(error) => "Not sent: ${error}";

  static String m36(to) => "Sending to ${to}";

  static String m37(link) =>
      "One .wyrm-link file with what ${link} needs to come back, here or on another broker.";

  static String m38(site) => "Back up ${site}";

  static String m39(link) => "Back up the link ${link}";

  static String m40(days) => "Kept in Backups for ${days} days.";

  static String m41(days) =>
      "Downloaded in parts when it is ready; also kept on the broker for ${days} days.";

  static String m42(n) =>
      "${Intl.plural(n, one: '1 block', other: '${n} blocks')}";

  static String m43(brokers, devices) =>
      "${brokers} brokers · ${devices} devices";

  static String m44(driver) => "built-in driver ${driver}";

  static String m45(version) => "Back on ${version}";

  static String m46(tried, version) =>
      "${tried} did not pass its trial start. The next start went back to ${version} and restored the control plane from the pre-update backup.";

  static String m47(version, latest) => "${version} · ${latest} is available";

  static String m48(version) => "${version} · up to date";

  static String m49(version) => "${version} · the update was rolled back";

  static String m50(version) => "${version} is on trial";

  static String m51(version) =>
      "If the new version writes a newer SCHEMA, ${version} cannot read it afterwards: a rollback restores the pre-update backup of the control plane, so changes made after the update are lost on rollback.";

  static String m52(from, to) => "Stopped on ${from}, started on ${to}";

  static String m53(version) => "${version} staged";

  static String m54(back, all, seconds) => "${back} of ${all} in ${seconds} s";

  static String m55(time) =>
      "Studio lost the gateway and tries again by itself · ${time}";

  static String m56(version) => "Open the log of ${version}";

  static String m57(site, version) => "${site} is restarting on ${version}";

  static String m58(site, version) => "Roll back ${site} to ${version}?";

  static String m59(when) => "possible until ${when}";

  static String m60(site, version) => "${site} runs ${version}";

  static String m61(version) =>
      "The update is confirmed; ${version} and the pre-update backup are kept for a rollback.";

  static String m62(n) => "${n} s";

  static String m63(version) =>
      "The new binary is staged beside the current one; ${version} stays on disk.";

  static String m64(version) =>
      "The broker stops cleanly and the service manager starts ${version} (about 5–15 s without the broker).";

  static String m65(version) =>
      "${version} runs on trial: it must have the router, the gateway and its links back within 3 min.";

  static String m66(version) =>
      "Then it confirms itself. If it does not, the next start goes back to ${version} with the backup of step 1.";

  static String m67(site, version) => "Update ${site} to wyrmd ${version}";

  static String m68(site) => "Type ${site} to confirm";

  static String m69(site) => "${site} updated";

  static String m70(site) => "Updating ${site}";

  static String m71(site) => "CA-signed · ${site} CA";

  static String m72(n) =>
      "${Intl.plural(n, one: '1 block becomes', other: '${n} blocks become')} one block of this flow. Wires that cross its edge become its inputs and outputs.";

  static String m73(count) =>
      "${Intl.plural(count, zero: 'no children', one: '1 child', other: '${count} children')}";

  static String m74(answer) => "from the card: ${answer}";

  static String m75(answer) => "in your own words: ${answer}";

  static String m76(site) =>
      "${site} dials out to it; it authorizes ${site} there.";

  static String m77(size) => "data_dir ${size}";

  static String m78(id) => "Deauthorize ${id}?";

  static String m79(flow) =>
      "The draft of “${flow}” replaces the version that runs now.";

  static String m80(who) => "deployed by ${who}";

  static String m81(name) => "Forget ${name}?";

  static String m82(method, when) => "${method} · ${when}";

  static String m83(user) =>
      "${user} can no longer unlock with it; it signs in with the password only. The record stays as removed by you until it is forgotten.";

  static String m84(name) => "Remove ${name}?";

  static String m85(n, where) =>
      "${Intl.plural(n, one: '1 gateway on ${where} · announced by DNS-SD', other: '${n} gateways on ${where} · announced by DNS-SD')}";

  static String m86(where) => "Looking on ${where}…";

  static String m87(where) => "No gateway answered on ${where} in 8 s";

  static String m88(n, range) =>
      "${Intl.plural(n, one: '1 gateway on ${range} · found by a range probe', other: '${n} gateways on ${range} · found by a range probe')}";

  static String m89(range, port) => "Probing ${range} on port ${port}…";

  static String m90(steps) =>
      "The task is done. Steps left out: ${steps}. Ask for them as a follow-up; its plan is approved on its own.";

  static String m91(device) =>
      "It runs on ${device}; the broker cannot start or stop it.";

  static String m92(id) => "Edit params of ${id}";

  static String m93(time) =>
      "The broker log around ${time} has the rest of the story.";

  static String m94(field) =>
      "Back in the form, the field ${field} is marked; correct it and send again.";

  static String m95(role, site) =>
      "Your role is ${role}. Nothing was changed on ${site}.";

  static String m96(call, key) => "${call} on ${key}";

  static String m97(type) => "studio · ${type}";

  static String m98(thing) => "deploy ${thing}";

  static String m99(thing) => "install ${thing}";

  static String m100(thing) => "list ${thing}";

  static String m101(thing) => "log in to ${thing}";

  static String m102(thing) => "open ${thing}";

  static String m103(thing) => "read ${thing}";

  static String m104(thing) => "remove ${thing}";

  static String m105(call, thing) => "run ${call} on ${thing}";

  static String m106(thing) => "save ${thing}";

  static String m107(thing) => "start ${thing}";

  static String m108(step) => "finish “${step}”";

  static String m109(thing) => "stop ${thing}";

  static String m110(thing) => "write ${thing}";

  static String m111(thing) => "Deploying ${thing}";

  static String m112(thing) => "Installing ${thing}";

  static String m113(thing) => "Listing ${thing}";

  static String m114(thing) => "Logging in to ${thing}";

  static String m115(thing) => "Opening ${thing}";

  static String m116(thing) => "Reading ${thing}";

  static String m117(thing) => "Removing ${thing}";

  static String m118(call, thing) => "${call} on ${thing}";

  static String m119(thing) => "Saving ${thing}";

  static String m120(thing) => "Starting ${thing}";

  static String m121(thing) => "Stopping ${thing}";

  static String m122(thing) => "Writing ${thing}";

  static String m123(call) => "${call}";

  static String m124(site) => "No answer from the broker at ${site}.";

  static String m125(status) =>
      "The broker answered ${status} and sent no message.";

  static String m126(status, message) => "${status}: ${message}";

  static String m127(time) => "${time} (local)";

  static String m128(doing, site) => "${doing} failed on ${site}";

  static String m129(doing) => "${doing} failed";

  static String m130(site, what) => "${site} is busy, ${what} did not start";

  static String m131(thing) => "${thing} is not there anymore";

  static String m132(thing) => "History of ${thing} unavailable";

  static String m133(site) => "${site} did not answer";

  static String m134(thing) => "Reading ${thing} failed";

  static String m135(what) => "You can’t ${what}";

  static String m136(site) => "Live values from ${site} stopped";

  static String m137(what) => "Studio could not ${what}";

  static String m138(thing, call) => "${thing} does not support ${call}";

  static String m139(seconds) => "Try again in ${seconds} s";

  static String m140(user, role) => "${user} (${role})";

  static String m141(s) => "every ${s} s";

  static String m142(reason) =>
      "The unreadable file could not be moved aside: ${reason}";

  static String m143(name) =>
      "Fresh settings keep the unreadable file beside the new one as ${name}. You add your gateways and log in again.";

  static String m144(panel) => "Studio could not draw ${panel}";

  static String m145(panel) => "The ${panel} could not be drawn";

  static String m146(when) => "first seen ${when}";

  static String m147(v) => "v${v} deployed";

  static String m148(v) => "v${v} · error";

  static String m149(v) => "v${v} stopped";

  static String m150(v) => "Version ${v}";

  static String m151(site) => "Flows on ${site}";

  static String m152(count) => "${count} blocks";

  static String m153(label) => "Unpin “${label}” from block";

  static String m154(task, steps) =>
      "Do the steps that were left out of the plan of task ${task}: ${steps}.";

  static String m155(address) => "from ${address}";

  static String m156(host, ms) => "${host} · answered in ${ms} ms";

  static String m157(host) => "No answer from ${host}";

  static String m158(key) => "Go to ${key}";

  static String m159(id) => "Grant access to ${id}";

  static String m160(days) => "raw kept ${days} d";

  static String m161(n) => "${n} series";

  static String m162(size) => "Historian ${size}";

  static String m163(id) => "Params history of ${id}";

  static String m164(status) =>
      "Reading the history failed: ${status}. Details in Problems.";

  static String m165(main, standby) => "${main} · standby ${standby}";

  static String m166(n) =>
      "${Intl.plural(n, one: '1 input', other: '${n} inputs')}";

  static String m167(name, broker) => "${name} is installed on ${broker}.";

  static String m168(n) =>
      "${Intl.plural(n, zero: 'no instance in this flow', one: '1 instance in this flow', other: '${n} instances in this flow')} · a change here changes them all";

  static String m169(count) => "${count} keys copied";

  static String m170(lag) => "lag ${lag}";

  static String m171(time) => "last read ${time}";

  static String m172(n) =>
      "${Intl.plural(n, one: '1 link already', other: '${n} links already')}";

  static String m173(n) =>
      "${Intl.plural(n, one: '1 link', other: '${n} links')}";

  static String m174(site) =>
      "Started and watched by ${site}: built-in drivers and installed packages. You can stop, change, upgrade and remove them.";

  static String m175(site) => "Links on ${site}";

  static String m176(first, last) => "${first} and ${last}";

  static String m177(status) =>
      "Reading the list of children failed: ${status}. Details in Problems.";

  static String m178(n) =>
      "${Intl.plural(n, one: '1 change is waiting in Review and apply; it is kept.', other: '${n} changes are waiting in Review and apply; they are kept.')}";

  static String m179(user, site, min) =>
      "${user} on ${site} · locked after ${min} min without use. Values and the tree stay hidden; links, flows and the session keep running.";

  static String m180(id) => "Log of ${id}";

  static String m181(n) =>
      "${Intl.plural(n, one: '1 instance uses it', other: '${n} instances use it')}";

  static String m182(n) => "library v${n}";

  static String m183(n) => "${n} used";

  static String m184(n) => "v${n}";

  static String m185(kind, count) => "${kind} · ${count} actions";

  static String m186(status) =>
      "Reading the description failed: ${status}. Details in Problems.";

  static String m187(count) =>
      "${Intl.plural(count, one: '… 1 more byte', other: '… ${count} more bytes')}";

  static String m188(count) =>
      "${Intl.plural(count, one: '1 more line', other: '${count} more lines')}";

  static String m189(count) => "${count} selected";

  static String m190(level, have) => "Needs ${level} · you have ${have}";

  static String m191(level) => "Needs ${level} · you have it";

  static String m192(action) => "This node has no ${action} action.";

  static String m193(param) => "The driver has no ${param} parameter.";

  static String m194(site) => "none: ${site} is the top";

  static String m195(site) => "signed by the ${site} CA (known)";

  static String m196(site) => "certificate of the ${site} CA, pinned";

  static String m197(version) => "wyrmd ${version}";

  static String m198(site) => "Explorer shows wy/${site}.";

  static String m199(node) => "Open ${node} in Explorer";

  static String m200(site) => "Opening the tree of ${site}…";

  static String m201(name) => "package ${name}";

  static String m202(n) =>
      "${Intl.plural(n, one: '1 case', other: '${n} cases')}";

  static String m203(n) =>
      "${Intl.plural(n, zero: 'no parameters', one: '1 parameter', other: '${n} parameters')}";

  static String m204(rev) => "Parameters (revision ${rev}, JSON)";

  static String m205(detail) => "Not JSON: ${detail}";

  static String m206(site) => "${site} · picked from this network";

  static String m207(site) =>
      "${site} · picked from this network · standby filled in";

  static String m208(now, atRun) =>
      "awaiting approval · ${now} checked now, ${atRun} when it runs";

  static String m209(n) => "needs step ${n}";

  static String m210(path) => "Saved ${path}. Run it with wyrm-agent run.";

  static String m211(steps) =>
      "Secret arguments are not in the file: ${steps}. Add them before you run it.";

  static String m212(s) => "${s} s";

  static String m213(n) => "Plan · ${n} steps";

  static String m214(s) => "timeout ${s} s";

  static String m215(n) =>
      "${Intl.plural(n, one: '1 point', other: '${n} points')}";

  static String m216(n) =>
      "${Intl.plural(n, one: '1 port', other: '${n} ports')}";

  static String m217(step) => "${step} · later";

  static String m218(site) => "Reading the tree of ${site}";

  static String m219(message) => "The draft does not run: ${message}";

  static String m220(reason) =>
      "Not offered: /api/info did not answer (${reason}).";

  static String m221(version) =>
      "Not offered: this gateway needs Studio ${version} or newer.";

  static String m222(count) =>
      "${Intl.plural(count, one: '1 problem', other: '${count} problems')}";

  static String m223(name) => "${name} is installed";

  static String m224(name) => "Installing ${name}…";

  static String m225(sites) => "reaches ${sites}";

  static String m226(status) =>
      "Reading the value failed: ${status}. Details in Problems.";

  static String m227(field) =>
      "This broker cannot bind ${field} (its flow engine is older than ADR 0040)";

  static String m228(field) => "${field} takes no input: type its value";

  static String m229(from, to) => "${from} does not fit ${to}";

  static String m230(cn) => "Reject ${cn}?";

  static String m231(n) =>
      "${Intl.plural(n, one: 'relays 1 site', other: 'relays ${n} sites')}";

  static String m232(id) => "Remove ${id}?";

  static String m233(name) => "Remove ${name}?";

  static String m234(action) => "Result · ${action}";

  static String m235(what) => "returns ${what}";

  static String m236(audit) =>
      "Each write is checked by the link and recorded in ${audit}. A value shows only after it is read back.";

  static String m237(rev) => "Revision ${rev}";

  static String m238(rev) => "Revision ${rev} · in use";

  static String m239(site, user, role, level) =>
      "Site ${site} · applied with your rights: ${user}, ${role} (${level})";

  static String m240(role, site) => "${role} on ${site}";

  static String m241(rev) => "Roll back to revision ${rev}?";

  static String m242(n) =>
      "${Intl.plural(n, one: '1 row', other: '${n} rows')}";

  static String m243(site, broker) => "From ${site} · wyrmd ${broker}";

  static String m244(when, n, sealed) =>
      "Made ${when} · sections: ${n} · secrets: ${sealed}";

  static String m245(fresh, exists) =>
      "Links: ${fresh} new, ${exists} exist here";

  static String m246(site) => "A backup of another site: ${site}";

  static String m247(files) => "Replace the site\'s keys: ${files}";

  static String m248(site) => "${site} restarts and applies the backup";

  static String m249(site) => "Restore ${site} from a backup";

  static String m250(done, size) => "Uploading: ${done} of ${size}";

  static String m251(user) =>
      "Runs as ${user}. Nothing else in the tree changes unless the result is used.";

  static String m252(s) => "all steps passed · ${s} s";

  static String m253(steps) => "done · steps left out: ${steps}";

  static String m254(steps) =>
      "stopped · steps ${steps} changed something and stay done";

  static String m255(n) =>
      "stopped · step ${n} changed something and stays done";

  static String m256(n, of) => "Run · step ${n} of ${of}";

  static String m257(of) => "Run · ${of} steps";

  static String m258(site) => "Runs on ${site}";

  static String m259(task) => "Save the plan of ${task}";

  static String m260(name) => "${name}";

  static String m261(date) => "added ${date}";

  static String m262(site) =>
      "Set by ${site} (gateway.devices.step_up: config); you cannot turn it off here.";

  static String m263(site) =>
      "${site} does not ask for it (gateway.devices.step_up: none); only the gateway can turn it on.";

  static String m264(site) => "Your devices on ${site}";

  static String m265(n) =>
      "${Intl.plural(n, zero: 'password due today', one: 'password due in 1 day', other: 'password due in ${n} days')}";

  static String m266(site, max) =>
      "Hides the tree and values; the session and Review and apply are kept. ${site} allows at most ${max} min.";

  static String m267(n) => "${n} min";

  static String m268(device) => "On ${device}";

  static String m269(site) =>
      "${site} asks for your password before a new key.";

  static String m270(site, state, max, days, confirm) =>
      "${site}’s policy: devices ${state} · up to ${max} · password every ${days} days${confirm}. An administrator sees and removes devices in Access › Users.";

  static String m271(admin) => "removed by ${admin}";

  static String m272(user) =>
      "Every session and every device of ${user} ends, this one too.";

  static String m273(store, date, device) =>
      "A key in ${store}, added ${date}. Off removes the key here and ${device} from your devices.";

  static String m274(store) =>
      "Off: Studio asks for the password here. On makes a key in ${store}.";

  static String m275(s) => "${s} s";

  static String m276(level) => "Log level ${level}";

  static String m277(site) => "Sites around ${site}";

  static String m278(site) =>
      "What ${site} connects to and what connects to it: brokers above and below, platforms it sends to, and devices whose links run outside any broker.";

  static String m279(count) =>
      "${Intl.plural(count, one: '1 byte', other: '${count} bytes')}";

  static String m280(count) =>
      "${Intl.plural(count, one: '1 char', other: '${count} chars')}";

  static String m281(count) =>
      "${Intl.plural(count, one: '1 column', other: '${count} columns')}";

  static String m282(count) =>
      "${Intl.plural(count, one: '1 item', other: '${count} items')}";

  static String m283(count) =>
      "${Intl.plural(count, one: '1 key', other: '${count} keys')}";

  static String m284(count) =>
      "${Intl.plural(count, one: '1 line', other: '${count} lines')}";

  static String m285(count) =>
      "${Intl.plural(count, one: '1 row', other: '${count} rows')}";

  static String m286(count) =>
      "${Intl.plural(count, zero: 'No staged changes', one: '1 staged change', other: '${count} staged changes')}";

  static String m287(was) => "staged · was ${was}";

  static String m288(host) => "Standby: ${host}";

  static String m289(n, total) => "Step ${n} of ${total}";

  static String m290(host) => "Reaching ${host}";

  static String m291(n) => "skipped: needs step ${n}";

  static String m292(name) => "Confirm with ${name}";

  static String m293(name, site, device) =>
      "${name} signs this one request: ${site} gets a proof bound to these changes, and stays confirmed on ${device} for 5 minutes.";

  static String m294(n, site) =>
      "${Intl.plural(n, one: 'Apply 1 change on ${site}.', other: 'Apply ${n} changes on ${site}.')} ${site} asks for a fresh confirmation before config changes.";

  static String m295(site) =>
      "Enter your password: ${site} stays confirmed for 5 minutes.";

  static String m296(site, reason) =>
      "${site} did not take the confirmation: ${reason}";

  static String m297(name) =>
      "${name} did not confirm. Try again or use the password.";

  static String m298(name) => "Waiting for ${name}…";

  static String m299(n) => "Stopped at step ${n}";

  static String m300(why) =>
      "${why}\nWhat was done before it stays done; nothing is reversed by itself.";

  static String m301(version, os) => "${version} (${os})";

  static String m302(version, language) => "Studio ${version} · ${language}";

  static String m303(n) => "ACL denials grew by ${n}";

  static String m304(from) =>
      "acl_denied was ${from} when this screen was last shown";

  static String m305(n) => "Standby is ${n} records behind";

  static String m306(n) => "Forks moved aside after a split: ${n}";

  static String m307(site) => "${site} waits for Authorize";

  static String m308(n) => "A downstream broker that relays sites: ${n}";

  static String m309(id) => "sys/links/${id}/state is failed; its log says why";

  static String m310(id) => "${id} failed";

  static String m311(cn) => "${cn} waits in quarantine";

  static String m312(cn) => "Unknown certificate CN ${cn}";

  static String m313(cn, t) => "Unknown certificate CN ${cn} since ${t}";

  static String m314(size) =>
      "Everything the broker owns is in its `data_dir` (here ${size}). Studio does not take backups: they hold the site\'s keys and are made on the host. The steps, ready to copy:";

  static String m315(n) =>
      "Sets of records moved aside after both brokers were active (a healed split): ${n}. The audit record `standby_forked` says which.";

  static String m316(n) =>
      "${n} registry records are not on the standby yet: a takeover now would lose them.";

  static String m317(n) => "Clear disconnected links (${n})…";

  static String m318(ids) =>
      "${ids}\n\nTheir ids are retired and cannot be used again.";

  static String m319(n) => "Clear ${n} disconnected links…";

  static String m320(ids) => "Removed: ${ids}";

  static String m321(title) => "Copy: ${title}";

  static String m322(url) => "Link to the guide copied: ${url}";

  static String m323(id) => "link: ${id}";

  static String m324(n) => "Lines copied: ${n}";

  static String m325(path) => "Saved ${path}";

  static String m326(n) =>
      "${n} lines from the broker\'s ring · newest first · `sys/~act/get_log`";

  static String m327(n, m, time) =>
      "${n} of ${m} lines within 2 min of ${time} UTC · newest first · `sys/~act/get_log`";

  static String m328(t) => "started ${t}";

  static String m329(n) => "Needs a look · ${n}";

  static String m330(m, time) =>
      "None of the newest ${m} lines is within 2 min of ${time} UTC. Ask for more lines, or clear the time.";

  static String m331(standby) =>
      "2. In `wyrmd.json5` on both hosts: `${standby}` and `peers.listen`; a lease `arbiter` on a third host is recommended.";

  static String m332(t) => "${t} · now";

  static String m333(n) => "of ${n}";

  static String m334(name) =>
      "File ${name}. A .cbor file is sent as it is; a JSON file is encoded first.";

  static String m335(name) => "Profile ${name} put";

  static String m336(name) => "Profile ${name} removed";

  static String m337(reason) =>
      "This broker does not list its profiles through the gateway (${reason}). You can still put one; it is then served at pub/<name>.";

  static String m338(name) => "Remove profile ${name}";

  static String m339(name) =>
      "The broker stops serving pub/${name} and records it in the audit journal (profile_remove).";

  static String m340(cn) => "external · CN ${cn}";

  static String m341(size) => "history ${size} · open History";

  static String m342(id) => "${id} failed · open Links";

  static String m343(site) => "${site} · open Sites";

  static String m344(cn) => "${cn} waits · open Quarantine";

  static String m345(measure, from, to) =>
      "${measure} in and out per second from ${from} to ${to}";

  static String m346(shown, total) => "${shown} of ${total} rows";

  static String m347(up) => "downstream of ${up}";

  static String m348(level) => "needs ${level}";

  static String m349(who) => "by ${who}";

  static String m350(n) => "failed at step ${n}";

  static String m351(agent) => "Each task is a node: ${agent}/tasks/<id>";

  static String m352(site) => "TLS · certificate of the ${site} CA";

  static String m353(site) => "TLS · ${site} CA, not trusted yet";

  static String m354(site) => "TLS · ${site} CA, pinned on this computer";

  static String m355(seconds) => "hides in ${seconds} s";

  static String m356(site) => "stays until ${site} is back";

  static String m357(site) => "Tree · ${site}";

  static String m358(step) => "${step} avg";

  static String m359(rollup, from, to) => "${rollup} · ${from}–${to}";

  static String m360(at, delta, key, over) =>
      "Δ from A (${at}): ${delta} ${key} over ${over}";

  static String m361(what, range) =>
      "${what}, ${range}. Use the window below to choose the range.";

  static String m362(h, m) => "${h} h ${m} min";

  static String m363(key) => "You may not read ${key}";

  static String m364(t) => "A · ${t}";

  static String m365(min, max) => "min ${min} · max ${max}";

  static String m366(m) => "${m} min";

  static String m367(t) => "raw · ${t}";

  static String m368(s) => "${s} s";

  static String m369(name) => "Show or hide ${name}";

  static String m370(n) => "${n} d";

  static String m371(n) => "${n} h";

  static String m372(n) => "${n} min";

  static String m373(site) => "It matches · trust ${site}";

  static String m374(host) =>
      "The gateway’s certificate is not signed by this CA, or does not name ${host}. Nothing was trusted.";

  static String m375(site) => "First time on ${site} · check its certificate";

  static String m376(command) =>
      "On the broker: System › Gateway › Certificate code, or ${command} on its host.";

  static String m377(site) =>
      "${site}’s gateway uses its own CA, which this computer does not know. Compare the code with the one on the broker before you trust it; anyone on this network can announce a name.";

  static String m378(unit) => "unit ${unit}";

  static String m379(name) => "${name} did not open the key";

  static String m380(device) =>
      "The faces on ${device} changed, so the key Studio kept no longer opens. Someone with the new face cannot sign in as you.";

  static String m381(device) =>
      "The fingerprints on ${device} changed, so the key Studio kept no longer opens. Someone with the new finger cannot sign in as you.";

  static String m382(name) => "${name} was turned off for this account";

  static String m383(site) => "Checking the key with ${site}…";

  static String m384(site) => "confirm changes on ${site}";

  static String m385(days, name) =>
      "It was ${days} days since the last password here. ${name} works again after this login.";

  static String m386(site, days) =>
      "${site} asks for the password every ${days} days";

  static String m387(site, user) => "turn on unlocking ${site} as ${user}";

  static String m388(site, days) =>
      "${site} asks for the password once every ${days} days.";

  static String m389(site) =>
      "Works with ${site} and its standby. Other gateways ask for their own.";

  static String m390(site, standby) =>
      "Works with ${site} and its standby ${standby}. Other gateways ask for their own.";

  static String m391(user, site, store) =>
      "One key for ${user} on ${site}, made inside ${store}. It never leaves it; Studio never keeps your password.";

  static String m392(name) =>
      "Log in with the password. ${name} stays on for the next time.";

  static String m393(store, date) => "Key in ${store} · added ${date}";

  static String m394(name, when) => "${name} · ${when}";

  static String m395(name) => "${name} did not match 3 times";

  static String m396(site) => "to ${site}’s gateway.";

  static String m397(site) =>
      "${site} no longer allows unlocking with biometrics";

  static String m398(name) => "${name} could not be turned on";

  static String m399(site, user, role) =>
      "Logged in to ${site} as ${user} · ${role}";

  static String m400(name, site, device) =>
      "Instead of the password, ${name} opens a key that proves to ${site} it is you on ${device}.";

  static String m401(name) => "Unlock with ${name} next time?";

  static String m402(user) => "Password for ${user}";

  static String m403(host) => "${host} + standby";

  static String m404(site, max) =>
      "${site} allows it: biometric devices on, up to ${max} per user (gateway.devices). You can turn it off in the account menu › Security.";

  static String m405(site, user) => "sign in to ${site} as ${user}";

  static String m406(name) => "Turn ${name} on again after I log in";

  static String m407(device, name) =>
      "An administrator removed ${device} from your devices. Log in with the password; you can turn ${name} on again after.";

  static String m408(role, site) => "· ${role} on ${site}";

  static String m409(site) => "Unlock to open the tree of ${site}.";

  static String m410(device, name) =>
      "The gateway has no record of ${device} any more. Log in with the password; you can turn ${name} on again after.";

  static String m411(site) => "${site} does not know this key";

  static String m412(name) => "Use ${name}";

  static String m413(name) => "Unlock with ${name}";

  static String m414(d) => "up ${d}";

  static String m415(n) => "Update links: ${n}";

  static String m416(version) => "${version} stays, a link did not answer";

  static String m417(package) =>
      "Bring a zip of the package ${package} with a higher version. The broker checks it as any install and updates every link of the package.";

  static String m418(links) => "Hot start, no restart: ${links}";

  static String m419(version, when) =>
      "${version} stays installed until ${when}. A restore point is sealed for this broker and stays on it.";

  static String m420(n) => "links: ${n}";

  static String m421(n, links) => "Links that restart (${n}): ${links}";

  static String m422(link) => "Open ${link}";

  static String m423(link) => "${link} · before a restore from a backup";

  static String m424(link, version) => "${link} · ${version} · before update";

  static String m425(version, links) =>
      "These links stop and start on ${version}: ${links}. The broker puts their private data back to the restore point of the update when the update changed the store format or did not end well; after an update that ended well they keep the data they have. After it no version is kept: there is no second rollback.";

  static String m426(package, version) => "Roll back ${package} to ${version}?";

  static String m427(version) => "Roll back to ${version}…";

  static String m428(version) => "Rolled back to ${version}";

  static String m429(version) => "The links run ${version}";

  static String m430(links) => "${links}: back with all their nodes.";

  static String m431(state) =>
      "It changes the store format (from state ${state})";

  static String m432(state) => "Store format: same (state ${state})";

  static String m433(back, gone) =>
      "declared again: ${back} · not back yet or gone: ${gone}";

  static String m434(n) => "Custom package · links that run it: ${n}";

  static String m435(n) =>
      "Package of the repository · links that run it: ${n}";

  static String m436(package, from, to) => "Update ${package} ${from} → ${to}";

  static String m437(package, from) => "Update ${package} ${from} from a file";

  static String m438(package) => "${package} updated";

  static String m439(package) => "${package} update rolled back";

  static String m440(package) => "Updating ${package}";

  static String m441(package) => "Versions of ${package}";

  static String m442(version) => "What is new in ${version}";

  static String m443(v) => "Version ${v} · deployed";

  static String m444(site) => "via ${site}";

  static String m445(delimiter, header) =>
      "Read as the block reads it: delimiter ${delimiter}, ${header}";

  static String m446(keys) => "${keys} saves · Esc cancels";

  static String m447(keys) => "${keys} saves · Esc discards the changes";

  static String m448(n, who) => "${n} waiting to be let in: ${who}";

  static String m449(value) => "was ${value}";

  static String m450(n) => "Watch groups · ${n}";

  static String m451(user) => "Welcome, ${user}";

  static String m452(value) => "would run on ${value}";

  static String m453(value) => "would send ${value}";

  static String m454(value) => "would write ${value}";

  static String m455(level) => "Turning this on needs ${level} level";

  static String m456(site) => "wyrmd on ${site}";

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
    "actBackUp": MessageLookupByLibrary.simpleMessage("Back up…"),
    "actBackUpNote": MessageLookupByLibrary.simpleMessage(
      "One file with its settings, private data and package; restore it here or on another broker.",
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
    "answerButton": MessageLookupByLibrary.simpleMessage("Answer"),
    "answerFrom": MessageLookupByLibrary.simpleMessage("From"),
    "answerHint": MessageLookupByLibrary.simpleMessage(
      "Answer in your own words (Cmd+Enter)",
    ),
    "answerLink": MessageLookupByLibrary.simpleMessage("Link"),
    "answerName": MessageLookupByLibrary.simpleMessage("Name"),
    "answerRights": MessageLookupByLibrary.simpleMessage("Rights"),
    "answerRuns": MessageLookupByLibrary.simpleMessage("Runs"),
    "answerWaitingNote": MessageLookupByLibrary.simpleMessage(
      "The assistant waits for your answer. Nothing is planned before it. A restart of the broker ends a task that waits.",
    ),
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Apply"),
    "applyChanges": m6,
    "applyProfile": MessageLookupByLibrary.simpleMessage("Apply profile"),
    "approve": MessageLookupByLibrary.simpleMessage("Approve"),
    "approveBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Approve admits it as a downstream broker with the relays above. Compare the key with its sys/upstream/<this site>/key first.",
    ),
    "approveByAgent": m7,
    "approveCount": m8,
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Approve makes it an external link with its own branch and a link token; copy the token to the device. The router reloads for about a second. Reject refuses this CN from now on.",
    ),
    "approveNone": MessageLookupByLibrary.simpleMessage(
      "Tick at least one step.",
    ),
    "approveOtherSite": m9,
    "approveReasonNote": MessageLookupByLibrary.simpleMessage(
      "Approving in Studio comes with its next step. Approve with wyrm-agent for now.",
    ),
    "approveRefused": m10,
    "approveRefusedHint": MessageLookupByLibrary.simpleMessage(
      "Untick the step it names and approve the rest. When the plan is done, ask for the steps left out as a follow-up: they are approved then.",
    ),
    "approveSigns": m11,
    "askAdminFor": m12,
    "askAdminReason": MessageLookupByLibrary.simpleMessage(
      "The broker has no call to send a request to an admin yet.",
    ),
    "askButton": MessageLookupByLibrary.simpleMessage("Ask"),
    "askHint": MessageLookupByLibrary.simpleMessage(
      "Ask for a change, or a question about the network (Cmd+Enter)",
    ),
    "asksToJoin": MessageLookupByLibrary.simpleMessage("asks to join"),
    "asksToJoinRelays": m13,
    "asksToRelay": m14,
    "auditDone": MessageLookupByLibrary.simpleMessage("done"),
    "auditNeeds": MessageLookupByLibrary.simpleMessage(
      "The audit needs config on sys/audit.",
    ),
    "auditRefused": m15,
    "back": MessageLookupByLibrary.simpleMessage("Back"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("Back to Links"),
    "backupPassphrase": MessageLookupByLibrary.simpleMessage(
      "Passphrase of the backup",
    ),
    "backupPassphraseNote": MessageLookupByLibrary.simpleMessage(
      "Only for a backup sealed with one. One sealed for its site needs none and opens only on a broker with that site\'s keys. Studio never stores it.",
    ),
    "backupReplaces": m16,
    "backupRightsAsk": MessageLookupByLibrary.simpleMessage(
      "the broker asks if needed",
    ),
    "backupRightsNote": MessageLookupByLibrary.simpleMessage(
      "Needed when the link has grants or a network allowlist: without it the broker lists them and installs nothing. Its token, certificate and requester key are new.",
    ),
    "bakAbout": m17,
    "bakAll": MessageLookupByLibrary.simpleMessage("All"),
    "bakBackUp": MessageLookupByLibrary.simpleMessage("Back up…"),
    "bakCancelDownload": MessageLookupByLibrary.simpleMessage(
      "Cancel the download",
    ),
    "bakCard": MessageLookupByLibrary.simpleMessage("Backups"),
    "bakCardEmpty": MessageLookupByLibrary.simpleMessage(
      "No backup is kept on the broker.",
    ),
    "bakCardNote": m18,
    "bakCardOld": MessageLookupByLibrary.simpleMessage(
      "This broker has no backups from Studio (it runs a wyrmd before ADR 0048). Use the commands below.",
    ),
    "bakChooseConnection": MessageLookupByLibrary.simpleMessage(
      "Choose a link and a connection",
    ),
    "bakChooseFolder": m19,
    "bakConsistent": MessageLookupByLibrary.simpleMessage(
      "Each store is read at one consistent moment, inside its own read transaction; the broker keeps running and writing.",
    ),
    "bakDo": MessageLookupByLibrary.simpleMessage("Back up"),
    "bakDoLink": m20,
    "bakDoneSub": m21,
    "bakDoneTitle": MessageLookupByLibrary.simpleMessage("Backup ready"),
    "bakDownload": MessageLookupByLibrary.simpleMessage("Download…"),
    "bakDownloading": m22,
    "bakFactBy": MessageLookupByLibrary.simpleMessage("Made by"),
    "bakFactContents": MessageLookupByLibrary.simpleMessage("Contents"),
    "bakFactLink": MessageLookupByLibrary.simpleMessage("Link"),
    "bakFactSealed": MessageLookupByLibrary.simpleMessage("Secrets"),
    "bakFactSent": MessageLookupByLibrary.simpleMessage("Sent to"),
    "bakFailed": MessageLookupByLibrary.simpleMessage(
      "The broker did not make the backup",
    ),
    "bakFailedTitle": m23,
    "bakKeysNeedPassphrase": MessageLookupByLibrary.simpleMessage(
      "Give a passphrase of at least 12 characters below: the keys are sealed with it.",
    ),
    "bakKeysNeverSent": MessageLookupByLibrary.simpleMessage(
      "A backup with Keys and secrets is never sent: download it at the site\'s own gateway.",
    ),
    "bakKeysWarning": m24,
    "bakKindFull": MessageLookupByLibrary.simpleMessage("broker"),
    "bakKindLink": m25,
    "bakKindPreRestore": MessageLookupByLibrary.simpleMessage(
      "before a restore",
    ),
    "bakKindPreUpdate": MessageLookupByLibrary.simpleMessage(
      "before an update",
    ),
    "bakLast30": MessageLookupByLibrary.simpleMessage("Last 30 days"),
    "bakLast7": MessageLookupByLibrary.simpleMessage("Last 7 days"),
    "bakLast90": MessageLookupByLibrary.simpleMessage("Last 90 days"),
    "bakLinkRestoreNote": MessageLookupByLibrary.simpleMessage(
      "Restore it with Links › Add a link › From backup: on this broker (it replaces the link, after a restore point) or on another one as a new link.",
    ),
    "bakNeedsConfig": MessageLookupByLibrary.simpleMessage("config on sys"),
    "bakNeedsConfigLinks": MessageLookupByLibrary.simpleMessage(
      "config on sys/links",
    ),
    "bakNoBackups": MessageLookupByLibrary.simpleMessage(
      "This broker makes no backups for Studio (a wyrmd before ADR 0048).",
    ),
    "bakNoConnections": MessageLookupByLibrary.simpleMessage(
      "This link has no connection.",
    ),
    "bakNoSendLinks": MessageLookupByLibrary.simpleMessage(
      "The host lists no file-store link for backups (backups.send_links in wyrmd.json5).",
    ),
    "bakOffline": MessageLookupByLibrary.simpleMessage(
      "When the broker does not start",
    ),
    "bakOfflineNote": MessageLookupByLibrary.simpleMessage(
      "The offline way, for a broker that does not start or a host without Studio: a copy of data_dir made on the host. The steps, ready to copy:",
    ),
    "bakOpen": MessageLookupByLibrary.simpleMessage("Open"),
    "bakPassphrase": MessageLookupByLibrary.simpleMessage(
      "Passphrase for the keys and secrets",
    ),
    "bakPassphraseLink": MessageLookupByLibrary.simpleMessage(
      "Passphrase for its private data",
    ),
    "bakPassphraseLinkNote": MessageLookupByLibrary.simpleMessage(
      "With it the file opens on any broker. Without it Private data is sealed for this site and opens only on a broker with its keys. Studio never stores it.",
    ),
    "bakPassphraseNote": MessageLookupByLibrary.simpleMessage(
      "Seals Keys and secrets and the links\' secrets (Argon2id). Without it the keys stay out and link secrets are sealed for this site. Studio never stores it.",
    ),
    "bakPassphraseShort": m26,
    "bakProgressSub": MessageLookupByLibrary.simpleMessage(
      "You can close this; the broker finishes it and keeps it under Backups.",
    ),
    "bakProgressTitle": m27,
    "bakRemoveNote": MessageLookupByLibrary.simpleMessage(
      "The file is deleted from the broker. A copy you downloaded or sent stays.",
    ),
    "bakRemoveRow": MessageLookupByLibrary.simpleMessage(
      "Remove it from the broker",
    ),
    "bakRemoveTitle": m28,
    "bakRestore": MessageLookupByLibrary.simpleMessage("Restore…"),
    "bakRowFailed": MessageLookupByLibrary.simpleMessage("failed"),
    "bakRowRunning": m29,
    "bakRowSending": m30,
    "bakSaved": m31,
    "bakSavedNote": m32,
    "bakSavedTo": m33,
    "bakSealedBroker": m34,
    "bakSealedNone": MessageLookupByLibrary.simpleMessage("none in it"),
    "bakSealedPassphrase": MessageLookupByLibrary.simpleMessage(
      "sealed with the passphrase",
    ),
    "bakSecConfig": MessageLookupByLibrary.simpleMessage(
      "wyrmd.json5 (read only)",
    ),
    "bakSecConfigNote": MessageLookupByLibrary.simpleMessage(
      "The configuration with secrets masked, for reference; a restore never writes it.",
    ),
    "bakSecControl": MessageLookupByLibrary.simpleMessage("Control plane"),
    "bakSecControlNote": MessageLookupByLibrary.simpleMessage(
      "Registry (links, grants, peers, tokens), users and roles, flow store, audit. Needed to restore anything else.",
    ),
    "bakSecData": MessageLookupByLibrary.simpleMessage("Private data"),
    "bakSecDataNote": MessageLookupByLibrary.simpleMessage(
      "Its secrets and its private directory: the runtime edits of a driver (connections, devices, points), a portable app\'s store.",
    ),
    "bakSecDataflows": MessageLookupByLibrary.simpleMessage("Dataflows"),
    "bakSecDataflowsNote": MessageLookupByLibrary.simpleMessage(
      "The artifacts of the flow engine; the flows themselves are in the control plane.",
    ),
    "bakSecHistory": MessageLookupByLibrary.simpleMessage("History"),
    "bakSecHistoryNote": MessageLookupByLibrary.simpleMessage(
      "The recorded days of the historian and its index.",
    ),
    "bakSecKeys": MessageLookupByLibrary.simpleMessage("Keys and secrets"),
    "bakSecKeysNote": MessageLookupByLibrary.simpleMessage(
      "Site CA, state and secrets keys, gateway keys, link tokens and sealed secrets. Sealed with the passphrase below.",
    ),
    "bakSecLinkHistoryNote": MessageLookupByLibrary.simpleMessage(
      "The recorded rows of its points.",
    ),
    "bakSecLinks": MessageLookupByLibrary.simpleMessage("Links"),
    "bakSecLinksNote": MessageLookupByLibrary.simpleMessage(
      "Per link: its definition, its secrets and its private data, sealed. Their packages go in too.",
    ),
    "bakSecPackage": MessageLookupByLibrary.simpleMessage("Package"),
    "bakSecPackageNote": MessageLookupByLibrary.simpleMessage(
      "The package it runs, as its files, so it restores where the repository cannot be reached.",
    ),
    "bakSecPackages": MessageLookupByLibrary.simpleMessage(
      "Installed packages",
    ),
    "bakSecPackagesNote": MessageLookupByLibrary.simpleMessage(
      "Every installed package as its files, so a restore needs no repository.",
    ),
    "bakSecSettings": MessageLookupByLibrary.simpleMessage("Settings"),
    "bakSecSettingsNote": MessageLookupByLibrary.simpleMessage(
      "The link\'s definition: driver, mode, params, grants.",
    ),
    "bakSecStorage": MessageLookupByLibrary.simpleMessage("Broker storage"),
    "bakSecStorageNote": MessageLookupByLibrary.simpleMessage(
      "The storage tree and its values, with a JSON export for people.",
    ),
    "bakSecretsHost": MessageLookupByLibrary.simpleMessage(
      "The host does not let secrets leave this broker (backups.export_secrets is false in wyrmd.json5). Secrets are sealed for this site.",
    ),
    "bakSecretsUpstream": MessageLookupByLibrary.simpleMessage(
      "This session reaches the site through an upstream broker: its keys and a passphrase-sealed file never travel up. Sign in at the site\'s own gateway.",
    ),
    "bakSend": MessageLookupByLibrary.simpleMessage("Send"),
    "bakSendConnection": MessageLookupByLibrary.simpleMessage("Connection"),
    "bakSendFailed": m35,
    "bakSendFolder": MessageLookupByLibrary.simpleMessage(
      "Folder (set on the host)",
    ),
    "bakSendLink": MessageLookupByLibrary.simpleMessage("File-store link"),
    "bakSendPath": MessageLookupByLibrary.simpleMessage(
      "File name or sub-path",
    ),
    "bakSendPathNote": MessageLookupByLibrary.simpleMessage(
      "Empty: the backup\'s own file name. A sub-folder must exist; a name that exists is refused, never replaced.",
    ),
    "bakSending": m36,
    "bakSensitive": MessageLookupByLibrary.simpleMessage(
      "A backup is as sensitive as the broker\'s data directory: keep it where only administrators reach it.",
    ),
    "bakShow": MessageLookupByLibrary.simpleMessage("Show in Backups"),
    "bakSub": MessageLookupByLibrary.simpleMessage(
      "Pick what goes in. One .wyrm-backup file (a zip with a manifest); the broker keeps running while it is made.",
    ),
    "bakSubLink": m37,
    "bakTagAlways": MessageLookupByLibrary.simpleMessage("always"),
    "bakTagPassphrase": MessageLookupByLibrary.simpleMessage("passphrase"),
    "bakTagSite": MessageLookupByLibrary.simpleMessage("sealed for this site"),
    "bakTitle": m38,
    "bakTitleLink": m39,
    "bakWhatGoesIn": MessageLookupByLibrary.simpleMessage("What goes in"),
    "bakWhere": MessageLookupByLibrary.simpleMessage("Where"),
    "bakWhereBroker": MessageLookupByLibrary.simpleMessage(
      "Keep on the broker",
    ),
    "bakWhereBrokerNote": m40,
    "bakWhereComputer": MessageLookupByLibrary.simpleMessage("This computer"),
    "bakWhereComputerNote": m41,
    "bakWhereStore": MessageLookupByLibrary.simpleMessage("File store link…"),
    "bakWhereStoreNote": MessageLookupByLibrary.simpleMessage(
      "A file-store link (S3, WebDAV, a disk) takes it from the broker without passing through this computer.",
    ),
    "bakWorking": MessageLookupByLibrary.simpleMessage("Backing up…"),
    "bindHint": MessageLookupByLibrary.simpleMessage(
      "Drag an output here to bind",
    ),
    "block": MessageLookupByLibrary.simpleMessage("Block"),
    "blockForm": MessageLookupByLibrary.simpleMessage("Form"),
    "blockInputs": MessageLookupByLibrary.simpleMessage("Inputs"),
    "blockOutputs": MessageLookupByLibrary.simpleMessage("Outputs"),
    "blocksCount": m42,
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
    "brokersDevices": m43,
    "builtIn": MessageLookupByLibrary.simpleMessage("built in"),
    "builtInDriver": m44,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Built into wyrmd · nothing to download",
    ),
    "bupBackOn": m45,
    "bupBackOnNote": m46,
    "bupCard": MessageLookupByLibrary.simpleMessage("Broker version"),
    "bupCardAvailable": m47,
    "bupCardCurrent": m48,
    "bupCardRolledBack": m49,
    "bupCardTrial": m50,
    "bupCheckConfig": MessageLookupByLibrary.simpleMessage(
      "The new binary accepts this configuration",
    ),
    "bupCheckConfigNote": MessageLookupByLibrary.simpleMessage(
      "The new wyrmd runs its check on the configuration of this broker.",
    ),
    "bupCheckRoom": MessageLookupByLibrary.simpleMessage("Room for it"),
    "bupCheckRoomNote": MessageLookupByLibrary.simpleMessage(
      "The binary and the pre-update backup fit the disk.",
    ),
    "bupCheckSchema": MessageLookupByLibrary.simpleMessage(
      "A store format may move",
    ),
    "bupCheckSchemaNote": m51,
    "bupCheckSigned": MessageLookupByLibrary.simpleMessage(
      "The release is signed",
    ),
    "bupCheckSignedNote": MessageLookupByLibrary.simpleMessage(
      "The Ed25519 signature of the release key and the SHA-256 of the archive.",
    ),
    "bupCheckStandby": MessageLookupByLibrary.simpleMessage(
      "A standby is updated first",
    ),
    "bupCheckStandbyNote": MessageLookupByLibrary.simpleMessage(
      "When a standby follows this broker and the release changes the replication protocol, the broker refuses until the standby runs the new version.",
    ),
    "bupChecked": MessageLookupByLibrary.simpleMessage(
      "Checked before anything changes",
    ),
    "bupClosing": MessageLookupByLibrary.simpleMessage(
      "Closing Studio does not stop it.",
    ),
    "bupDo": MessageLookupByLibrary.simpleMessage("Back up and update"),
    "bupDoneBack": MessageLookupByLibrary.simpleMessage(
      "Router, gateway, links back",
    ),
    "bupDoneConfirmed": MessageLookupByLibrary.simpleMessage("Confirmed"),
    "bupDonePreBackup": MessageLookupByLibrary.simpleMessage(
      "Pre-update backup",
    ),
    "bupDoneRestart": m52,
    "bupDoneStaged": m53,
    "bupExternal": MessageLookupByLibrary.simpleMessage(
      "This broker does not replace itself (updates.mode: \"external\": a container or a distribution package). The image is changed where the container is defined, and the data volume carries the state across.",
    ),
    "bupExternalBackup": MessageLookupByLibrary.simpleMessage(
      "Studio still makes the backup for you before you do it.",
    ),
    "bupFactAudit": MessageLookupByLibrary.simpleMessage("Audit"),
    "bupFactDown": MessageLookupByLibrary.simpleMessage("Without the broker"),
    "bupFactLinks": MessageLookupByLibrary.simpleMessage("Links back"),
    "bupFactNow": MessageLookupByLibrary.simpleMessage("Now"),
    "bupFactReason": MessageLookupByLibrary.simpleMessage("Reason"),
    "bupFactRollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "bupFactTried": MessageLookupByLibrary.simpleMessage("Tried"),
    "bupFactVersion": MessageLookupByLibrary.simpleMessage("Version"),
    "bupHide": MessageLookupByLibrary.simpleMessage("Hide"),
    "bupHow": MessageLookupByLibrary.simpleMessage("How it goes"),
    "bupLinksBack": m54,
    "bupLost": m55,
    "bupMakeBackup": MessageLookupByLibrary.simpleMessage("Make the backup"),
    "bupMeanwhile": MessageLookupByLibrary.simpleMessage(
      "Links on other machines walk to their next endpoint or wait; devices keep their last outputs. Values recorded by links during the restart are not lost if the link buffers them.",
    ),
    "bupNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "Needs config on sys · audited",
    ),
    "bupOnTrial": MessageLookupByLibrary.simpleMessage(
      "The gateway is back; the new version is on trial.",
    ),
    "bupOpenLog": m56,
    "bupPillContainer": MessageLookupByLibrary.simpleMessage("container"),
    "bupPillRestarting": MessageLookupByLibrary.simpleMessage("restarting"),
    "bupReconnecting": MessageLookupByLibrary.simpleMessage("Reconnecting…"),
    "bupRestarting": m57,
    "bupRollBackNote": MessageLookupByLibrary.simpleMessage(
      "The broker restarts on the version before and restores the pre-update backup of its control plane. Changes made after the update are lost.",
    ),
    "bupRollBackTitle": m58,
    "bupRollBackUntil": m59,
    "bupRolledBack": MessageLookupByLibrary.simpleMessage("Update rolled back"),
    "bupRuns": m60,
    "bupRunsNote": m61,
    "bupSeconds": m62,
    "bupShow": MessageLookupByLibrary.simpleMessage("Show…"),
    "bupStep1": MessageLookupByLibrary.simpleMessage(
      "Pre-update backup of the control plane, secrets sealed (kept until the update is confirmed).",
    ),
    "bupStep2": m63,
    "bupStep3": m64,
    "bupStep4": m65,
    "bupStep5": m66,
    "bupSub": MessageLookupByLibrary.simpleMessage(
      "From the release channel of this broker · the broker restarts once",
    ),
    "bupTitle": m67,
    "bupType": m68,
    "bupUpdate": MessageLookupByLibrary.simpleMessage("Update…"),
    "bupUpdated": m69,
    "bupUpdating": m70,
    "bupUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "This screen reconnects by itself.",
    ),
    "caSigned": m71,
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
    "cbNote": m72,
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
    "checkAtRun": MessageLookupByLibrary.simpleMessage(
      "checked when it runs: an earlier step makes this node",
    ),
    "checkFailed": MessageLookupByLibrary.simpleMessage(
      "The package did not pass: bring another one.",
    ),
    "checkNow": MessageLookupByLibrary.simpleMessage(
      "checked against the live tree",
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
    "childCount": m73,
    "childrenNote": MessageLookupByLibrary.simpleMessage(
      "Select a row: a node opens in the tree, a value opens in the inspector.",
    ),
    "choicesConfirm": MessageLookupByLibrary.simpleMessage("Write the plan"),
    "choicesFromCard": m74,
    "choicesNoAnswer": MessageLookupByLibrary.simpleMessage("no answer"),
    "choicesNote": MessageLookupByLibrary.simpleMessage(
      "Or answer in your own words below.",
    ),
    "choicesOwnWords": m75,
    "choicesPickOne": MessageLookupByLibrary.simpleMessage(
      "Pick an option, or answer in your own words below.",
    ),
    "choicesTitle": MessageLookupByLibrary.simpleMessage("The assistant asks"),
    "chooseBackupFile": MessageLookupByLibrary.simpleMessage(
      "Choose a .wyrm-link file",
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
    "colDevices": MessageLookupByLibrary.simpleMessage("Devices"),
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
    "connectNote": m76,
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
    "dataDir": m77,
    "dataflow": MessageLookupByLibrary.simpleMessage("Dataflow"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Its rights here are cut now and its next connection waits in quarantine. Its sites stay below it.",
    ),
    "deauthorizeTitle": m78,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Decide in Links"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "A link in quarantine is approved or rejected in Links › Quarantine.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("decide in Sites"),
    "deploy": MessageLookupByLibrary.simpleMessage("Deploy"),
    "deployAskMessage": m79,
    "deployAskTitle": MessageLookupByLibrary.simpleMessage("Deploy this flow?"),
    "deployInside": MessageLookupByLibrary.simpleMessage(
      "Go back to the flow to deploy",
    ),
    "deployedByWho": m80,
    "deploying": MessageLookupByLibrary.simpleMessage("Deploying…"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Design gallery"),
    "designGalleryNote": MessageLookupByLibrary.simpleMessage(
      "Every part of the design system (development builds).",
    ),
    "deviceForgetText": MessageLookupByLibrary.simpleMessage(
      "The record goes from the gateway.",
    ),
    "deviceForgetTitle": m81,
    "deviceLine": m82,
    "deviceRemoveText": m83,
    "deviceRemoveTitle": m84,
    "devicesNone": MessageLookupByLibrary.simpleMessage("No devices."),
    "disableUser": MessageLookupByLibrary.simpleMessage("Disable"),
    "disableUserNote": MessageLookupByLibrary.simpleMessage(
      "A disabled user cannot log in; their roles stay.",
    ),
    "discard": MessageLookupByLibrary.simpleMessage("Discard"),
    "discardAll": MessageLookupByLibrary.simpleMessage("Discard all"),
    "discoverFound": m85,
    "discoverLooking": m86,
    "discoverNoneTitle": m87,
    "discoverNothing": MessageLookupByLibrary.simpleMessage("Nothing found"),
    "discoverPanel": MessageLookupByLibrary.simpleMessage(
      "Gateways on this network",
    ),
    "discoverProbed": m88,
    "discoverProbing": m89,
    "doneLeftOutNote": m90,
    "doneNote": MessageLookupByLibrary.simpleMessage(
      "The task is done. Its record keeps the plan and the log.",
    ),
    "doneOnTheDevice": m91,
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
    "editParamsOf": m92,
    "enableUser": MessageLookupByLibrary.simpleMessage("Enable"),
    "errAdviceBroker": m93,
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
    "errAdviceInputField": m94,
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
    "errAdviceRightsRole": m95,
    "errAdviceStudio": MessageLookupByLibrary.simpleMessage(
      "Try it again; restart Studio if it keeps happening.",
    ),
    "errAdviceUnsupported": MessageLookupByLibrary.simpleMessage(
      "This broker or link does not have this call; it may be older than Studio expects.",
    ),
    "errBackToForm": MessageLookupByLibrary.simpleMessage("Back to the form"),
    "errCallOn": m96,
    "errChipStudio": m97,
    "errCopied": MessageLookupByLibrary.simpleMessage("Copied"),
    "errCopyDetails": MessageLookupByLibrary.simpleMessage("Copy details"),
    "errCopyReport": MessageLookupByLibrary.simpleMessage("Copy report"),
    "errDetails": MessageLookupByLibrary.simpleMessage("Details"),
    "errDetailsCopied": MessageLookupByLibrary.simpleMessage(
      "The details are on the clipboard.",
    ),
    "errDoDeploy": m98,
    "errDoInstall": m99,
    "errDoList": m100,
    "errDoLogIn": m101,
    "errDoOpen": m102,
    "errDoRead": m103,
    "errDoRemove": m104,
    "errDoRun": m105,
    "errDoSave": m106,
    "errDoStart": m107,
    "errDoStep": m108,
    "errDoStop": m109,
    "errDoWrite": m110,
    "errDoingDeploy": m111,
    "errDoingInstall": m112,
    "errDoingList": m113,
    "errDoingLogIn": m114,
    "errDoingOpen": m115,
    "errDoingRead": m116,
    "errDoingRemove": m117,
    "errDoingRun": m118,
    "errDoingSave": m119,
    "errDoingStart": m120,
    "errDoingStop": m121,
    "errDoingWrite": m122,
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
    "errNounRun": m123,
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
    "errSilentReach": m124,
    "errSilentStatus": m125,
    "errStatusLine": m126,
    "errThingBroker": MessageLookupByLibrary.simpleMessage("the broker"),
    "errThingThis": MessageLookupByLibrary.simpleMessage("this"),
    "errTimeLocal": m127,
    "errTitleBroker": m128,
    "errTitleBrokerNoSite": m129,
    "errTitleBusy": m130,
    "errTitleGone": m131,
    "errTitleHistory": m132,
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
    "errTitleReach": m133,
    "errTitleReachNoSite": MessageLookupByLibrary.simpleMessage(
      "The broker did not answer",
    ),
    "errTitleRead": m134,
    "errTitleRights": m135,
    "errTitleStream": m136,
    "errTitleStudio": m137,
    "errTitleUnsupported": m138,
    "errTryAgain": MessageLookupByLibrary.simpleMessage("Try again"),
    "errTryAgainIn": m139,
    "errUserRole": m140,
    "errWhatYouCanDo": MessageLookupByLibrary.simpleMessage("What you can do"),
    "errWriteNote": MessageLookupByLibrary.simpleMessage(
      "A write that timed out may still have been applied. Check the value before you send it again.",
    ),
    "eventNone": MessageLookupByLibrary.simpleMessage("not yet"),
    "everySeconds": m141,
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
    "fatalMoveFailed": m142,
    "fatalNote": m143,
    "fatalQuit": MessageLookupByLibrary.simpleMessage("Quit"),
    "fatalTitle": MessageLookupByLibrary.simpleMessage(
      "Studio could not start",
    ),
    "faultBody": MessageLookupByLibrary.simpleMessage(
      "The rest of Studio still works; values and actions elsewhere are not affected.",
    ),
    "faultDrawAgain": MessageLookupByLibrary.simpleMessage("Draw it again"),
    "faultProblem": m144,
    "faultThisPart": MessageLookupByLibrary.simpleMessage("this part"),
    "faultTitle": m145,
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
    "findOnNetwork": MessageLookupByLibrary.simpleMessage(
      "Find on this network",
    ),
    "firesAtDeploy": MessageLookupByLibrary.simpleMessage("fires at deploy"),
    "firesAtDeployNote": MessageLookupByLibrary.simpleMessage(
      "A parameter sends its value when the flow starts, so this writes at every deploy.",
    ),
    "firesAtStartNote": MessageLookupByLibrary.simpleMessage(
      "This field sends its value when the flow starts, so this wire writes at every deploy.",
    ),
    "firstSeen": m146,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "The draft does not validate.",
    ),
    "flowBack": MessageLookupByLibrary.simpleMessage("Back"),
    "flowDeployed": m147,
    "flowError": m148,
    "flowName": MessageLookupByLibrary.simpleMessage("Flow id"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.",
    ),
    "flowPropertiesNote2": MessageLookupByLibrary.simpleMessage(
      "A bound field shows the value that comes in; its wire and source light when you point at it. The link icon goes to the source or unbinds.",
    ),
    "flowStopped": m149,
    "flowVersion": m150,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "A deploy needs config on dataflows; the gateway adds your proofs for each target. Viewers can open a flow and only look.",
    ),
    "flowsOn": m151,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Each flow runs in the broker. You edit a draft; nothing changes until you deploy it.",
    ),
    "fmBlocks": m152,
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
    "fmUnpinField": m153,
    "followUpAsk": m154,
    "followUpLeftOut": MessageLookupByLibrary.simpleMessage(
      "Ask for the steps left out",
    ),
    "fromAddress": m155,
    "fromBackup": MessageLookupByLibrary.simpleMessage("From a backup"),
    "fromBackupNote": MessageLookupByLibrary.simpleMessage(
      "A link backup (.wyrm-link) made by Back up… on a link: its settings, private data and package. It comes back under its own id or a new one.",
    ),
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "From the official list",
    ),
    "gateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "gatewayAnswered": m156,
    "gatewayNoAnswer": m157,
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("Gateway URL"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445, or several separated by commas",
    ),
    "gatewayUser": MessageLookupByLibrary.simpleMessage("Gateway user"),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git repository (HTTPS)",
    ),
    "goTo": m158,
    "goToSource": MessageLookupByLibrary.simpleMessage("Go to source"),
    "goUp": MessageLookupByLibrary.simpleMessage("Go up"),
    "grantFor": m159,
    "grantLevel": MessageLookupByLibrary.simpleMessage("Level"),
    "grantPath": MessageLookupByLibrary.simpleMessage("Key or pattern"),
    "groupBackup": MessageLookupByLibrary.simpleMessage("Backup"),
    "groupChange": MessageLookupByLibrary.simpleMessage("Change"),
    "groupDevices": MessageLookupByLibrary.simpleMessage("Devices"),
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
    "hideSteps": MessageLookupByLibrary.simpleMessage("Hide steps"),
    "historianKeep": m160,
    "historianSeries": m161,
    "historianSize": m162,
    "historyFooter": MessageLookupByLibrary.simpleMessage(
      "Sync links read the historian\'s change journal, so nothing is lost while a database is down.",
    ),
    "historyOf": m163,
    "historyUnavailable": MessageLookupByLibrary.simpleMessage(
      "history unavailable",
    ),
    "historyUnavailableTip": m164,
    "holdUnknown": MessageLookupByLibrary.simpleMessage(
      "Hold unknown connections here",
    ),
    "holdUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Off (with Allow all links off too): unknown certificates are ignored.",
    ),
    "hostsWithStandby": m165,
    "howItRunsThere": MessageLookupByLibrary.simpleMessage("How it runs there"),
    "importPoints": MessageLookupByLibrary.simpleMessage(
      "Import CSV or DSA tree",
    ),
    "inputsCount": m166,
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
    "installedOn": m167,
    "instancesInFlow": m168,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Not a gateway URL (http:// or https:// and a host)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Issue"),
    "keyCopied": MessageLookupByLibrary.simpleMessage("Key copied"),
    "keysCopied": m169,
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
    "lag": m170,
    "languageName": MessageLookupByLibrary.simpleMessage("English"),
    "lastRead": m171,
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
    "linksAlready": m172,
    "linksCount": m173,
    "linksLocalNote": m174,
    "linksOn": m175,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "Connections with a certificate from this site that no link is set up for. They can read and write nothing until you approve them.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "They run on their own machines and connect with a certificate from this site. You decide what they may reach and whether they may stay; the device itself is updated where it runs.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.",
    ),
    "listAnd": m176,
    "listFailedTip": m177,
    "liveRefused": MessageLookupByLibrary.simpleMessage(
      "You cannot read every source and target of this flow",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Loading…"),
    "lockKept": m178,
    "lockText": m179,
    "lockTitle": MessageLookupByLibrary.simpleMessage("Studio is locked"),
    "lockUnlock": MessageLookupByLibrary.simpleMessage("Unlock"),
    "lockWrongPassword": MessageLookupByLibrary.simpleMessage(
      "The password is wrong.",
    ),
    "logEmpty": MessageLookupByLibrary.simpleMessage("No lines."),
    "logIn": MessageLookupByLibrary.simpleMessage("Log in"),
    "logInLead": MessageLookupByLibrary.simpleMessage(
      "to a broker’s gateway. Your role there decides what you can change.",
    ),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Sign in to a WYRM gateway.",
    ),
    "logOf": m180,
    "logOut": MessageLookupByLibrary.simpleMessage("Log out"),
    "lookAgain": MessageLookupByLibrary.simpleMessage("Look again"),
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
    "mbInUse": m181,
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
    "mbUpdateTo": m182,
    "mbUsed": m183,
    "mbVersion": m184,
    "menuLanguage": MessageLookupByLibrary.simpleMessage("Language"),
    "menuOther": MessageLookupByLibrary.simpleMessage("Other"),
    "menuSubtitle": m185,
    "menuTheme": MessageLookupByLibrary.simpleMessage("Theme"),
    "messagesPerSecond": MessageLookupByLibrary.simpleMessage(
      "Router messages per second",
    ),
    "metaFailedTip": m186,
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
    "monthsShort": MessageLookupByLibrary.simpleMessage(
      "Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec",
    ),
    "more": MessageLookupByLibrary.simpleMessage("More"),
    "moreBytes": m187,
    "moreLines": m188,
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
    "nSelected": m189,
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
    "needsLevelYouHave": m190,
    "needsLevelYouHaveIt": m191,
    "networkError": MessageLookupByLibrary.simpleMessage("Connection problem"),
    "newCertificate": MessageLookupByLibrary.simpleMessage("new certificate"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("New dataflow"),
    "newTask": MessageLookupByLibrary.simpleMessage("New task"),
    "newValue": MessageLookupByLibrary.simpleMessage("New value"),
    "no": MessageLookupByLibrary.simpleMessage("no"),
    "noActionReason": m192,
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
    "noParamReason": m193,
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
    "noUpstream": m194,
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
    "noteKnownAs": m195,
    "noteNew": MessageLookupByLibrary.simpleMessage(
      "its own CA · check the code before you trust it",
    ),
    "notePinned": m196,
    "notePlain": MessageLookupByLibrary.simpleMessage(
      "plain http on this computer",
    ),
    "noteTreeNode": MessageLookupByLibrary.simpleMessage(
      "A point of the tree. A read-only point has no input; binding into a writable one writes ~set.",
    ),
    "noteTrusted": MessageLookupByLibrary.simpleMessage(
      "certificate trusted by this computer",
    ),
    "noteWyrmd": m197,
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
    "openItsTreeNote": m198,
    "openNodeInExplorer": m199,
    "openSettings": MessageLookupByLibrary.simpleMessage("Open settings"),
    "openingTree": MessageLookupByLibrary.simpleMessage("Opening the tree"),
    "openingTreeOf": m200,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Operate · runs now",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Runs on the device with your rights and is written to the audit.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("package"),
    "packageNamed": m201,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Package from your repository · SHA-256 checked against the index on download",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("Package URL (HTTPS)"),
    "pairsCount": m202,
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
    "paramCount": m203,
    "paramsJson": m204,
    "paramsNotJson": m205,
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
    "pickedFrom": m206,
    "pickedWithStandby": m207,
    "pinField": MessageLookupByLibrary.simpleMessage("Pin to block"),
    "pinLocked": MessageLookupByLibrary.simpleMessage(
      "A bound field stays on the block",
    ),
    "ping": MessageLookupByLibrary.simpleMessage("Ping"),
    "planCard": MessageLookupByLibrary.simpleMessage("Plan"),
    "planChecked": MessageLookupByLibrary.simpleMessage(
      "awaiting approval · checked",
    ),
    "planCheckedPartly": m208,
    "planNeedsStep": m209,
    "planNote": MessageLookupByLibrary.simpleMessage(
      "The plan is in the task\'s record. Studio shows it when the gateway can read documents (docs/studio.md §10 item 11). Read it with wyrm-agent for now.",
    ),
    "planSaved": m210,
    "planSavedSecrets": m211,
    "planSecretNote": MessageLookupByLibrary.simpleMessage(
      "A secret argument is not shown. The approval is still for the value the plan holds.",
    ),
    "planSleep": m212,
    "planSteps": m213,
    "planTimeout": m214,
    "planWaiting": MessageLookupByLibrary.simpleMessage(
      "The plan waits for approval. Nothing runs before it.",
    ),
    "planWhyNote": MessageLookupByLibrary.simpleMessage(
      "The lines after “why” and the warnings come from the model. Read the key and the arguments of each step: they are what runs.",
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
    "pointsCount": m215,
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Values update live. Edits are staged in this session; nothing is written to the device until you apply.",
    ),
    "portBad": MessageLookupByLibrary.simpleMessage("The port is 1 to 65535."),
    "portsCount": m216,
    "preloadBlocks": MessageLookupByLibrary.simpleMessage(
      "Reading the flow blocks",
    ),
    "preloadFlows": MessageLookupByLibrary.simpleMessage("Reading the flows"),
    "preloadLater": m217,
    "preloadLinks": MessageLookupByLibrary.simpleMessage("Reading the links"),
    "preloadSites": MessageLookupByLibrary.simpleMessage("Reading the sites"),
    "preloadTree": m218,
    "previewInvalid": m219,
    "previewTag": MessageLookupByLibrary.simpleMessage("preview"),
    "probeButton": MessageLookupByLibrary.simpleMessage("Probe"),
    "probeNote": MessageLookupByLibrary.simpleMessage(
      "One HTTPS request per address to /api/info, 16 at a time, at most 1024 addresses. Ask before probing a network that is not yours.",
    ),
    "probePortField": MessageLookupByLibrary.simpleMessage("Port"),
    "probeRangeField": MessageLookupByLibrary.simpleMessage("Range"),
    "probeRangeTitle": MessageLookupByLibrary.simpleMessage(
      "Probe a range instead",
    ),
    "problemCodeMismatch": MessageLookupByLibrary.simpleMessage(
      "Not offered: the CA code it announced is not the code of its CA.",
    ),
    "problemNoAnswer": m220,
    "problemNoCa": MessageLookupByLibrary.simpleMessage(
      "Not offered: this computer does not trust its certificate, and it sends no CA to check.",
    ),
    "problemNoInfo": MessageLookupByLibrary.simpleMessage(
      "Not offered: this wyrmd is older than Studio needs (no /api/info).",
    ),
    "problemNoName": MessageLookupByLibrary.simpleMessage(
      "Not offered: its certificate names neither this address nor a host name. Type its address.",
    ),
    "problemPlainHttp": MessageLookupByLibrary.simpleMessage(
      "Not offered: plain http off this computer is refused (insecure_plaintext).",
    ),
    "problemStudioTooOld": m221,
    "problems": MessageLookupByLibrary.simpleMessage("Problems"),
    "problemsClear": MessageLookupByLibrary.simpleMessage("Clear all"),
    "problemsClose": MessageLookupByLibrary.simpleMessage("Close problems"),
    "problemsCount": m222,
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
    "qInstalled": m223,
    "qInstalling": m224,
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
    "rangeBadPart": MessageLookupByLibrary.simpleMessage(
      "Each part of an address is 0 to 255.",
    ),
    "rangeBadPrefix": MessageLookupByLibrary.simpleMessage(
      "The prefix is 0 to 32.",
    ),
    "rangeBadText": MessageLookupByLibrary.simpleMessage(
      "Write an IPv4 range, as 10.0.7.0/24.",
    ),
    "rangeTooBig": MessageLookupByLibrary.simpleMessage(
      "At most 1024 addresses: a /22 or smaller.",
    ),
    "reachesSites": m225,
    "readAgain": MessageLookupByLibrary.simpleMessage("Read again"),
    "readFailed": MessageLookupByLibrary.simpleMessage("read failed"),
    "readFailedTip": m226,
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
    "refuseNeedsBroker": m227,
    "refuseNoInput": m228,
    "refuseOutput": MessageLookupByLibrary.simpleMessage(
      "Outputs cannot be bound",
    ),
    "refuseSelf": MessageLookupByLibrary.simpleMessage(
      "A block cannot feed itself",
    ),
    "refuseType": m229,
    "reject": MessageLookupByLibrary.simpleMessage("Reject"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "This certificate is refused from now on.",
    ),
    "rejectPlanHint": MessageLookupByLibrary.simpleMessage("Reason"),
    "rejectPlanNote": MessageLookupByLibrary.simpleMessage(
      "The plan is not run. The reason is kept in the task\'s record.",
    ),
    "rejectPlanTitle": MessageLookupByLibrary.simpleMessage("Reject the plan?"),
    "rejectTitle": m230,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Nothing to do from here: it came in with its relay. Deauthorize the relay to cut it off.",
    ),
    "relaysSites": m231,
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
    "removeLinkTitle": m232,
    "removePair": MessageLookupByLibrary.simpleMessage("Remove the last case"),
    "removePort": MessageLookupByLibrary.simpleMessage("Remove the last port"),
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "It stops, its tree is deleted, and its id is retired: it cannot be used again.",
    ),
    "removeUser": MessageLookupByLibrary.simpleMessage("Remove user"),
    "removeUserNote": MessageLookupByLibrary.simpleMessage(
      "They cannot log in again; their sessions end.",
    ),
    "removeUserTitle": m233,
    "requiredField": MessageLookupByLibrary.simpleMessage("Required field"),
    "resultNoValue": MessageLookupByLibrary.simpleMessage("—"),
    "resultNote": MessageLookupByLibrary.simpleMessage(
      "The keys the plan touched, with their values now.",
    ),
    "resultOf": m234,
    "resultTitle": MessageLookupByLibrary.simpleMessage("Result"),
    "returns": m235,
    "review": MessageLookupByLibrary.simpleMessage("Review"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage("Review and apply"),
    "reviewNote": m236,
    "revision": m237,
    "revisionNow": m238,
    "rightsLine": m239,
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Without this the broker installs nothing. Grants change later with Grant access; other values with the link\'s params.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "The package asks for these rights",
    ),
    "roleOnSite": m240,
    "rollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Its parameters become a new revision and the link restarts with them.",
    ),
    "rollBackTo": m241,
    "rowsAdd": MessageLookupByLibrary.simpleMessage("Add a row"),
    "rowsAnswered": m242,
    "rowsEmpty": MessageLookupByLibrary.simpleMessage("No rows yet"),
    "rowsRemove": MessageLookupByLibrary.simpleMessage("Remove this row"),
    "rstAcceptLinks": MessageLookupByLibrary.simpleMessage(
      "Accept the rights and network the links of the file ask for",
    ),
    "rstAcceptPackages": MessageLookupByLibrary.simpleMessage(
      "Accept the rights and network the packages of the file ask for",
    ),
    "rstAdd": MessageLookupByLibrary.simpleMessage(
      "Add only: links and storage nodes that do not exist yet; nothing replaced, no restart",
    ),
    "rstAddNote": MessageLookupByLibrary.simpleMessage("Nothing is replaced"),
    "rstAdded": MessageLookupByLibrary.simpleMessage(
      "Added; nothing was replaced, no restart",
    ),
    "rstApplied": MessageLookupByLibrary.simpleMessage(
      "The backup was applied; the broker runs on it",
    ),
    "rstCheck": MessageLookupByLibrary.simpleMessage("Check the file"),
    "rstChecked": MessageLookupByLibrary.simpleMessage("Checked"),
    "rstChoose": MessageLookupByLibrary.simpleMessage("Choose the file…"),
    "rstConfigNever": MessageLookupByLibrary.simpleMessage(
      "A copy for reference; a restore never writes it.",
    ),
    "rstConfirmKeys": MessageLookupByLibrary.simpleMessage(
      "Tick Replace the site\'s keys first",
    ),
    "rstControlOther": MessageLookupByLibrary.simpleMessage(
      "The control plane does not open with this broker\'s keys",
    ),
    "rstControlOtherNote": MessageLookupByLibrary.simpleMessage(
      "It is restored only together with Keys and secrets.",
    ),
    "rstDoAdd": MessageLookupByLibrary.simpleMessage("Add"),
    "rstDoReplace": MessageLookupByLibrary.simpleMessage("Restore and restart"),
    "rstFactSections": MessageLookupByLibrary.simpleMessage("Sections"),
    "rstFile": m243,
    "rstFileNote": m244,
    "rstHow": MessageLookupByLibrary.simpleMessage("How"),
    "rstInTheFile": MessageLookupByLibrary.simpleMessage("In the file"),
    "rstKeysDiffer": MessageLookupByLibrary.simpleMessage(
      "This site\'s CA, other key files",
    ),
    "rstKeysNeedPassphrase": MessageLookupByLibrary.simpleMessage(
      "Give the passphrase of the backup: the keys are restored only with it.",
    ),
    "rstKeysNone": MessageLookupByLibrary.simpleMessage("No keys in the file"),
    "rstKeysNoneNote": MessageLookupByLibrary.simpleMessage(
      "This broker keeps its own keys.",
    ),
    "rstKeysOther": MessageLookupByLibrary.simpleMessage("Another CA"),
    "rstKeysOtherNote": MessageLookupByLibrary.simpleMessage(
      "Restoring the keys changes the site\'s identity: links, operators and peer brokers enrol again.",
    ),
    "rstKeysSame": MessageLookupByLibrary.simpleMessage("The same keys"),
    "rstKeysSameNote": MessageLookupByLibrary.simpleMessage(
      "Every key file of the backup is this broker\'s; tokens and certificates stay valid.",
    ),
    "rstLinks": m245,
    "rstLogIn": MessageLookupByLibrary.simpleMessage("Log in again"),
    "rstLost": MessageLookupByLibrary.simpleMessage(
      "The broker did not come back for this session",
    ),
    "rstLostNote": MessageLookupByLibrary.simpleMessage(
      "It may still be starting, or it runs with other keys: after a restore of Keys and secrets this session is no longer the site\'s. Log in again; if the gateway does not answer, look at the broker on its host.",
    ),
    "rstNotApplied": MessageLookupByLibrary.simpleMessage(
      "The restore was not applied",
    ),
    "rstNotAppliedNote": MessageLookupByLibrary.simpleMessage(
      "The broker put everything back and runs on the state it had. The plan and the reason are kept on the host in data_dir/restore.failed.",
    ),
    "rstNotInAdd": MessageLookupByLibrary.simpleMessage(
      "Add takes links and storage only.",
    ),
    "rstNothingTicked": MessageLookupByLibrary.simpleMessage(
      "Tick a section this mode takes",
    ),
    "rstOtherSite": m246,
    "rstOtherSiteNote": MessageLookupByLibrary.simpleMessage(
      "The broker refuses a backup of another site name. Set site in wyrmd.json5 to the backup\'s first.",
    ),
    "rstPassphrase": MessageLookupByLibrary.simpleMessage(
      "Passphrase of the backup",
    ),
    "rstPassphraseKept": MessageLookupByLibrary.simpleMessage(
      "Sent again with the restore. Studio never stores it.",
    ),
    "rstPassphraseNote": MessageLookupByLibrary.simpleMessage(
      "Only for a backup sealed with one. Studio never stores it.",
    ),
    "rstPick": MessageLookupByLibrary.simpleMessage(
      "Pick a .wyrm-backup file.",
    ),
    "rstPickNote": MessageLookupByLibrary.simpleMessage(
      "The file goes to the broker in parts. Nothing changes until you have seen what the broker found in it.",
    ),
    "rstReplace": MessageLookupByLibrary.simpleMessage(
      "Replace what is ticked and restart the broker once (a backup of what it replaces is made first)",
    ),
    "rstReplaceKeys": m247,
    "rstReplaceKeysOther": MessageLookupByLibrary.simpleMessage(
      "Replace the site\'s keys with another CA: links, operators and peer brokers enrol again",
    ),
    "rstReplaceNote": MessageLookupByLibrary.simpleMessage(
      "A backup of what it replaces is made first",
    ),
    "rstReplaceProblems": MessageLookupByLibrary.simpleMessage(
      "The check found problems that block a replace.",
    ),
    "rstReplaceUpstream": MessageLookupByLibrary.simpleMessage(
      "This session reaches the site through an upstream broker: the broker refuses a replace from above. Add is open.",
    ),
    "rstRestarting": m248,
    "rstRestartingMore": MessageLookupByLibrary.simpleMessage(
      "A backup of what is replaced was made first (pre-restore, in Backups). The broker stops, and its next start applies the staged sections before any store opens.",
    ),
    "rstRestartingNote": MessageLookupByLibrary.simpleMessage(
      "Studio reconnects by itself.",
    ),
    "rstSchemas": MessageLookupByLibrary.simpleMessage(
      "Store formats differ (backup → here)",
    ),
    "rstTick": MessageLookupByLibrary.simpleMessage("tick what to bring back"),
    "rstTitle": m249,
    "rstUnknown": MessageLookupByLibrary.simpleMessage("The broker is back"),
    "rstUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Its audit shows neither restore_applied nor restore_failed yet. Look at System › Log before you rely on the restore.",
    ),
    "rstUploaded": MessageLookupByLibrary.simpleMessage(
      "The file is on the broker",
    ),
    "rstUploadedNote": MessageLookupByLibrary.simpleMessage(
      "Nothing was changed yet. The check reads its manifest and compares it with this broker.",
    ),
    "rstUploading": m250,
    "rstUploadingButton": MessageLookupByLibrary.simpleMessage("Uploading…"),
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
    "runNotRun": MessageLookupByLibrary.simpleMessage("not run"),
    "runNow": MessageLookupByLibrary.simpleMessage("Run now"),
    "runNowNote": m251,
    "runOff": MessageLookupByLibrary.simpleMessage("The block is disabled"),
    "runOnStartTitle": MessageLookupByLibrary.simpleMessage(
      "Run on every start?",
    ),
    "runPassed": MessageLookupByLibrary.simpleMessage("all steps passed"),
    "runPassedIn": m252,
    "runPassedLeftOut": m253,
    "runRunning": MessageLookupByLibrary.simpleMessage("running…"),
    "runStopped": m254,
    "runStoppedFirst": MessageLookupByLibrary.simpleMessage(
      "stopped · nothing was changed",
    ),
    "runStoppedOne": m255,
    "runStopsNote": MessageLookupByLibrary.simpleMessage(
      "stops at the first step that fails",
    ),
    "runTitle": m256,
    "runTitleEnded": m257,
    "runWaiting": MessageLookupByLibrary.simpleMessage("waiting"),
    "running": MessageLookupByLibrary.simpleMessage("Running"),
    "runningNote": MessageLookupByLibrary.simpleMessage(
      "The agent works on it. Cancel stops it; what was done stays done.",
    ),
    "runsOn": m258,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Runs on another device",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Same call from the CLI",
    ),
    "saveAsPlan": MessageLookupByLibrary.simpleMessage("Save as a plan"),
    "savePlanTitle": m259,
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
    "screenOf": m260,
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
    "securityAdded": m261,
    "securityConfirm": MessageLookupByLibrary.simpleMessage(
      "Confirm before config changes",
    ),
    "securityConfirmForced": m262,
    "securityConfirmNone": m263,
    "securityDevicesOn": m264,
    "securityDue": m265,
    "securityForget": MessageLookupByLibrary.simpleMessage("Forget"),
    "securityLockAfter": MessageLookupByLibrary.simpleMessage(
      "Lock Studio after",
    ),
    "securityLockDesc": m266,
    "securityLockOff": MessageLookupByLibrary.simpleMessage("Off"),
    "securityMenu": MessageLookupByLibrary.simpleMessage("Security"),
    "securityMinutes": m267,
    "securityNoBio": MessageLookupByLibrary.simpleMessage(
      "No biometric unlock on this computer: it asks for the password.",
    ),
    "securityNoDevices": MessageLookupByLibrary.simpleMessage(
      "No devices yet.",
    ),
    "securityOn": m268,
    "securityPasswordNeeded": m269,
    "securityPolicy": m270,
    "securityPolicyConfirm": MessageLookupByLibrary.simpleMessage(
      " · confirm config changes",
    ),
    "securityPolicyOff": MessageLookupByLibrary.simpleMessage("off"),
    "securityPolicyOn": MessageLookupByLibrary.simpleMessage("on"),
    "securityRemove": MessageLookupByLibrary.simpleMessage("Remove"),
    "securityRemoved": MessageLookupByLibrary.simpleMessage(
      "removed · signs in with the password only",
    ),
    "securityRemovedBy": m271,
    "securitySignOutAll": MessageLookupByLibrary.simpleMessage(
      "Sign out everywhere",
    ),
    "securitySignOutAllNote": m272,
    "securitySignedOut": MessageLookupByLibrary.simpleMessage("signed out"),
    "securityThisDevice": MessageLookupByLibrary.simpleMessage("this device"),
    "securityTitle": MessageLookupByLibrary.simpleMessage("Security"),
    "securityTurnOff": MessageLookupByLibrary.simpleMessage("Turn off"),
    "securityTurnOn": MessageLookupByLibrary.simpleMessage("Turn on"),
    "securityUnlockDesc": m273,
    "securityUnlockOffDesc": m274,
    "securityUsedNow": MessageLookupByLibrary.simpleMessage("used now"),
    "seeLinks": MessageLookupByLibrary.simpleMessage("see Links"),
    "seenAgo": m275,
    "seenNow": MessageLookupByLibrary.simpleMessage("now"),
    "selectANode": MessageLookupByLibrary.simpleMessage(
      "Select a node in the tree.",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Session expired"),
    "setLogLevel": m276,
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
    "showSteps": MessageLookupByLibrary.simpleMessage("Show steps"),
    "signingIn": MessageLookupByLibrary.simpleMessage("Signing in…"),
    "siteRelayedBelow": MessageLookupByLibrary.simpleMessage(
      "Site relayed below",
    ),
    "sitesAround": m277,
    "sitesSubtitle": m278,
    "sizeBytes": m279,
    "sizeChars": m280,
    "sizeColumns": m281,
    "sizeItems": m282,
    "sizeKeys": m283,
    "sizeLines": m284,
    "sizeRows": m285,
    "stage": MessageLookupByLibrary.simpleMessage("Stage"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "Stage puts it into Review and apply with your other edits.",
    ),
    "stagedChanges": m286,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Nothing is written until you apply. Each change runs with your own rights.",
    ),
    "stagedWas": m287,
    "stale": MessageLookupByLibrary.simpleMessage("stale"),
    "standbyAnswersAt": MessageLookupByLibrary.simpleMessage(
      "Its standby answers at",
    ),
    "standbyGateway": MessageLookupByLibrary.simpleMessage("Standby gateway"),
    "standbyIs": m288,
    "stateConnected": MessageLookupByLibrary.simpleMessage("Connected"),
    "stateFailed": MessageLookupByLibrary.simpleMessage("Failed"),
    "stateInstalled": MessageLookupByLibrary.simpleMessage("Installed"),
    "stateOffline": MessageLookupByLibrary.simpleMessage("Offline"),
    "stateStarting": MessageLookupByLibrary.simpleMessage("Starting"),
    "stateStopped": MessageLookupByLibrary.simpleMessage("Stopped"),
    "stateStopping": MessageLookupByLibrary.simpleMessage("Stopping"),
    "stateWaiting": MessageLookupByLibrary.simpleMessage("Waiting"),
    "stepBring": MessageLookupByLibrary.simpleMessage("Bring"),
    "stepByAgent": MessageLookupByLibrary.simpleMessage(
      "runs with the agent\'s key: this mode needs no person for it, and it cannot be left out",
    ),
    "stepCheck": MessageLookupByLibrary.simpleMessage("Check"),
    "stepChecking": MessageLookupByLibrary.simpleMessage(
      "Checking user and password",
    ),
    "stepChoose": MessageLookupByLibrary.simpleMessage("Choose"),
    "stepInstall": MessageLookupByLibrary.simpleMessage("Install"),
    "stepLeftOut": MessageLookupByLibrary.simpleMessage(
      "left out: it will not run",
    ),
    "stepOf": m289,
    "stepReaching": m290,
    "stepReading": MessageLookupByLibrary.simpleMessage(
      "Reading your role and sites",
    ),
    "stepSkippedNeeds": m291,
    "stepUpConfirm": MessageLookupByLibrary.simpleMessage("Confirm"),
    "stepUpConfirmWith": m292,
    "stepUpDevice": m293,
    "stepUpLead": m294,
    "stepUpPasswordOnly": m295,
    "stepUpRefused": m296,
    "stepUpStopped": m297,
    "stepUpTitle": MessageLookupByLibrary.simpleMessage("Confirm it is you"),
    "stepUpWaiting": m298,
    "stepWhere": MessageLookupByLibrary.simpleMessage("Where it runs"),
    "stopRecording": MessageLookupByLibrary.simpleMessage("Stop recording"),
    "stoppedAt": m299,
    "stoppedNote": m300,
    "studioAbout": m301,
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio is signed in here",
    ),
    "studioVersion": m302,
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
    "sysAttnAcl": m303,
    "sysAttnAclDetail": m304,
    "sysAttnBehind": m305,
    "sysAttnBehindDetail": m306,
    "sysAttnBehindPlain": MessageLookupByLibrary.simpleMessage(
      "standby_lag is above 0: a takeover now loses records",
    ),
    "sysAttnBroker": m307,
    "sysAttnBrokerPlain": MessageLookupByLibrary.simpleMessage(
      "A downstream broker",
    ),
    "sysAttnBrokerRelays": m308,
    "sysAttnFork": MessageLookupByLibrary.simpleMessage(
      "The standby moved a fork aside",
    ),
    "sysAttnLinkDetail": m309,
    "sysAttnLinkFailed": m310,
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
    "sysAttnQuarantine": m311,
    "sysAttnQuarantineDetail": m312,
    "sysAttnQuarantineSince": m313,
    "sysBackup": MessageLookupByLibrary.simpleMessage("Back up and restore"),
    "sysBackupNote": m314,
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
    "sysBannerForks": m315,
    "sysBannerLag": m316,
    "sysBrokerAll": MessageLookupByLibrary.simpleMessage("broker (all)"),
    "sysBrokerLogLevel": MessageLookupByLibrary.simpleMessage(
      "Broker log level",
    ),
    "sysBytes": MessageLookupByLibrary.simpleMessage("Bytes"),
    "sysClear": m317,
    "sysClearAsk": MessageLookupByLibrary.simpleMessage(
      "Clear these disconnected links?",
    ),
    "sysClearAskBody": m318,
    "sysClearBoard": m319,
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
    "sysCleared": m320,
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
    "sysCopyCommand": m321,
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
    "sysGuideCopied": m322,
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
    "sysLinkSource": m323,
    "sysLogCopied": m324,
    "sysLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Staged in Review and apply; once applied it takes effect at once, no restart, and replaces `RUST_LOG`. Zenoh stays at warn below trace. Values and tokens are never logged below trace. A link\'s own level: Links › the link › Log.",
    ),
    "sysLogNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "The log is read with config on sys.",
    ),
    "sysLogNotSaved": MessageLookupByLibrary.simpleMessage(
      "Cannot save the log",
    ),
    "sysLogSaved": m325,
    "sysLogSummary": m326,
    "sysLogSummaryAround": m327,
    "sysLogSummaryNone": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/get_log` · config",
    ),
    "sysMessages": MessageLookupByLibrary.simpleMessage("Messages"),
    "sysMetaStarted": m328,
    "sysNeedsLook": m329,
    "sysNeedsLookNote": MessageLookupByLibrary.simpleMessage(
      "From the broker\'s own values. Each opens the screen where it is fixed.",
    ),
    "sysNoLines": MessageLookupByLibrary.simpleMessage(
      "No lines at this level.",
    ),
    "sysNoLinesAround": m330,
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
    "sysNoStandbyStep2": m331,
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
    "sysNow": m332,
    "sysOfTotal": m333,
    "sysOpenAuditRecord": MessageLookupByLibrary.simpleMessage(
      "Open the audit record ›",
    ),
    "sysOut": MessageLookupByLibrary.simpleMessage("out"),
    "sysPackages": MessageLookupByLibrary.simpleMessage("Packages"),
    "sysProfileFile": m334,
    "sysProfileName": MessageLookupByLibrary.simpleMessage("Name"),
    "sysProfileNameHint": MessageLookupByLibrary.simpleMessage(
      "<vendor>:<model>",
    ),
    "sysProfilePut": m335,
    "sysProfileRemoved": m336,
    "sysProfiles": MessageLookupByLibrary.simpleMessage("Device profiles"),
    "sysProfilesFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/profiles` › Put Profile, Remove Profile · config",
    ),
    "sysProfilesNote": MessageLookupByLibrary.simpleMessage(
      "Models served as `pub/<vendor>:<model>`: points, units and ranges that links and the assistant inherit.",
    ),
    "sysProfilesUnlisted": m337,
    "sysPulled": MessageLookupByLibrary.simpleMessage("pulled every 1 s"),
    "sysPut": MessageLookupByLibrary.simpleMessage("Put profile"),
    "sysPutProfile": MessageLookupByLibrary.simpleMessage("Put profile…"),
    "sysRecords": MessageLookupByLibrary.simpleMessage("records"),
    "sysRemove": MessageLookupByLibrary.simpleMessage("Remove"),
    "sysRemoveProfile": m338,
    "sysRemoveProfileAsk": m339,
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
    "sysStaleRow": m340,
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
    "sysSubData": m341,
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
    "sysSubLinkFailed": m342,
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
    "sysSubPeer": m343,
    "sysSubSessions": MessageLookupByLibrary.simpleMessage(
      "network sessions; gateway users not counted",
    ),
    "sysSubWaits": m344,
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
    "sysTrafficDescribe": m345,
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
    "tableFiltered": m346,
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
    "tagActiveStandby": MessageLookupByLibrary.simpleMessage(
      "active + standby",
    ),
    "tagDownstreamOf": m347,
    "tagNeeds": m348,
    "tagNew": MessageLookupByLibrary.simpleMessage("new"),
    "tagPlainHttp": MessageLookupByLibrary.simpleMessage("plain http"),
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("runs now"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("staged"),
    "tagUsedBefore": MessageLookupByLibrary.simpleMessage("used before"),
    "taskAwaiting": MessageLookupByLibrary.simpleMessage("awaiting approval"),
    "taskAwaitingAnswer": MessageLookupByLibrary.simpleMessage(
      "awaiting your answer",
    ),
    "taskBy": m349,
    "taskDone": MessageLookupByLibrary.simpleMessage("done"),
    "taskFailed": MessageLookupByLibrary.simpleMessage("failed or stopped"),
    "taskFailedAt": m350,
    "taskListNote": m351,
    "taskNoChanges": MessageLookupByLibrary.simpleMessage("nothing changed"),
    "taskPlanning": MessageLookupByLibrary.simpleMessage("planning"),
    "taskRunning": MessageLookupByLibrary.simpleMessage("running"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("this broker"),
    "thisNetwork": MessageLookupByLibrary.simpleMessage("this network"),
    "tlsCertificateOf": m352,
    "tlsNotTrusted": m353,
    "tlsPinned": m354,
    "toAccept": MessageLookupByLibrary.simpleMessage("to accept"),
    "toastDismiss": MessageLookupByLibrary.simpleMessage("Dismiss"),
    "toastHidesIn": m355,
    "toastNotifications": MessageLookupByLibrary.simpleMessage("Notifications"),
    "toastStays": m356,
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
    "treeOf": m357,
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
    "trendAvg": m358,
    "trendBadRecorded": MessageLookupByLibrary.simpleMessage(
      "bad quality recorded",
    ),
    "trendBucket": m359,
    "trendClearMarker": MessageLookupByLibrary.simpleMessage(
      "Click A again to clear it",
    ),
    "trendDelta": m360,
    "trendDescribe": m361,
    "trendFollowNow": MessageLookupByLibrary.simpleMessage("Follow now"),
    "trendHint": MessageLookupByLibrary.simpleMessage(
      "Hover for values · drag on the chart to zoom · click to set marker A · drag or resize the window below · double-click resets · ← → move the focused handle",
    ),
    "trendHoursMinutes": m362,
    "trendLocked": m363,
    "trendMarker": m364,
    "trendMinMax": m365,
    "trendMinutes": m366,
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
    "trendRawAt": m367,
    "trendResetZoom": MessageLookupByLibrary.simpleMessage("Reset zoom"),
    "trendSeconds": m368,
    "trendSetMarker": MessageLookupByLibrary.simpleMessage(
      "Click to set marker A",
    ),
    "trendShowHide": m369,
    "trendStepDays": m370,
    "trendStepHours": m371,
    "trendStepMinutes": m372,
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
    "trustCode": MessageLookupByLibrary.simpleMessage("CA code"),
    "trustMatches": m373,
    "trustRefusedChain": m374,
    "trustRefusedChanged": MessageLookupByLibrary.simpleMessage(
      "The gateway now sends another CA than the one shown. Nothing was trusted.",
    ),
    "trustRefusedMismatch": MessageLookupByLibrary.simpleMessage(
      "The code the gateway claims is not the code of its CA. Nothing was trusted.",
    ),
    "trustRefusedNoAnswer": MessageLookupByLibrary.simpleMessage(
      "The gateway did not answer again. Nothing was trusted.",
    ),
    "trustTitle": m375,
    "trustWhere": m376,
    "trustWhy": m377,
    "tryAgain": MessageLookupByLibrary.simpleMessage("Try again"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Turn on"),
    "typeOrFind": MessageLookupByLibrary.simpleMessage(
      "Type the address, or find one on this network.",
    ),
    "unbind": MessageLookupByLibrary.simpleMessage("Unbind"),
    "unitNumber": m378,
    "unlockAgoNow": MessageLookupByLibrary.simpleMessage("now"),
    "unlockAnother": MessageLookupByLibrary.simpleMessage(
      "Another account or gateway",
    ),
    "unlockCancelTitle": m379,
    "unlockChangedFaces": m380,
    "unlockChangedFingers": m381,
    "unlockChangedTitle": m382,
    "unlockChecking": m383,
    "unlockConfirmPrompt": m384,
    "unlockDeviceComputer": MessageLookupByLibrary.simpleMessage(
      "this computer",
    ),
    "unlockDeviceIphone": MessageLookupByLibrary.simpleMessage("this iPhone"),
    "unlockDeviceMac": MessageLookupByLibrary.simpleMessage("this Mac"),
    "unlockDevicePc": MessageLookupByLibrary.simpleMessage("this PC"),
    "unlockDevicePhone": MessageLookupByLibrary.simpleMessage("this phone"),
    "unlockDontAsk": MessageLookupByLibrary.simpleMessage(
      "Don’t ask on this computer",
    ),
    "unlockDueText": m385,
    "unlockDueTitle": m386,
    "unlockEnablePrompt": m387,
    "unlockFactEndsFaces": MessageLookupByLibrary.simpleMessage(
      "It ends when the faces here change, when your password changes, or when an administrator removes this device.",
    ),
    "unlockFactEndsFingers": MessageLookupByLibrary.simpleMessage(
      "It ends when the fingerprints here change, when your password changes, or when an administrator removes this device.",
    ),
    "unlockFactPassword": m388,
    "unlockFactSite": m389,
    "unlockFactStandby": m390,
    "unlockFactStore": m391,
    "unlockFallbackText": m392,
    "unlockKeyIn": m393,
    "unlockLastPassword": MessageLookupByLibrary.simpleMessage("password"),
    "unlockLastUsed": m394,
    "unlockLockoutTitle": m395,
    "unlockLogInTo": m396,
    "unlockNameBiometric": MessageLookupByLibrary.simpleMessage("biometrics"),
    "unlockNameFace": MessageLookupByLibrary.simpleMessage("face unlock"),
    "unlockNameFingerprint": MessageLookupByLibrary.simpleMessage(
      "fingerprint",
    ),
    "unlockNameIris": MessageLookupByLibrary.simpleMessage("iris"),
    "unlockNoBioFactOther": MessageLookupByLibrary.simpleMessage(
      "On a computer with a fingerprint reader, use macOS or Windows to unlock with it.",
    ),
    "unlockNoBioFactRemember": MessageLookupByLibrary.simpleMessage(
      "Studio remembers the gateway and the user, never the password.",
    ),
    "unlockNoBioText": MessageLookupByLibrary.simpleMessage(
      "Studio can only bind a key to Touch ID, Face ID, Windows Hello or an Android fingerprint. Here it will ask for the password each time.",
    ),
    "unlockNoBioTitle": MessageLookupByLibrary.simpleMessage(
      "This computer has no biometric unlock",
    ),
    "unlockNoneLinux": MessageLookupByLibrary.simpleMessage(
      "Linux has no system prompt Studio can bind a key to, so this computer always asks for the password.",
    ),
    "unlockNoneOther": MessageLookupByLibrary.simpleMessage(
      "Studio found no Touch ID or Windows Hello set up here, so this computer asks for the password.",
    ),
    "unlockNoneTitle": MessageLookupByLibrary.simpleMessage(
      "No biometric unlock on this computer",
    ),
    "unlockNotNow": MessageLookupByLibrary.simpleMessage("Not now"),
    "unlockOffText": MessageLookupByLibrary.simpleMessage(
      "An administrator turned devices off on this gateway. Studio removed its key; log in with the password.",
    ),
    "unlockOffTitle": m397,
    "unlockOffToast": m398,
    "unlockOfferChecked": m399,
    "unlockOfferText": m400,
    "unlockOfferTitle": m401,
    "unlockOpenStudio": MessageLookupByLibrary.simpleMessage("Open Studio"),
    "unlockOrEnter": MessageLookupByLibrary.simpleMessage("Or press Enter"),
    "unlockPasswordChangedText": MessageLookupByLibrary.simpleMessage(
      "A new password signs out every device. Log in with the new one.",
    ),
    "unlockPasswordChangedTitle": MessageLookupByLibrary.simpleMessage(
      "Your password changed",
    ),
    "unlockPasswordFor": m402,
    "unlockPlusStandby": m403,
    "unlockPolicyLine": m404,
    "unlockPrompt": m405,
    "unlockReEnable": m406,
    "unlockRemovedText": m407,
    "unlockRemovedTitle": MessageLookupByLibrary.simpleMessage(
      "Removed by an administrator",
    ),
    "unlockRoleOn": m408,
    "unlockStoreAndroid": MessageLookupByLibrary.simpleMessage(
      "this phone’s hardware keystore",
    ),
    "unlockStoreIos": MessageLookupByLibrary.simpleMessage(
      "this iPhone’s Secure Enclave",
    ),
    "unlockStoreMac": MessageLookupByLibrary.simpleMessage(
      "this Mac’s Secure Enclave",
    ),
    "unlockStoreWindows": MessageLookupByLibrary.simpleMessage("this PC’s TPM"),
    "unlockToOpen": m409,
    "unlockUnknownText": m410,
    "unlockUnknownTitle": m411,
    "unlockUse": m412,
    "unlockUsePassword": MessageLookupByLibrary.simpleMessage(
      "Use the password",
    ),
    "unlockWelcomeBack": MessageLookupByLibrary.simpleMessage("Welcome back"),
    "unlockWith": m413,
    "unpinField": MessageLookupByLibrary.simpleMessage("Unpin from block"),
    "unreachableAdvice": MessageLookupByLibrary.simpleMessage(
      "The broker may be restarting or this computer is on another network.",
    ),
    "unsubscribeNote": MessageLookupByLibrary.simpleMessage(
      "The point stops being recorded; its rows stay.",
    ),
    "upFor": m414,
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
    "updDo": m415,
    "updFailed": m416,
    "updFailedNote": MessageLookupByLibrary.simpleMessage(
      "The health check ended without an answer from every link.",
    ),
    "updFromFile": MessageLookupByLibrary.simpleMessage("A newer archive"),
    "updFromFileNote": m417,
    "updFromFileRow": MessageLookupByLibrary.simpleMessage("Update from file…"),
    "updGoneTile": MessageLookupByLibrary.simpleMessage("gone"),
    "updHotStart": m418,
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
    "updKeptUntil": m419,
    "updLeave": MessageLookupByLibrary.simpleMessage(
      "You can leave this screen; it goes on.",
    ),
    "updLinksCount": m420,
    "updLinksRestart": m421,
    "updLinksRestartNote": MessageLookupByLibrary.simpleMessage(
      "Their values pause while each restarts; their nodes are declared again from the settings they keep.",
    ),
    "updNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "Needs config on sys/links",
    ),
    "updNeverUpdated": MessageLookupByLibrary.simpleMessage(
      "This package was not updated on this broker yet.",
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
    "updOpenLink": m422,
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
    "updPointBeforeRestore": m423,
    "updPointBeforeUpdate": m424,
    "updPoints": MessageLookupByLibrary.simpleMessage("Restore points"),
    "updRights": MessageLookupByLibrary.simpleMessage("Rights and network"),
    "updRightsNote": MessageLookupByLibrary.simpleMessage(
      "If the new version asks for more than the links have, the broker installs nothing and lists them here for you to accept.",
    ),
    "updRollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "updRollBackNote": m425,
    "updRollBackTitle": m426,
    "updRollBackTo": m427,
    "updRolledBackNote": MessageLookupByLibrary.simpleMessage(
      "The links run the kept version again.",
    ),
    "updRolledBackTo": m428,
    "updRowChecking": MessageLookupByLibrary.simpleMessage("being checked"),
    "updRuns": m429,
    "updRunsNote": m430,
    "updStateChanges": m431,
    "updStateChangesNote": MessageLookupByLibrary.simpleMessage(
      "The old version cannot read the new store: a rollback restores the store of the restore point.",
    ),
    "updStateCustom": MessageLookupByLibrary.simpleMessage(
      "Store format: the archive says",
    ),
    "updStateCustomNote": MessageLookupByLibrary.simpleMessage(
      "If the archive does not read the installed store format, the broker refuses an update without a restore point.",
    ),
    "updStateSame": m432,
    "updStateSameNote": MessageLookupByLibrary.simpleMessage(
      "The new version reads the store of the installed one.",
    ),
    "updStepNodes": MessageLookupByLibrary.simpleMessage(
      "Health: every link back with its nodes",
    ),
    "updStepNodesCount": m433,
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
    "updSubCustom": m434,
    "updSubOfficial": m435,
    "updTab": MessageLookupByLibrary.simpleMessage("Updates"),
    "updTabNote": MessageLookupByLibrary.simpleMessage(
      "Links whose package has a newer version. Every link of a package is updated together, and the broker keeps what it needs to go back.",
    ),
    "updThen": MessageLookupByLibrary.simpleMessage("Then"),
    "updTitle": m436,
    "updTitleCustom": m437,
    "updTitleDone": m438,
    "updTitleRolledBack": m439,
    "updTogether": MessageLookupByLibrary.simpleMessage("updated together"),
    "updUpdating": m440,
    "updUpdatingButton": MessageLookupByLibrary.simpleMessage("Updating…"),
    "updUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Values of its links pause while each restarts.",
    ),
    "updVersionsOf": m441,
    "updWhatChanges": MessageLookupByLibrary.simpleMessage(
      "What changes for the broker",
    ),
    "updWhatIsNew": m442,
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
    "versionDeployed": m443,
    "viaSite": m444,
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
    "viewerCsvRules": m445,
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
    "viewerSaveHint": m446,
    "viewerTabTable": MessageLookupByLibrary.simpleMessage("As table"),
    "viewerTabText": MessageLookupByLibrary.simpleMessage("Text"),
    "viewerTableHint": m447,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Waiting in quarantine",
    ),
    "waitingToBeLetIn": m448,
    "wasValue": m449,
    "wasWord": MessageLookupByLibrary.simpleMessage("was"),
    "watchGroup": MessageLookupByLibrary.simpleMessage("Watch group"),
    "watchGroups": m450,
    "welcomeUser": m451,
    "whatItRead": MessageLookupByLibrary.simpleMessage("What it read"),
    "whyAnnounce": MessageLookupByLibrary.simpleMessage(
      "The broker may have gateway.announce off (hardened sites), or its gateway listens on loopback only.",
    ),
    "whyBring": MessageLookupByLibrary.simpleMessage(
      "Bring your own package only when it is not in the official list. A zip, a URL or a Git repository with a built package, or one component.",
    ),
    "whyBringBackup": MessageLookupByLibrary.simpleMessage(
      "A link backup is one file with what a link needs to come back. Studio reads its manifest here; the broker checks all of it as a new link.",
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
    "whyMulticast": MessageLookupByLibrary.simpleMessage(
      "Multicast does not cross this network: guest Wi-Fi, a VPN, or a VLAN without an mDNS reflector.",
    ),
    "whyNew": MessageLookupByLibrary.simpleMessage("New"),
    "whyPermission": MessageLookupByLibrary.simpleMessage(
      "Studio may not be allowed to see the local network.",
    ),
    "whyPermissionIos": MessageLookupByLibrary.simpleMessage(
      "Studio may not be allowed to see the local network. iOS: Settings › Privacy & Security › Local Network.",
    ),
    "whyPermissionMac": MessageLookupByLibrary.simpleMessage(
      "Studio may not be allowed to see the local network. macOS: System Settings › Privacy & Security › Local Network.",
    ),
    "whyRunBackup": MessageLookupByLibrary.simpleMessage(
      "Keep its id to restore it, or give a new one to make a second link. The mode is the one it ran in.",
    ),
    "whyRunCustom": MessageLookupByLibrary.simpleMessage(
      "Choose the broker. Only brokers whose host the package was built for can take it; how it runs is set by the package kind.",
    ),
    "whyRunOfficial": MessageLookupByLibrary.simpleMessage(
      "Choose the broker, then how the link runs on it. A built-in driver can run inside the broker, as its own process or on another machine.",
    ),
    "whyType": MessageLookupByLibrary.simpleMessage(
      "You can always type the address, or open a link or a code from the broker’s System page.",
    ),
    "windowClose": MessageLookupByLibrary.simpleMessage("Close window"),
    "windowMaximize": MessageLookupByLibrary.simpleMessage("Maximize"),
    "windowMinimize": MessageLookupByLibrary.simpleMessage("Minimize"),
    "windowRestore": MessageLookupByLibrary.simpleMessage("Restore"),
    "wordOrderReason": MessageLookupByLibrary.simpleMessage(
      "Set by the data type: its _wswap, _bswap or _wbswap suffix.",
    ),
    "wouldRun": m452,
    "wouldSend": m453,
    "wouldWrite": m454,
    "writableNeeds": m455,
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
    "wyrmdOn": m456,
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
