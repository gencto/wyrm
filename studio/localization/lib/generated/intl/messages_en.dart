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

  static String m73(n) =>
      "${Intl.plural(n, zero: 'nothing · its guess', one: '1 change · its guess', other: '${n} changes · its guess')}";

  static String m74(count) =>
      "${Intl.plural(count, zero: 'no children', one: '1 child', other: '${count} children')}";

  static String m75(answer) => "from the card: ${answer}";

  static String m76(answer) => "in your own words: ${answer}";

  static String m77(site) =>
      "${site} dials out to it; it authorizes ${site} there.";

  static String m78(size) => "data_dir ${size}";

  static String m79(id) => "Deauthorize ${id}?";

  static String m80(flow) =>
      "The draft of “${flow}” replaces the version that runs now.";

  static String m81(who) => "deployed by ${who}";

  static String m82(steps) =>
      "The task is done. Steps left out: ${steps}. Ask for them as a follow-up; its plan is approved on its own.";

  static String m83(device) =>
      "It runs on ${device}; the broker cannot start or stop it.";

  static String m84(id) => "Edit params of ${id}";

  static String m85(time) =>
      "The broker log around ${time} has the rest of the story.";

  static String m86(field) =>
      "Back in the form, the field ${field} is marked; correct it and send again.";

  static String m87(role, site) =>
      "Your role is ${role}. Nothing was changed on ${site}.";

  static String m88(call, key) => "${call} on ${key}";

  static String m89(type) => "studio · ${type}";

  static String m90(thing) => "deploy ${thing}";

  static String m91(thing) => "install ${thing}";

  static String m92(thing) => "list ${thing}";

  static String m93(thing) => "log in to ${thing}";

  static String m94(thing) => "open ${thing}";

  static String m95(thing) => "read ${thing}";

  static String m96(thing) => "remove ${thing}";

  static String m97(call, thing) => "run ${call} on ${thing}";

  static String m98(thing) => "save ${thing}";

  static String m99(thing) => "start ${thing}";

  static String m100(step) => "finish “${step}”";

  static String m101(thing) => "stop ${thing}";

  static String m102(thing) => "write ${thing}";

  static String m103(thing) => "Deploying ${thing}";

  static String m104(thing) => "Installing ${thing}";

  static String m105(thing) => "Listing ${thing}";

  static String m106(thing) => "Logging in to ${thing}";

  static String m107(thing) => "Opening ${thing}";

  static String m108(thing) => "Reading ${thing}";

  static String m109(thing) => "Removing ${thing}";

  static String m110(call, thing) => "${call} on ${thing}";

  static String m111(thing) => "Saving ${thing}";

  static String m112(thing) => "Starting ${thing}";

  static String m113(thing) => "Stopping ${thing}";

  static String m114(thing) => "Writing ${thing}";

  static String m115(call) => "${call}";

  static String m116(site) => "No answer from the broker at ${site}.";

  static String m117(status) =>
      "The broker answered ${status} and sent no message.";

  static String m118(status, message) => "${status}: ${message}";

  static String m119(time) => "${time} (local)";

  static String m120(doing, site) => "${doing} failed on ${site}";

  static String m121(doing) => "${doing} failed";

  static String m122(site, what) => "${site} is busy, ${what} did not start";

  static String m123(thing) => "${thing} is not there anymore";

  static String m124(thing) => "History of ${thing} unavailable";

  static String m125(site) => "${site} did not answer";

  static String m126(thing) => "Reading ${thing} failed";

  static String m127(what) => "You can’t ${what}";

  static String m128(site) => "Live values from ${site} stopped";

  static String m129(what) => "Studio could not ${what}";

  static String m130(thing, call) => "${thing} does not support ${call}";

  static String m131(seconds) => "Try again in ${seconds} s";

  static String m132(user, role) => "${user} (${role})";

  static String m133(s) => "every ${s} s";

  static String m134(reason) =>
      "The unreadable file could not be moved aside: ${reason}";

  static String m135(name) =>
      "Fresh settings keep the unreadable file beside the new one as ${name}. You add your gateways and log in again.";

  static String m136(panel) => "Studio could not draw ${panel}";

  static String m137(panel) => "The ${panel} could not be drawn";

  static String m138(when) => "first seen ${when}";

  static String m139(mode) =>
      "replaces this plan; with require_approval “${mode}” the new plan\'s write steps run without a person";

  static String m140(v) => "v${v} deployed";

  static String m141(v) => "v${v} · error";

  static String m142(v) => "v${v} stopped";

  static String m143(v) => "Version ${v}";

  static String m144(site) => "Flows on ${site}";

  static String m145(count) => "${count} blocks";

  static String m146(label) => "Unpin “${label}” from block";

  static String m147(task, steps) =>
      "Do the steps that were left out of the plan of task ${task}: ${steps}.";

  static String m148(address) => "from ${address}";

  static String m149(host, ms) => "${host} · answered in ${ms} ms";

  static String m150(host) => "No answer from ${host}";

  static String m151(key) => "Go to ${key}";

  static String m152(id) => "Grant access to ${id}";

  static String m153(node) => "Tell it what you know about ${node}…";

  static String m154(days) => "raw kept ${days} d";

  static String m155(n) => "${n} series";

  static String m156(size) => "Historian ${size}";

  static String m157(id) => "Params history of ${id}";

  static String m158(status) =>
      "Reading the history failed: ${status}. Details in Problems.";

  static String m159(n) =>
      "${Intl.plural(n, one: '1 input', other: '${n} inputs')}";

  static String m160(name, broker) => "${name} is installed on ${broker}.";

  static String m161(n) =>
      "${Intl.plural(n, zero: 'no instance in this flow', one: '1 instance in this flow', other: '${n} instances in this flow')} · a change here changes them all";

  static String m162(count) => "${count} keys copied";

  static String m163(lag) => "lag ${lag}";

  static String m164(time) => "last read ${time}";

  static String m165(n) =>
      "${Intl.plural(n, one: '1 link already', other: '${n} links already')}";

  static String m166(n) =>
      "${Intl.plural(n, one: '1 link', other: '${n} links')}";

  static String m167(site) =>
      "Started and watched by ${site}: built-in drivers and installed packages. You can stop, change, upgrade and remove them.";

  static String m168(site) => "Links on ${site}";

  static String m169(first, last) => "${first} and ${last}";

  static String m170(status) =>
      "Reading the list of children failed: ${status}. Details in Problems.";

  static String m171(id) => "Log of ${id}";

  static String m172(n) =>
      "${Intl.plural(n, one: '1 instance uses it', other: '${n} instances use it')}";

  static String m173(n) => "library v${n}";

  static String m174(n) => "${n} used";

  static String m175(n) => "v${n}";

  static String m176(kind, count) => "${kind} · ${count} actions";

  static String m177(status) =>
      "Reading the description failed: ${status}. Details in Problems.";

  static String m178(n) =>
      "${Intl.plural(n, zero: 'Make a plan', one: 'Make a plan for 1 unit', other: 'Make a plan for ${n} units')}";

  static String m179(count) =>
      "${Intl.plural(count, one: '… 1 more byte', other: '… ${count} more bytes')}";

  static String m180(count) =>
      "${Intl.plural(count, one: '1 more line', other: '${count} more lines')}";

  static String m181(count) => "${count} selected";

  static String m182(level, have) => "Needs ${level} · you have ${have}";

  static String m183(level) => "Needs ${level} · you have it";

  static String m184(action) => "This node has no ${action} action.";

  static String m185(param) => "The driver has no ${param} parameter.";

  static String m186(site) => "none: ${site} is the top";

  static String m187(site) => "Explorer shows wy/${site}.";

  static String m188(node) => "Open ${node} in Explorer";

  static String m189(id) => "Open tasks/${id}";

  static String m190(site) => "Opening the tree of ${site}…";

  static String m191(name) => "package ${name}";

  static String m192(n) =>
      "${Intl.plural(n, one: '1 case', other: '${n} cases')}";

  static String m193(n) =>
      "${Intl.plural(n, zero: 'no parameters', one: '1 parameter', other: '${n} parameters')}";

  static String m194(rev) => "Parameters (revision ${rev}, JSON)";

  static String m195(detail) => "Not JSON: ${detail}";

  static String m196(now, atRun) =>
      "awaiting approval · ${now} checked now, ${atRun} when it runs";

  static String m197(n) => "needs step ${n}";

  static String m198(path) => "Saved ${path}. Run it with wyrm-agent run.";

  static String m199(steps) =>
      "Secret arguments are not in the file: ${steps}. Add them before you run it.";

  static String m200(s) => "${s} s";

  static String m201(n) => "Plan · ${n} steps";

  static String m202(s) => "timeout ${s} s";

  static String m203(n) =>
      "${Intl.plural(n, one: '1 point', other: '${n} points')}";

  static String m204(n) =>
      "${Intl.plural(n, one: '1 port', other: '${n} ports')}";

  static String m205(step) => "${step} · later";

  static String m206(site) => "Reading the tree of ${site}";

  static String m207(message) => "The draft does not run: ${message}";

  static String m208(count) =>
      "${Intl.plural(count, one: '1 problem', other: '${count} problems')}";

  static String m209(name) => "${name} is installed";

  static String m210(name) => "Installing ${name}…";

  static String m211(sites) => "reaches ${sites}";

  static String m212(status) =>
      "Reading the value failed: ${status}. Details in Problems.";

  static String m213(field) =>
      "This broker cannot bind ${field} (its flow engine is older than ADR 0040)";

  static String m214(field) => "${field} takes no input: type its value";

  static String m215(from, to) => "${from} does not fit ${to}";

  static String m216(cn) => "Reject ${cn}?";

  static String m217(n) =>
      "${Intl.plural(n, one: 'relays 1 site', other: 'relays ${n} sites')}";

  static String m218(id) => "Remove ${id}?";

  static String m219(name) => "Remove ${name}?";

  static String m220(id) =>
      "This plan was replaced by tasks/${id} and cannot be approved. Approve the plan of that task instead.";

  static String m221(action) => "Result · ${action}";

  static String m222(what) => "returns ${what}";

  static String m223(audit) =>
      "Each write is checked by the link and recorded in ${audit}. A value shows only after it is read back.";

  static String m224(rev) => "Revision ${rev}";

  static String m225(rev) => "Revision ${rev} · in use";

  static String m226(site, user, role, level) =>
      "Site ${site} · applied with your rights: ${user}, ${role} (${level})";

  static String m227(role, site) => "${role} on ${site}";

  static String m228(rev) => "Roll back to revision ${rev}?";

  static String m229(n) =>
      "${Intl.plural(n, one: '1 row', other: '${n} rows')}";

  static String m230(site, broker) => "From ${site} · wyrmd ${broker}";

  static String m231(when, n, sealed) =>
      "Made ${when} · sections: ${n} · secrets: ${sealed}";

  static String m232(fresh, exists) =>
      "Links: ${fresh} new, ${exists} exist here";

  static String m233(site) => "A backup of another site: ${site}";

  static String m234(files) => "Replace the site\'s keys: ${files}";

  static String m235(site) => "${site} restarts and applies the backup";

  static String m236(site) => "Restore ${site} from a backup";

  static String m237(done, size) => "Uploading: ${done} of ${size}";

  static String m238(user) =>
      "Runs as ${user}. Nothing else in the tree changes unless the result is used.";

  static String m239(s) => "all steps passed · ${s} s";

  static String m240(steps) => "done · steps left out: ${steps}";

  static String m241(steps) =>
      "stopped · steps ${steps} changed something and stay done";

  static String m242(n) =>
      "stopped · step ${n} changed something and stays done";

  static String m243(n, of) => "Run · step ${n} of ${of}";

  static String m244(of) => "Run · ${of} steps";

  static String m245(site) => "Runs on ${site}";

  static String m246(task) => "Save the plan of ${task}";

  static String m247(name) => "${name}";

  static String m248(level) => "Log level ${level}";

  static String m249(site) => "Sites around ${site}";

  static String m250(site) =>
      "What ${site} connects to and what connects to it: brokers above and below, platforms it sends to, and devices whose links run outside any broker.";

  static String m251(count) =>
      "${Intl.plural(count, one: '1 byte', other: '${count} bytes')}";

  static String m252(count) =>
      "${Intl.plural(count, one: '1 char', other: '${count} chars')}";

  static String m253(count) =>
      "${Intl.plural(count, one: '1 column', other: '${count} columns')}";

  static String m254(count) =>
      "${Intl.plural(count, one: '1 item', other: '${count} items')}";

  static String m255(count) =>
      "${Intl.plural(count, one: '1 key', other: '${count} keys')}";

  static String m256(count) =>
      "${Intl.plural(count, one: '1 line', other: '${count} lines')}";

  static String m257(count) =>
      "${Intl.plural(count, one: '1 row', other: '${count} rows')}";

  static String m258(count) =>
      "${Intl.plural(count, zero: 'No staged changes', one: '1 staged change', other: '${count} staged changes')}";

  static String m259(was) => "staged · was ${was}";

  static String m260(host) => "Standby: ${host}";

  static String m261(n, total) => "Step ${n} of ${total}";

  static String m262(host) => "Reaching ${host}";

  static String m263(n) => "skipped: needs step ${n}";

  static String m264(n) => "Stopped at step ${n}";

  static String m265(n, code) => "Stopped at step ${n} · ${code}";

  static String m266(why) =>
      "${why}\nWhat was done before it stays done; nothing is reversed by itself.";

  static String m267(version, os) => "${version} (${os})";

  static String m268(version, language) => "Studio ${version} · ${language}";

  static String m269(n) => "ACL denials grew by ${n}";

  static String m270(from) =>
      "acl_denied was ${from} when this screen was last shown";

  static String m271(n) => "Standby is ${n} records behind";

  static String m272(n) => "Forks moved aside after a split: ${n}";

  static String m273(site) => "${site} waits for Authorize";

  static String m274(n) => "A downstream broker that relays sites: ${n}";

  static String m275(id) => "sys/links/${id}/state is failed; its log says why";

  static String m276(id) => "${id} failed";

  static String m277(cn) => "${cn} waits in quarantine";

  static String m278(cn) => "Unknown certificate CN ${cn}";

  static String m279(cn, t) => "Unknown certificate CN ${cn} since ${t}";

  static String m280(size) =>
      "Everything the broker owns is in its `data_dir` (here ${size}). Studio does not take backups: they hold the site\'s keys and are made on the host. The steps, ready to copy:";

  static String m281(n) =>
      "Sets of records moved aside after both brokers were active (a healed split): ${n}. The audit record `standby_forked` says which.";

  static String m282(n) =>
      "${n} registry records are not on the standby yet: a takeover now would lose them.";

  static String m283(n) => "Clear disconnected links (${n})…";

  static String m284(ids) =>
      "${ids}\n\nTheir ids are retired and cannot be used again.";

  static String m285(n) => "Clear ${n} disconnected links…";

  static String m286(ids) => "Removed: ${ids}";

  static String m287(title) => "Copy: ${title}";

  static String m288(url) => "Link to the guide copied: ${url}";

  static String m289(id) => "link: ${id}";

  static String m290(n) => "Lines copied: ${n}";

  static String m291(path) => "Saved ${path}";

  static String m292(n) =>
      "${n} lines from the broker\'s ring · newest first · `sys/~act/get_log`";

  static String m293(n, m, time) =>
      "${n} of ${m} lines within 2 min of ${time} UTC · newest first · `sys/~act/get_log`";

  static String m294(t) => "started ${t}";

  static String m295(n) => "Needs a look · ${n}";

  static String m296(m, time) =>
      "None of the newest ${m} lines is within 2 min of ${time} UTC. Ask for more lines, or clear the time.";

  static String m297(standby) =>
      "2. In `wyrmd.json5` on both hosts: `${standby}` and `peers.listen`; a lease `arbiter` on a third host is recommended.";

  static String m298(t) => "${t} · now";

  static String m299(n) => "of ${n}";

  static String m300(name) =>
      "File ${name}. A .cbor file is sent as it is; a JSON file is encoded first.";

  static String m301(name) => "Profile ${name} put";

  static String m302(name) => "Profile ${name} removed";

  static String m303(reason) =>
      "This broker does not list its profiles through the gateway (${reason}). You can still put one; it is then served at pub/<name>.";

  static String m304(name) => "Remove profile ${name}";

  static String m305(name) =>
      "The broker stops serving pub/${name} and records it in the audit journal (profile_remove).";

  static String m306(cn) => "external · CN ${cn}";

  static String m307(size) => "history ${size} · open History";

  static String m308(id) => "${id} failed · open Links";

  static String m309(site) => "${site} · open Sites";

  static String m310(cn) => "${cn} waits · open Quarantine";

  static String m311(measure, from, to) =>
      "${measure} in and out per second from ${from} to ${to}";

  static String m312(shown, total) => "${shown} of ${total} rows";

  static String m313(level) => "needs ${level}";

  static String m314(who) => "by ${who}";

  static String m315(n) => "failed at step ${n}";

  static String m316(agent) => "Each task is a node: ${agent}/tasks/<id>";

  static String m317(id) => "replaced by ${id}";

  static String m318(site) => "TLS · certificate of the ${site} CA";

  static String m319(seconds) => "hides in ${seconds} s";

  static String m320(site) => "stays until ${site} is back";

  static String m321(site) => "Tree · ${site}";

  static String m322(step) => "${step} avg";

  static String m323(rollup, from, to) => "${rollup} · ${from}–${to}";

  static String m324(at, delta, key, over) =>
      "Δ from A (${at}): ${delta} ${key} over ${over}";

  static String m325(what, range) =>
      "${what}, ${range}. Use the window below to choose the range.";

  static String m326(h, m) => "${h} h ${m} min";

  static String m327(key) => "You may not read ${key}";

  static String m328(t) => "A · ${t}";

  static String m329(min, max) => "min ${min} · max ${max}";

  static String m330(m) => "${m} min";

  static String m331(t) => "raw · ${t}";

  static String m332(s) => "${s} s";

  static String m333(name) => "Show or hide ${name}";

  static String m334(n) => "${n} d";

  static String m335(n) => "${n} h";

  static String m336(n) => "${n} min";

  static String m337(unit) => "unit ${unit}";

  static String m338(d) => "up ${d}";

  static String m339(n) => "Update links: ${n}";

  static String m340(version) => "${version} stays, a link did not answer";

  static String m341(package) =>
      "Bring a zip of the package ${package} with a higher version. The broker checks it as any install and updates every link of the package.";

  static String m342(links) => "Hot start, no restart: ${links}";

  static String m343(version, when) =>
      "${version} stays installed until ${when}. A restore point is sealed for this broker and stays on it.";

  static String m344(n) => "links: ${n}";

  static String m345(n, links) => "Links that restart (${n}): ${links}";

  static String m346(link) => "Open ${link}";

  static String m347(link) => "${link} · before a restore from a backup";

  static String m348(link, version) => "${link} · ${version} · before update";

  static String m349(version, links) =>
      "These links stop and start on ${version}: ${links}. The broker puts their private data back to the restore point of the update when the update changed the store format or did not end well; after an update that ended well they keep the data they have. After it no version is kept: there is no second rollback.";

  static String m350(package, version) => "Roll back ${package} to ${version}?";

  static String m351(version) => "Roll back to ${version}…";

  static String m352(version) => "Rolled back to ${version}";

  static String m353(version) => "The links run ${version}";

  static String m354(links) => "${links}: back with all their nodes.";

  static String m355(state) =>
      "It changes the store format (from state ${state})";

  static String m356(state) => "Store format: same (state ${state})";

  static String m357(back, gone) =>
      "declared again: ${back} · not back yet or gone: ${gone}";

  static String m358(n) => "Custom package · links that run it: ${n}";

  static String m359(n) =>
      "Package of the repository · links that run it: ${n}";

  static String m360(package, from, to) => "Update ${package} ${from} → ${to}";

  static String m361(package, from) => "Update ${package} ${from} from a file";

  static String m362(package) => "${package} updated";

  static String m363(package) => "${package} update rolled back";

  static String m364(package) => "Updating ${package}";

  static String m365(package) => "Versions of ${package}";

  static String m366(version) => "What is new in ${version}";

  static String m367(v) => "Version ${v} · deployed";

  static String m368(site) => "via ${site}";

  static String m369(delimiter, header) =>
      "Read as the block reads it: delimiter ${delimiter}, ${header}";

  static String m370(keys) => "${keys} saves · Esc cancels";

  static String m371(keys) => "${keys} saves · Esc discards the changes";

  static String m372(n, who) => "${n} waiting to be let in: ${who}";

  static String m373(value) => "was ${value}";

  static String m374(n) => "Watch groups · ${n}";

  static String m375(mode) =>
      "With require_approval “${mode}”, the plan of a pick runs its write steps without a person. The tag is the assistant\'s guess, not a check. Read a tile before you pick it.";

  static String m376(user) => "Welcome, ${user}";

  static String m377(value) => "would run on ${value}";

  static String m378(value) => "would send ${value}";

  static String m379(value) => "would write ${value}";

  static String m380(level) => "Turning this on needs ${level} level";

  static String m381(site) => "wyrmd on ${site}";

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
    "addFromExplorer": MessageLookupByLibrary.simpleMessage("+ from Explorer"),
    "addFromExplorerNone": MessageLookupByLibrary.simpleMessage(
      "Select a node in Explorer first; it is added here as @ chip.",
    ),
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
    "argsMasked": MessageLookupByLibrary.simpleMessage(
      "The schema of this step is not known yet (an earlier step makes its node): its arguments are masked, and none goes into a saved plan.",
    ),
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
    "changesGuess": m73,
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
    "childCount": m74,
    "childrenNote": MessageLookupByLibrary.simpleMessage(
      "Select a row: a node opens in the tree, a value opens in the inspector.",
    ),
    "choicesConfirm": MessageLookupByLibrary.simpleMessage("Write the plan"),
    "choicesFromCard": m75,
    "choicesNoAnswer": MessageLookupByLibrary.simpleMessage("no answer"),
    "choicesNote": MessageLookupByLibrary.simpleMessage(
      "Or answer in your own words below.",
    ),
    "choicesOwnWords": m76,
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
    "connectNote": m77,
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
    "dataDir": m78,
    "dataflow": MessageLookupByLibrary.simpleMessage("Dataflow"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Its rights here are cut now and its next connection waits in quarantine. Its sites stay below it.",
    ),
    "deauthorizeTitle": m79,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Decide in Links"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "A link in quarantine is approved or rejected in Links › Quarantine.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("decide in Sites"),
    "deploy": MessageLookupByLibrary.simpleMessage("Deploy"),
    "deployAskMessage": m80,
    "deployAskTitle": MessageLookupByLibrary.simpleMessage("Deploy this flow?"),
    "deployInside": MessageLookupByLibrary.simpleMessage(
      "Go back to the flow to deploy",
    ),
    "deployedByWho": m81,
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
    "doneLeftOutNote": m82,
    "doneNote": MessageLookupByLibrary.simpleMessage(
      "The task is done. Its record keeps the plan and the log.",
    ),
    "doneOnTheDevice": m83,
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
    "editParamsOf": m84,
    "enableUser": MessageLookupByLibrary.simpleMessage("Enable"),
    "errAdviceBroker": m85,
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
    "errAdviceInputField": m86,
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
    "errAdviceRightsRole": m87,
    "errAdviceStudio": MessageLookupByLibrary.simpleMessage(
      "Try it again; restart Studio if it keeps happening.",
    ),
    "errAdviceUnsupported": MessageLookupByLibrary.simpleMessage(
      "This broker or link does not have this call; it may be older than Studio expects.",
    ),
    "errBackToForm": MessageLookupByLibrary.simpleMessage("Back to the form"),
    "errCallOn": m88,
    "errChipStudio": m89,
    "errCopied": MessageLookupByLibrary.simpleMessage("Copied"),
    "errCopyDetails": MessageLookupByLibrary.simpleMessage("Copy details"),
    "errCopyReport": MessageLookupByLibrary.simpleMessage("Copy report"),
    "errDetails": MessageLookupByLibrary.simpleMessage("Details"),
    "errDetailsCopied": MessageLookupByLibrary.simpleMessage(
      "The details are on the clipboard.",
    ),
    "errDoDeploy": m90,
    "errDoInstall": m91,
    "errDoList": m92,
    "errDoLogIn": m93,
    "errDoOpen": m94,
    "errDoRead": m95,
    "errDoRemove": m96,
    "errDoRun": m97,
    "errDoSave": m98,
    "errDoStart": m99,
    "errDoStep": m100,
    "errDoStop": m101,
    "errDoWrite": m102,
    "errDoingDeploy": m103,
    "errDoingInstall": m104,
    "errDoingList": m105,
    "errDoingLogIn": m106,
    "errDoingOpen": m107,
    "errDoingRead": m108,
    "errDoingRemove": m109,
    "errDoingRun": m110,
    "errDoingSave": m111,
    "errDoingStart": m112,
    "errDoingStop": m113,
    "errDoingWrite": m114,
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
    "errNounRun": m115,
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
    "errSilentReach": m116,
    "errSilentStatus": m117,
    "errStatusLine": m118,
    "errThingBroker": MessageLookupByLibrary.simpleMessage("the broker"),
    "errThingThis": MessageLookupByLibrary.simpleMessage("this"),
    "errTimeLocal": m119,
    "errTitleBroker": m120,
    "errTitleBrokerNoSite": m121,
    "errTitleBusy": m122,
    "errTitleGone": m123,
    "errTitleHistory": m124,
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
    "errTitleReach": m125,
    "errTitleReachNoSite": MessageLookupByLibrary.simpleMessage(
      "The broker did not answer",
    ),
    "errTitleRead": m126,
    "errTitleRights": m127,
    "errTitleStream": m128,
    "errTitleStudio": m129,
    "errTitleUnsupported": m130,
    "errTryAgain": MessageLookupByLibrary.simpleMessage("Try again"),
    "errTryAgainIn": m131,
    "errUserRole": m132,
    "errWhatYouCanDo": MessageLookupByLibrary.simpleMessage("What you can do"),
    "errWriteNote": MessageLookupByLibrary.simpleMessage(
      "A write that timed out may still have been applied. Check the value before you send it again.",
    ),
    "eventNone": MessageLookupByLibrary.simpleMessage("not yet"),
    "everySeconds": m133,
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
    "fatalMoveFailed": m134,
    "fatalNote": m135,
    "fatalQuit": MessageLookupByLibrary.simpleMessage("Quit"),
    "fatalTitle": MessageLookupByLibrary.simpleMessage(
      "Studio could not start",
    ),
    "faultBody": MessageLookupByLibrary.simpleMessage(
      "The rest of Studio still works; values and actions elsewhere are not affected.",
    ),
    "faultDrawAgain": MessageLookupByLibrary.simpleMessage("Draw it again"),
    "faultProblem": m136,
    "faultThisPart": MessageLookupByLibrary.simpleMessage("this part"),
    "faultTitle": m137,
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
    "firstSeen": m138,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "The draft does not validate.",
    ),
    "fixReplaces": MessageLookupByLibrary.simpleMessage("replaces this plan"),
    "fixReplacesNoPerson": m139,
    "flowBack": MessageLookupByLibrary.simpleMessage("Back"),
    "flowDeployed": m140,
    "flowError": m141,
    "flowName": MessageLookupByLibrary.simpleMessage("Flow id"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.",
    ),
    "flowPropertiesNote2": MessageLookupByLibrary.simpleMessage(
      "A bound field shows the value that comes in; its wire and source light when you point at it. The link icon goes to the source or unbinds.",
    ),
    "flowStopped": m142,
    "flowVersion": m143,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "A deploy needs config on dataflows; the gateway adds your proofs for each target. Viewers can open a flow and only look.",
    ),
    "flowsOn": m144,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Each flow runs in the broker. You edit a draft; nothing changes until you deploy it.",
    ),
    "fmBlocks": m145,
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
    "fmUnpinField": m146,
    "followNeeds": MessageLookupByLibrary.simpleMessage(
      "only the asker of this task, or config on the agent link, can follow it up",
    ),
    "followUpAsk": m147,
    "followUpLeftOut": MessageLookupByLibrary.simpleMessage(
      "Ask for the steps left out",
    ),
    "fromAddress": m148,
    "fromBackup": MessageLookupByLibrary.simpleMessage("From a backup"),
    "fromBackupNote": MessageLookupByLibrary.simpleMessage(
      "A link backup (.wyrm-link) made by Back up… on a link: its settings, private data and package. It comes back under its own id or a new one.",
    ),
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "From the official list",
    ),
    "gateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "gatewayAnswered": m149,
    "gatewayNoAnswer": m150,
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("Gateway URL"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445, or several separated by commas",
    ),
    "gatewayUser": MessageLookupByLibrary.simpleMessage("Gateway user"),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git repository (HTTPS)",
    ),
    "goTo": m151,
    "goToSource": MessageLookupByLibrary.simpleMessage("Go to source"),
    "goUp": MessageLookupByLibrary.simpleMessage("Go up"),
    "grantFor": m152,
    "grantLevel": MessageLookupByLibrary.simpleMessage("Level"),
    "grantPath": MessageLookupByLibrary.simpleMessage("Key or pattern"),
    "groupBackup": MessageLookupByLibrary.simpleMessage("Backup"),
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
    "hideArgs": MessageLookupByLibrary.simpleMessage("Hide arguments"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Hide password"),
    "hideSteps": MessageLookupByLibrary.simpleMessage("Hide steps"),
    "hintAwaiting": MessageLookupByLibrary.simpleMessage(
      "Ask to change the plan, e.g. “skip step 4”… (a new plan replaces this one)",
    ),
    "hintDone": MessageLookupByLibrary.simpleMessage("What next?"),
    "hintFailed": m153,
    "hintPlanning": MessageLookupByLibrary.simpleMessage(
      "Answer, or ask something else…",
    ),
    "hintRunning": MessageLookupByLibrary.simpleMessage(
      "You can write while it runs…",
    ),
    "historianKeep": m154,
    "historianSeries": m155,
    "historianSize": m156,
    "historyFooter": MessageLookupByLibrary.simpleMessage(
      "Sync links read the historian\'s change journal, so nothing is lost while a database is down.",
    ),
    "historyOf": m157,
    "historyUnavailable": MessageLookupByLibrary.simpleMessage(
      "history unavailable",
    ),
    "historyUnavailableTip": m158,
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
    "inputsCount": m159,
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
    "installedOn": m160,
    "instancesInFlow": m161,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Not a gateway URL (http:// or https:// and a host)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Issue"),
    "keyCopied": MessageLookupByLibrary.simpleMessage("Key copied"),
    "keysCopied": m162,
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
    "lag": m163,
    "languageName": MessageLookupByLibrary.simpleMessage("English"),
    "lastRead": m164,
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
    "linksAlready": m165,
    "linksCount": m166,
    "linksLocalNote": m167,
    "linksOn": m168,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "Connections with a certificate from this site that no link is set up for. They can read and write nothing until you approve them.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "They run on their own machines and connect with a certificate from this site. You decide what they may reach and whether they may stay; the device itself is updated where it runs.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.",
    ),
    "listAnd": m169,
    "listFailedTip": m170,
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
    "logOf": m171,
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
    "mbInUse": m172,
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
    "mbUpdateTo": m173,
    "mbUsed": m174,
    "mbVersion": m175,
    "menuLanguage": MessageLookupByLibrary.simpleMessage("Language"),
    "menuOther": MessageLookupByLibrary.simpleMessage("Other"),
    "menuSubtitle": m176,
    "menuTheme": MessageLookupByLibrary.simpleMessage("Theme"),
    "messagesPerSecond": MessageLookupByLibrary.simpleMessage(
      "Router messages per second",
    ),
    "metaFailedTip": m177,
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
    "modelReviewed": MessageLookupByLibrary.simpleMessage(
      "what the assistant read about it",
    ),
    "modelSays": MessageLookupByLibrary.simpleMessage("the assistant says"),
    "more": MessageLookupByLibrary.simpleMessage("More"),
    "moreButton": m178,
    "moreBytes": m179,
    "moreLines": m180,
    "moreNone": MessageLookupByLibrary.simpleMessage(
      "Tick the nodes the plan is for.",
    ),
    "moreNote": MessageLookupByLibrary.simpleMessage(
      "The rows are the assistant\'s. Its plan for them waits for your approval.",
    ),
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
    "nSelected": m181,
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
    "needsLevelYouHave": m182,
    "needsLevelYouHaveIt": m183,
    "networkError": MessageLookupByLibrary.simpleMessage("Connection problem"),
    "newCertificate": MessageLookupByLibrary.simpleMessage("new certificate"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("New dataflow"),
    "newTask": MessageLookupByLibrary.simpleMessage("New task"),
    "newValue": MessageLookupByLibrary.simpleMessage("New value"),
    "no": MessageLookupByLibrary.simpleMessage("no"),
    "noActionReason": m184,
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
    "noParamReason": m185,
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
    "noUpstream": m186,
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
    "openItsTreeNote": m187,
    "openNodeInExplorer": m188,
    "openReplacement": m189,
    "openingTree": MessageLookupByLibrary.simpleMessage("Opening the tree"),
    "openingTreeOf": m190,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Operate · runs now",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Runs on the device with your rights and is written to the audit.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("package"),
    "packageNamed": m191,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Package from your repository · SHA-256 checked against the index on download",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("Package URL (HTTPS)"),
    "pairsCount": m192,
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
    "paramCount": m193,
    "paramsJson": m194,
    "paramsNotJson": m195,
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
    "planChecked": MessageLookupByLibrary.simpleMessage(
      "awaiting approval · checked",
    ),
    "planCheckedPartly": m196,
    "planNeedsStep": m197,
    "planNote": MessageLookupByLibrary.simpleMessage(
      "The plan is in the task\'s record. Studio shows it when the gateway can read documents (docs/studio.md §10 item 11). Read it with wyrm-agent for now.",
    ),
    "planSaved": m198,
    "planSavedSecrets": m199,
    "planSecretNote": MessageLookupByLibrary.simpleMessage(
      "A secret argument is not shown. The approval is still for the value the plan holds.",
    ),
    "planSleep": m200,
    "planSteps": m201,
    "planTimeout": m202,
    "planWaiting": MessageLookupByLibrary.simpleMessage(
      "The plan waits for approval. Nothing runs before it.",
    ),
    "planWhyNote": MessageLookupByLibrary.simpleMessage(
      "The lines after “why” and under “the assistant says” come from the model; a warning on the yellow band is the link\'s own check. Read the key and the arguments of each step: they are what runs.",
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
    "pointsCount": m203,
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Values update live. Edits are staged in this session; nothing is written to the device until you apply.",
    ),
    "portsCount": m204,
    "preloadBlocks": MessageLookupByLibrary.simpleMessage(
      "Reading the flow blocks",
    ),
    "preloadFlows": MessageLookupByLibrary.simpleMessage("Reading the flows"),
    "preloadLater": m205,
    "preloadLinks": MessageLookupByLibrary.simpleMessage("Reading the links"),
    "preloadSites": MessageLookupByLibrary.simpleMessage("Reading the sites"),
    "preloadTree": m206,
    "previewInvalid": m207,
    "previewTag": MessageLookupByLibrary.simpleMessage("preview"),
    "problems": MessageLookupByLibrary.simpleMessage("Problems"),
    "problemsClear": MessageLookupByLibrary.simpleMessage("Clear all"),
    "problemsClose": MessageLookupByLibrary.simpleMessage("Close problems"),
    "problemsCount": m208,
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
    "qInstalled": m209,
    "qInstalling": m210,
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
    "reachesSites": m211,
    "readAgain": MessageLookupByLibrary.simpleMessage("Read again"),
    "readFailed": MessageLookupByLibrary.simpleMessage("read failed"),
    "readFailedTip": m212,
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
    "refuseNeedsBroker": m213,
    "refuseNoInput": m214,
    "refuseOutput": MessageLookupByLibrary.simpleMessage(
      "Outputs cannot be bound",
    ),
    "refuseSelf": MessageLookupByLibrary.simpleMessage(
      "A block cannot feed itself",
    ),
    "refuseType": m215,
    "reject": MessageLookupByLibrary.simpleMessage("Reject"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "This certificate is refused from now on.",
    ),
    "rejectPlanHint": MessageLookupByLibrary.simpleMessage("Reason"),
    "rejectPlanNote": MessageLookupByLibrary.simpleMessage(
      "The plan is not run. The reason is kept in the task\'s record.",
    ),
    "rejectPlanTitle": MessageLookupByLibrary.simpleMessage("Reject the plan?"),
    "rejectTitle": m216,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Nothing to do from here: it came in with its relay. Deauthorize the relay to cut it off.",
    ),
    "relaysSites": m217,
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
    "removeLinkTitle": m218,
    "removePair": MessageLookupByLibrary.simpleMessage("Remove the last case"),
    "removePort": MessageLookupByLibrary.simpleMessage("Remove the last port"),
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "It stops, its tree is deleted, and its id is retired: it cannot be used again.",
    ),
    "removeUser": MessageLookupByLibrary.simpleMessage("Remove user"),
    "removeUserNote": MessageLookupByLibrary.simpleMessage(
      "They cannot log in again; their sessions end.",
    ),
    "removeUserTitle": m219,
    "replacedNote": m220,
    "replacedTitle": MessageLookupByLibrary.simpleMessage("replaced"),
    "requiredField": MessageLookupByLibrary.simpleMessage("Required field"),
    "resultNoValue": MessageLookupByLibrary.simpleMessage("—"),
    "resultNote": MessageLookupByLibrary.simpleMessage(
      "The keys the plan touched, with their values now.",
    ),
    "resultOf": m221,
    "resultTitle": MessageLookupByLibrary.simpleMessage("Result"),
    "returns": m222,
    "review": MessageLookupByLibrary.simpleMessage("Review"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage("Review and apply"),
    "reviewNote": m223,
    "reviewingNote": MessageLookupByLibrary.simpleMessage(
      "The assistant reads why it stopped…",
    ),
    "revision": m224,
    "revisionNow": m225,
    "rightsLine": m226,
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Without this the broker installs nothing. Grants change later with Grant access; other values with the link\'s params.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "The package asks for these rights",
    ),
    "roleOnSite": m227,
    "rollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Its parameters become a new revision and the link restarts with them.",
    ),
    "rollBackTo": m228,
    "rowsAdd": MessageLookupByLibrary.simpleMessage("Add a row"),
    "rowsAnswered": m229,
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
    "rstFile": m230,
    "rstFileNote": m231,
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
    "rstLinks": m232,
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
    "rstOtherSite": m233,
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
    "rstReplaceKeys": m234,
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
    "rstRestarting": m235,
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
    "rstTitle": m236,
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
    "rstUploading": m237,
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
    "runNowNote": m238,
    "runOff": MessageLookupByLibrary.simpleMessage("The block is disabled"),
    "runOnStartTitle": MessageLookupByLibrary.simpleMessage(
      "Run on every start?",
    ),
    "runPassed": MessageLookupByLibrary.simpleMessage("all steps passed"),
    "runPassedIn": m239,
    "runPassedLeftOut": m240,
    "runRunning": MessageLookupByLibrary.simpleMessage("running…"),
    "runStopped": m241,
    "runStoppedFirst": MessageLookupByLibrary.simpleMessage(
      "stopped · nothing was changed",
    ),
    "runStoppedOne": m242,
    "runStopsNote": MessageLookupByLibrary.simpleMessage(
      "stops at the first step that fails",
    ),
    "runTitle": m243,
    "runTitleEnded": m244,
    "runWaiting": MessageLookupByLibrary.simpleMessage("waiting"),
    "running": MessageLookupByLibrary.simpleMessage("Running"),
    "runningNote": MessageLookupByLibrary.simpleMessage(
      "The agent works on it. Cancel stops it; what was done stays done.",
    ),
    "runsOn": m245,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Runs on another device",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Same call from the CLI",
    ),
    "saveAsPlan": MessageLookupByLibrary.simpleMessage("Save as a plan"),
    "savePlanTitle": m246,
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
    "screenOf": m247,
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
    "setLogLevel": m248,
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
    "showArgs": MessageLookupByLibrary.simpleMessage("Show arguments"),
    "showPassword": MessageLookupByLibrary.simpleMessage("Show password"),
    "showSteps": MessageLookupByLibrary.simpleMessage("Show steps"),
    "signingIn": MessageLookupByLibrary.simpleMessage("Signing in…"),
    "siteRelayedBelow": MessageLookupByLibrary.simpleMessage(
      "Site relayed below",
    ),
    "sitesAround": m249,
    "sitesSubtitle": m250,
    "sizeBytes": m251,
    "sizeChars": m252,
    "sizeColumns": m253,
    "sizeItems": m254,
    "sizeKeys": m255,
    "sizeLines": m256,
    "sizeRows": m257,
    "stage": MessageLookupByLibrary.simpleMessage("Stage"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "Stage puts it into Review and apply with your other edits.",
    ),
    "stagedChanges": m258,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Nothing is written until you apply. Each change runs with your own rights.",
    ),
    "stagedWas": m259,
    "stale": MessageLookupByLibrary.simpleMessage("stale"),
    "standbyAnswersAt": MessageLookupByLibrary.simpleMessage(
      "Its standby answers at",
    ),
    "standbyGateway": MessageLookupByLibrary.simpleMessage("Standby gateway"),
    "standbyIs": m260,
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
    "stepOf": m261,
    "stepReaching": m262,
    "stepReading": MessageLookupByLibrary.simpleMessage(
      "Reading your role and sites",
    ),
    "stepSkippedNeeds": m263,
    "stepWhere": MessageLookupByLibrary.simpleMessage("Where it runs"),
    "stopRecording": MessageLookupByLibrary.simpleMessage("Stop recording"),
    "stoppedAt": m264,
    "stoppedAtCode": m265,
    "stoppedNote": m266,
    "studioAbout": m267,
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio is signed in here",
    ),
    "studioVersion": m268,
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
    "sysAttnAcl": m269,
    "sysAttnAclDetail": m270,
    "sysAttnBehind": m271,
    "sysAttnBehindDetail": m272,
    "sysAttnBehindPlain": MessageLookupByLibrary.simpleMessage(
      "standby_lag is above 0: a takeover now loses records",
    ),
    "sysAttnBroker": m273,
    "sysAttnBrokerPlain": MessageLookupByLibrary.simpleMessage(
      "A downstream broker",
    ),
    "sysAttnBrokerRelays": m274,
    "sysAttnFork": MessageLookupByLibrary.simpleMessage(
      "The standby moved a fork aside",
    ),
    "sysAttnLinkDetail": m275,
    "sysAttnLinkFailed": m276,
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
    "sysAttnQuarantine": m277,
    "sysAttnQuarantineDetail": m278,
    "sysAttnQuarantineSince": m279,
    "sysBackup": MessageLookupByLibrary.simpleMessage("Back up and restore"),
    "sysBackupNote": m280,
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
    "sysBannerForks": m281,
    "sysBannerLag": m282,
    "sysBrokerAll": MessageLookupByLibrary.simpleMessage("broker (all)"),
    "sysBrokerLogLevel": MessageLookupByLibrary.simpleMessage(
      "Broker log level",
    ),
    "sysBytes": MessageLookupByLibrary.simpleMessage("Bytes"),
    "sysClear": m283,
    "sysClearAsk": MessageLookupByLibrary.simpleMessage(
      "Clear these disconnected links?",
    ),
    "sysClearAskBody": m284,
    "sysClearBoard": m285,
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
    "sysCleared": m286,
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
    "sysCopyCommand": m287,
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
    "sysGuideCopied": m288,
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
    "sysLinkSource": m289,
    "sysLogCopied": m290,
    "sysLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Staged in Review and apply; once applied it takes effect at once, no restart, and replaces `RUST_LOG`. Zenoh stays at warn below trace. Values and tokens are never logged below trace. A link\'s own level: Links › the link › Log.",
    ),
    "sysLogNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "The log is read with config on sys.",
    ),
    "sysLogNotSaved": MessageLookupByLibrary.simpleMessage(
      "Cannot save the log",
    ),
    "sysLogSaved": m291,
    "sysLogSummary": m292,
    "sysLogSummaryAround": m293,
    "sysLogSummaryNone": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/get_log` · config",
    ),
    "sysMessages": MessageLookupByLibrary.simpleMessage("Messages"),
    "sysMetaStarted": m294,
    "sysNeedsLook": m295,
    "sysNeedsLookNote": MessageLookupByLibrary.simpleMessage(
      "From the broker\'s own values. Each opens the screen where it is fixed.",
    ),
    "sysNoLines": MessageLookupByLibrary.simpleMessage(
      "No lines at this level.",
    ),
    "sysNoLinesAround": m296,
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
    "sysNoStandbyStep2": m297,
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
    "sysNow": m298,
    "sysOfTotal": m299,
    "sysOpenAuditRecord": MessageLookupByLibrary.simpleMessage(
      "Open the audit record ›",
    ),
    "sysOut": MessageLookupByLibrary.simpleMessage("out"),
    "sysPackages": MessageLookupByLibrary.simpleMessage("Packages"),
    "sysProfileFile": m300,
    "sysProfileName": MessageLookupByLibrary.simpleMessage("Name"),
    "sysProfileNameHint": MessageLookupByLibrary.simpleMessage(
      "<vendor>:<model>",
    ),
    "sysProfilePut": m301,
    "sysProfileRemoved": m302,
    "sysProfiles": MessageLookupByLibrary.simpleMessage("Device profiles"),
    "sysProfilesFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/profiles` › Put Profile, Remove Profile · config",
    ),
    "sysProfilesNote": MessageLookupByLibrary.simpleMessage(
      "Models served as `pub/<vendor>:<model>`: points, units and ranges that links and the assistant inherit.",
    ),
    "sysProfilesUnlisted": m303,
    "sysPulled": MessageLookupByLibrary.simpleMessage("pulled every 1 s"),
    "sysPut": MessageLookupByLibrary.simpleMessage("Put profile"),
    "sysPutProfile": MessageLookupByLibrary.simpleMessage("Put profile…"),
    "sysRecords": MessageLookupByLibrary.simpleMessage("records"),
    "sysRemove": MessageLookupByLibrary.simpleMessage("Remove"),
    "sysRemoveProfile": m304,
    "sysRemoveProfileAsk": m305,
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
    "sysStaleRow": m306,
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
    "sysSubData": m307,
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
    "sysSubLinkFailed": m308,
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
    "sysSubPeer": m309,
    "sysSubSessions": MessageLookupByLibrary.simpleMessage(
      "network sessions; gateway users not counted",
    ),
    "sysSubWaits": m310,
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
    "sysTrafficDescribe": m311,
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
    "tableFiltered": m312,
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
    "tagNeeds": m313,
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("runs now"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("staged"),
    "taskAwaiting": MessageLookupByLibrary.simpleMessage("awaiting approval"),
    "taskAwaitingAnswer": MessageLookupByLibrary.simpleMessage(
      "awaiting your answer",
    ),
    "taskBy": m314,
    "taskDone": MessageLookupByLibrary.simpleMessage("done"),
    "taskFailed": MessageLookupByLibrary.simpleMessage("failed or stopped"),
    "taskFailedAt": m315,
    "taskListNote": m316,
    "taskNoChanges": MessageLookupByLibrary.simpleMessage("nothing changed"),
    "taskPlanning": MessageLookupByLibrary.simpleMessage("planning"),
    "taskReplaced": m317,
    "taskRunning": MessageLookupByLibrary.simpleMessage("running"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("this broker"),
    "tlsCertificateOf": m318,
    "toAccept": MessageLookupByLibrary.simpleMessage("to accept"),
    "toastDismiss": MessageLookupByLibrary.simpleMessage("Dismiss"),
    "toastHidesIn": m319,
    "toastNotifications": MessageLookupByLibrary.simpleMessage("Notifications"),
    "toastStays": m320,
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
    "treeOf": m321,
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
    "trendAvg": m322,
    "trendBadRecorded": MessageLookupByLibrary.simpleMessage(
      "bad quality recorded",
    ),
    "trendBucket": m323,
    "trendClearMarker": MessageLookupByLibrary.simpleMessage(
      "Click A again to clear it",
    ),
    "trendDelta": m324,
    "trendDescribe": m325,
    "trendFollowNow": MessageLookupByLibrary.simpleMessage("Follow now"),
    "trendHint": MessageLookupByLibrary.simpleMessage(
      "Hover for values · drag on the chart to zoom · click to set marker A · drag or resize the window below · double-click resets · ← → move the focused handle",
    ),
    "trendHoursMinutes": m326,
    "trendLocked": m327,
    "trendMarker": m328,
    "trendMinMax": m329,
    "trendMinutes": m330,
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
    "trendRawAt": m331,
    "trendResetZoom": MessageLookupByLibrary.simpleMessage("Reset zoom"),
    "trendSeconds": m332,
    "trendSetMarker": MessageLookupByLibrary.simpleMessage(
      "Click to set marker A",
    ),
    "trendShowHide": m333,
    "trendStepDays": m334,
    "trendStepHours": m335,
    "trendStepMinutes": m336,
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
    "unitNumber": m337,
    "unpinField": MessageLookupByLibrary.simpleMessage("Unpin from block"),
    "unreachableAdvice": MessageLookupByLibrary.simpleMessage(
      "The broker may be restarting or this computer is on another network.",
    ),
    "unsubscribeNote": MessageLookupByLibrary.simpleMessage(
      "The point stops being recorded; its rows stay.",
    ),
    "upFor": m338,
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
    "updDo": m339,
    "updFailed": m340,
    "updFailedNote": MessageLookupByLibrary.simpleMessage(
      "The health check ended without an answer from every link.",
    ),
    "updFromFile": MessageLookupByLibrary.simpleMessage("A newer archive"),
    "updFromFileNote": m341,
    "updFromFileRow": MessageLookupByLibrary.simpleMessage("Update from file…"),
    "updGoneTile": MessageLookupByLibrary.simpleMessage("gone"),
    "updHotStart": m342,
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
    "updKeptUntil": m343,
    "updLeave": MessageLookupByLibrary.simpleMessage(
      "You can leave this screen; it goes on.",
    ),
    "updLinksCount": m344,
    "updLinksRestart": m345,
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
    "updOpenLink": m346,
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
    "updPointBeforeRestore": m347,
    "updPointBeforeUpdate": m348,
    "updPoints": MessageLookupByLibrary.simpleMessage("Restore points"),
    "updRights": MessageLookupByLibrary.simpleMessage("Rights and network"),
    "updRightsNote": MessageLookupByLibrary.simpleMessage(
      "If the new version asks for more than the links have, the broker installs nothing and lists them here for you to accept.",
    ),
    "updRollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "updRollBackNote": m349,
    "updRollBackTitle": m350,
    "updRollBackTo": m351,
    "updRolledBackNote": MessageLookupByLibrary.simpleMessage(
      "The links run the kept version again.",
    ),
    "updRolledBackTo": m352,
    "updRowChecking": MessageLookupByLibrary.simpleMessage("being checked"),
    "updRuns": m353,
    "updRunsNote": m354,
    "updStateChanges": m355,
    "updStateChangesNote": MessageLookupByLibrary.simpleMessage(
      "The old version cannot read the new store: a rollback restores the store of the restore point.",
    ),
    "updStateCustom": MessageLookupByLibrary.simpleMessage(
      "Store format: the archive says",
    ),
    "updStateCustomNote": MessageLookupByLibrary.simpleMessage(
      "If the archive does not read the installed store format, the broker refuses an update without a restore point.",
    ),
    "updStateSame": m356,
    "updStateSameNote": MessageLookupByLibrary.simpleMessage(
      "The new version reads the store of the installed one.",
    ),
    "updStepNodes": MessageLookupByLibrary.simpleMessage(
      "Health: every link back with its nodes",
    ),
    "updStepNodesCount": m357,
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
    "updSubCustom": m358,
    "updSubOfficial": m359,
    "updTab": MessageLookupByLibrary.simpleMessage("Updates"),
    "updTabNote": MessageLookupByLibrary.simpleMessage(
      "Links whose package has a newer version. Every link of a package is updated together, and the broker keeps what it needs to go back.",
    ),
    "updThen": MessageLookupByLibrary.simpleMessage("Then"),
    "updTitle": m360,
    "updTitleCustom": m361,
    "updTitleDone": m362,
    "updTitleRolledBack": m363,
    "updTogether": MessageLookupByLibrary.simpleMessage("updated together"),
    "updUpdating": m364,
    "updUpdatingButton": MessageLookupByLibrary.simpleMessage("Updating…"),
    "updUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Values of its links pause while each restarts.",
    ),
    "updVersionsOf": m365,
    "updWhatChanges": MessageLookupByLibrary.simpleMessage(
      "What changes for the broker",
    ),
    "updWhatIsNew": m366,
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
    "versionDeployed": m367,
    "viaSite": m368,
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
    "viewerCsvRules": m369,
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
    "viewerSaveHint": m370,
    "viewerTabTable": MessageLookupByLibrary.simpleMessage("As table"),
    "viewerTabText": MessageLookupByLibrary.simpleMessage("Text"),
    "viewerTableHint": m371,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Waiting in quarantine",
    ),
    "waitingToBeLetIn": m372,
    "wasValue": m373,
    "wasWord": MessageLookupByLibrary.simpleMessage("was"),
    "watchGroup": MessageLookupByLibrary.simpleMessage("Watch group"),
    "watchGroups": m374,
    "waysCaution": m375,
    "waysNote": MessageLookupByLibrary.simpleMessage(
      "A pick is a new ask. Its plan is checked and waits for your approval, step by step.",
    ),
    "waysOut": MessageLookupByLibrary.simpleMessage("Ways out"),
    "welcomeUser": m376,
    "whatItRead": MessageLookupByLibrary.simpleMessage("What it read"),
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
    "whyNew": MessageLookupByLibrary.simpleMessage("New"),
    "whyRunBackup": MessageLookupByLibrary.simpleMessage(
      "Keep its id to restore it, or give a new one to make a second link. The mode is the one it ran in.",
    ),
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
    "wouldRun": m377,
    "wouldSend": m378,
    "wouldWrite": m379,
    "writableNeeds": m380,
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
    "wyrmdOn": m381,
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
