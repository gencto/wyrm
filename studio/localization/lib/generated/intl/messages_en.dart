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
      "${Intl.plural(n, one: 'Approve 1 change and run', other: 'Approve ${n} changes and run')}";

  static String m8(site) =>
      "This task is on site ${site}. This gateway signs approvals only for tasks of its own site. Approve it through the gateway of ${site}.";

  static String m9(why) =>
      "The approval was refused; the task still waits. ${why}";

  static String m10(role) =>
      "Signs one token per ticked step with your rights (${role}). Unticked steps are left out.";

  static String m11(count) => "Ask an admin for ${count}";

  static String m12(n) => "asks to join · relays ${n}";

  static String m13(sites) => "asks to relay: ${sites}";

  static String m14(code) => "refused (${code})";

  static String m15(id) =>
      "A link ${id} exists on this broker: it is replaced in place (same driver and mode), and a restore point of it is taken first.";

  static String m16(size, rights) => "About ${size} · ${rights}";

  static String m17(days) =>
      "Made while the broker runs, kept on it for ${days} days. Download one or send it to a file store.";

  static String m18(name) => "Choose the folder for ${name}";

  static String m19(link) => "Back up ${link}";

  static String m20(when) => "Kept on the broker until ${when} (Backups).";

  static String m21(done, size) => "Downloading: ${done} of ${size}";

  static String m22(what) => "Backup of ${what} failed";

  static String m23(site) =>
      "It holds the site\'s keys: whoever has the file and the passphrase is an administrator of ${site}.";

  static String m24(link) => "link ${link}";

  static String m25(n) => "At least ${n} characters";

  static String m26(what) => "Backing up ${what}";

  static String m27(name) => "Remove ${name}?";

  static String m28(percent) => "being made · ${percent} %";

  static String m29(percent) => "sending · ${percent} %";

  static String m30(name) => "Saved ${name}";

  static String m31(size, n) => "${size} · sections: ${n}";

  static String m32(path) => "Saved to ${path}; SHA-256 checked.";

  static String m33(site) =>
      "sealed for ${site}: opens only on a broker with its keys";

  static String m34(error) => "Not sent: ${error}";

  static String m35(to) => "Sending to ${to}";

  static String m36(link) =>
      "One .wyrm-link file with what ${link} needs to come back, here or on another broker.";

  static String m37(site) => "Back up ${site}";

  static String m38(link) => "Back up the link ${link}";

  static String m39(days) => "Kept in Backups for ${days} days.";

  static String m40(days) =>
      "Downloaded in parts when it is ready; also kept on the broker for ${days} days.";

  static String m41(n) =>
      "${Intl.plural(n, one: '1 block', other: '${n} blocks')}";

  static String m42(brokers, devices) =>
      "${brokers} brokers · ${devices} devices";

  static String m43(driver) => "built-in driver ${driver}";

  static String m44(version) => "Back on ${version}";

  static String m45(tried, version) =>
      "${tried} did not pass its trial start. The next start went back to ${version} and restored the control plane from the pre-update backup.";

  static String m46(version, latest) => "${version} · ${latest} is available";

  static String m47(version) => "${version} · up to date";

  static String m48(version) => "${version} · the update was rolled back";

  static String m49(version) => "${version} is on trial";

  static String m50(version) =>
      "If the new version writes a newer SCHEMA, ${version} cannot read it afterwards: a rollback restores the pre-update backup of the control plane, so changes made after the update are lost on rollback.";

  static String m51(from, to) => "Stopped on ${from}, started on ${to}";

  static String m52(version) => "${version} staged";

  static String m53(back, all, seconds) => "${back} of ${all} in ${seconds} s";

  static String m54(time) =>
      "Studio lost the gateway and tries again by itself · ${time}";

  static String m55(version) => "Open the log of ${version}";

  static String m56(site, version) => "${site} is restarting on ${version}";

  static String m57(site, version) => "Roll back ${site} to ${version}?";

  static String m58(when) => "possible until ${when}";

  static String m59(site, version) => "${site} runs ${version}";

  static String m60(version) =>
      "The update is confirmed; ${version} and the pre-update backup are kept for a rollback.";

  static String m61(n) => "${n} s";

  static String m62(version) =>
      "The new binary is staged beside the current one; ${version} stays on disk.";

  static String m63(version) =>
      "The broker stops cleanly and the service manager starts ${version} (about 5–15 s without the broker).";

  static String m64(version) =>
      "${version} runs on trial: it must have the router, the gateway and its links back within 3 min.";

  static String m65(version) =>
      "Then it confirms itself. If it does not, the next start goes back to ${version} with the backup of step 1.";

  static String m66(site, version) => "Update ${site} to wyrmd ${version}";

  static String m67(site) => "Type ${site} to confirm";

  static String m68(site) => "${site} updated";

  static String m69(site) => "Updating ${site}";

  static String m70(site) => "CA-signed · ${site} CA";

  static String m71(n) =>
      "${Intl.plural(n, one: '1 block becomes', other: '${n} blocks become')} one block of this flow. Wires that cross its edge become its inputs and outputs.";

  static String m72(count) =>
      "${Intl.plural(count, zero: 'no children', one: '1 child', other: '${count} children')}";

  static String m73(site) =>
      "${site} dials out to it; it authorizes ${site} there.";

  static String m74(size) => "data_dir ${size}";

  static String m75(id) => "Deauthorize ${id}?";

  static String m76(flow) =>
      "The draft of “${flow}” replaces the version that runs now.";

  static String m77(who) => "deployed by ${who}";

  static String m78(steps) =>
      "The task is done. Steps left out: ${steps}. Ask for them as a follow-up; its plan is approved on its own.";

  static String m79(device) =>
      "It runs on ${device}; the broker cannot start or stop it.";

  static String m80(id) => "Edit params of ${id}";

  static String m81(time) =>
      "The broker log around ${time} has the rest of the story.";

  static String m82(field) =>
      "Back in the form, the field ${field} is marked; correct it and send again.";

  static String m83(role, site) =>
      "Your role is ${role}. Nothing was changed on ${site}.";

  static String m84(call, key) => "${call} on ${key}";

  static String m85(type) => "studio · ${type}";

  static String m86(thing) => "deploy ${thing}";

  static String m87(thing) => "install ${thing}";

  static String m88(thing) => "list ${thing}";

  static String m89(thing) => "log in to ${thing}";

  static String m90(thing) => "open ${thing}";

  static String m91(thing) => "read ${thing}";

  static String m92(thing) => "remove ${thing}";

  static String m93(call, thing) => "run ${call} on ${thing}";

  static String m94(thing) => "save ${thing}";

  static String m95(thing) => "start ${thing}";

  static String m96(step) => "finish “${step}”";

  static String m97(thing) => "stop ${thing}";

  static String m98(thing) => "write ${thing}";

  static String m99(thing) => "Deploying ${thing}";

  static String m100(thing) => "Installing ${thing}";

  static String m101(thing) => "Listing ${thing}";

  static String m102(thing) => "Logging in to ${thing}";

  static String m103(thing) => "Opening ${thing}";

  static String m104(thing) => "Reading ${thing}";

  static String m105(thing) => "Removing ${thing}";

  static String m106(call, thing) => "${call} on ${thing}";

  static String m107(thing) => "Saving ${thing}";

  static String m108(thing) => "Starting ${thing}";

  static String m109(thing) => "Stopping ${thing}";

  static String m110(thing) => "Writing ${thing}";

  static String m111(call) => "${call}";

  static String m112(site) => "No answer from the broker at ${site}.";

  static String m113(status) =>
      "The broker answered ${status} and sent no message.";

  static String m114(status, message) => "${status}: ${message}";

  static String m115(time) => "${time} (local)";

  static String m116(doing, site) => "${doing} failed on ${site}";

  static String m117(doing) => "${doing} failed";

  static String m118(site, what) => "${site} is busy, ${what} did not start";

  static String m119(thing) => "${thing} is not there anymore";

  static String m120(thing) => "History of ${thing} unavailable";

  static String m121(site) => "${site} did not answer";

  static String m122(thing) => "Reading ${thing} failed";

  static String m123(what) => "You can’t ${what}";

  static String m124(site) => "Live values from ${site} stopped";

  static String m125(what) => "Studio could not ${what}";

  static String m126(thing, call) => "${thing} does not support ${call}";

  static String m127(seconds) => "Try again in ${seconds} s";

  static String m128(user, role) => "${user} (${role})";

  static String m129(s) => "every ${s} s";

  static String m130(reason) =>
      "The unreadable file could not be moved aside: ${reason}";

  static String m131(name) =>
      "Fresh settings keep the unreadable file beside the new one as ${name}. You add your gateways and log in again.";

  static String m132(panel) => "Studio could not draw ${panel}";

  static String m133(panel) => "The ${panel} could not be drawn";

  static String m134(when) => "first seen ${when}";

  static String m135(v) => "v${v} deployed";

  static String m136(v) => "v${v} · error";

  static String m137(v) => "v${v} stopped";

  static String m138(v) => "Version ${v}";

  static String m139(site) => "Flows on ${site}";

  static String m140(count) => "${count} blocks";

  static String m141(label) => "Unpin “${label}” from block";

  static String m142(task, steps) =>
      "Do the steps that were left out of the plan of task ${task}: ${steps}.";

  static String m143(address) => "from ${address}";

  static String m144(host, ms) => "${host} · answered in ${ms} ms";

  static String m145(host) => "No answer from ${host}";

  static String m146(key) => "Go to ${key}";

  static String m147(id) => "Grant access to ${id}";

  static String m148(days) => "raw kept ${days} d";

  static String m149(n) => "${n} series";

  static String m150(size) => "Historian ${size}";

  static String m151(id) => "Params history of ${id}";

  static String m152(status) =>
      "Reading the history failed: ${status}. Details in Problems.";

  static String m153(n) =>
      "${Intl.plural(n, one: '1 input', other: '${n} inputs')}";

  static String m154(name, broker) => "${name} is installed on ${broker}.";

  static String m155(n) =>
      "${Intl.plural(n, zero: 'no instance in this flow', one: '1 instance in this flow', other: '${n} instances in this flow')} · a change here changes them all";

  static String m156(count) => "${count} keys copied";

  static String m157(lag) => "lag ${lag}";

  static String m158(time) => "last read ${time}";

  static String m159(n) =>
      "${Intl.plural(n, one: '1 link already', other: '${n} links already')}";

  static String m160(n) =>
      "${Intl.plural(n, one: '1 link', other: '${n} links')}";

  static String m161(site) =>
      "Started and watched by ${site}: built-in drivers and installed packages. You can stop, change, upgrade and remove them.";

  static String m162(site) => "Links on ${site}";

  static String m163(first, last) => "${first} and ${last}";

  static String m164(status) =>
      "Reading the list of children failed: ${status}. Details in Problems.";

  static String m165(id) => "Log of ${id}";

  static String m166(n) =>
      "${Intl.plural(n, one: '1 instance uses it', other: '${n} instances use it')}";

  static String m167(n) => "library v${n}";

  static String m168(n) => "${n} used";

  static String m169(n) => "v${n}";

  static String m170(kind, count) => "${kind} · ${count} actions";

  static String m171(status) =>
      "Reading the description failed: ${status}. Details in Problems.";

  static String m172(count) =>
      "${Intl.plural(count, one: '… 1 more byte', other: '… ${count} more bytes')}";

  static String m173(count) =>
      "${Intl.plural(count, one: '1 more line', other: '${count} more lines')}";

  static String m174(count) => "${count} selected";

  static String m175(level, have) => "Needs ${level} · you have ${have}";

  static String m176(level) => "Needs ${level} · you have it";

  static String m177(action) => "This node has no ${action} action.";

  static String m178(param) => "The driver has no ${param} parameter.";

  static String m179(site) => "none: ${site} is the top";

  static String m180(site) => "Explorer shows wy/${site}.";

  static String m181(node) => "Open ${node} in Explorer";

  static String m182(site) => "Opening the tree of ${site}…";

  static String m183(name) => "package ${name}";

  static String m184(n) =>
      "${Intl.plural(n, one: '1 case', other: '${n} cases')}";

  static String m185(n) =>
      "${Intl.plural(n, zero: 'no parameters', one: '1 parameter', other: '${n} parameters')}";

  static String m186(rev) => "Parameters (revision ${rev}, JSON)";

  static String m187(detail) => "Not JSON: ${detail}";

  static String m188(n) => "needs step ${n}";

  static String m189(path) => "Saved ${path}. Run it with wyrm-agent run.";

  static String m190(s) => "${s} s";

  static String m191(n) => "Plan · ${n} steps";

  static String m192(s) => "timeout ${s} s";

  static String m193(n) =>
      "${Intl.plural(n, one: '1 point', other: '${n} points')}";

  static String m194(n) =>
      "${Intl.plural(n, one: '1 port', other: '${n} ports')}";

  static String m195(step) => "${step} · later";

  static String m196(site) => "Reading the tree of ${site}";

  static String m197(message) => "The draft does not run: ${message}";

  static String m198(count) =>
      "${Intl.plural(count, one: '1 problem', other: '${count} problems')}";

  static String m199(name) => "${name} is installed";

  static String m200(name) => "Installing ${name}…";

  static String m201(sites) => "reaches ${sites}";

  static String m202(status) =>
      "Reading the value failed: ${status}. Details in Problems.";

  static String m203(field) =>
      "This broker cannot bind ${field} (its flow engine is older than ADR 0040)";

  static String m204(field) => "${field} takes no input: type its value";

  static String m205(from, to) => "${from} does not fit ${to}";

  static String m206(cn) => "Reject ${cn}?";

  static String m207(n) =>
      "${Intl.plural(n, one: 'relays 1 site', other: 'relays ${n} sites')}";

  static String m208(id) => "Remove ${id}?";

  static String m209(name) => "Remove ${name}?";

  static String m210(action) => "Result · ${action}";

  static String m211(what) => "returns ${what}";

  static String m212(audit) =>
      "Each write is checked by the link and recorded in ${audit}. A value shows only after it is read back.";

  static String m213(rev) => "Revision ${rev}";

  static String m214(rev) => "Revision ${rev} · in use";

  static String m215(site, user, role, level) =>
      "Site ${site} · applied with your rights: ${user}, ${role} (${level})";

  static String m216(role, site) => "${role} on ${site}";

  static String m217(rev) => "Roll back to revision ${rev}?";

  static String m218(n) =>
      "${Intl.plural(n, one: '1 row', other: '${n} rows')}";

  static String m219(site, broker) => "From ${site} · wyrmd ${broker}";

  static String m220(when, n, sealed) =>
      "Made ${when} · sections: ${n} · secrets: ${sealed}";

  static String m221(fresh, exists) =>
      "Links: ${fresh} new, ${exists} exist here";

  static String m222(site) => "A backup of another site: ${site}";

  static String m223(files) => "Replace the site\'s keys: ${files}";

  static String m224(site) => "${site} restarts and applies the backup";

  static String m225(site) => "Restore ${site} from a backup";

  static String m226(done, size) => "Uploading: ${done} of ${size}";

  static String m227(user) =>
      "Runs as ${user}. Nothing else in the tree changes unless the result is used.";

  static String m228(s) => "all steps passed · ${s} s";

  static String m229(steps) => "done · steps left out: ${steps}";

  static String m230(k) => "stopped · steps 1–${k} stay done";

  static String m231(n, of) => "Run · step ${n} of ${of}";

  static String m232(of) => "Run · ${of} steps";

  static String m233(site) => "Runs on ${site}";

  static String m234(task) => "Save the plan of ${task}";

  static String m235(name) => "${name}";

  static String m236(level) => "Log level ${level}";

  static String m237(site) => "Sites around ${site}";

  static String m238(site) =>
      "What ${site} connects to and what connects to it: brokers above and below, platforms it sends to, and devices whose links run outside any broker.";

  static String m239(count) =>
      "${Intl.plural(count, one: '1 byte', other: '${count} bytes')}";

  static String m240(count) =>
      "${Intl.plural(count, one: '1 char', other: '${count} chars')}";

  static String m241(count) =>
      "${Intl.plural(count, one: '1 column', other: '${count} columns')}";

  static String m242(count) =>
      "${Intl.plural(count, one: '1 item', other: '${count} items')}";

  static String m243(count) =>
      "${Intl.plural(count, one: '1 key', other: '${count} keys')}";

  static String m244(count) =>
      "${Intl.plural(count, one: '1 line', other: '${count} lines')}";

  static String m245(count) =>
      "${Intl.plural(count, one: '1 row', other: '${count} rows')}";

  static String m246(count) =>
      "${Intl.plural(count, zero: 'No staged changes', one: '1 staged change', other: '${count} staged changes')}";

  static String m247(was) => "staged · was ${was}";

  static String m248(host) => "Standby: ${host}";

  static String m249(n, total) => "Step ${n} of ${total}";

  static String m250(host) => "Reaching ${host}";

  static String m251(n) => "skipped: needs step ${n}";

  static String m252(n) => "Stopped at step ${n}";

  static String m253(why) =>
      "${why}\nWhat was done before it stays done; nothing is reversed by itself.";

  static String m254(version, os) => "${version} (${os})";

  static String m255(version, language) => "Studio ${version} · ${language}";

  static String m256(n) => "ACL denials grew by ${n}";

  static String m257(from) =>
      "acl_denied was ${from} when this screen was last shown";

  static String m258(n) => "Standby is ${n} records behind";

  static String m259(n) => "Forks moved aside after a split: ${n}";

  static String m260(site) => "${site} waits for Authorize";

  static String m261(n) => "A downstream broker that relays sites: ${n}";

  static String m262(id) => "sys/links/${id}/state is failed; its log says why";

  static String m263(id) => "${id} failed";

  static String m264(cn) => "${cn} waits in quarantine";

  static String m265(cn) => "Unknown certificate CN ${cn}";

  static String m266(cn, t) => "Unknown certificate CN ${cn} since ${t}";

  static String m267(size) =>
      "Everything the broker owns is in its `data_dir` (here ${size}). Studio does not take backups: they hold the site\'s keys and are made on the host. The steps, ready to copy:";

  static String m268(n) =>
      "Sets of records moved aside after both brokers were active (a healed split): ${n}. The audit record `standby_forked` says which.";

  static String m269(n) =>
      "${n} registry records are not on the standby yet: a takeover now would lose them.";

  static String m270(n) => "Clear disconnected links (${n})…";

  static String m271(ids) =>
      "${ids}\n\nTheir ids are retired and cannot be used again.";

  static String m272(n) => "Clear ${n} disconnected links…";

  static String m273(ids) => "Removed: ${ids}";

  static String m274(title) => "Copy: ${title}";

  static String m275(url) => "Link to the guide copied: ${url}";

  static String m276(id) => "link: ${id}";

  static String m277(n) => "Lines copied: ${n}";

  static String m278(path) => "Saved ${path}";

  static String m279(n) =>
      "${n} lines from the broker\'s ring · newest first · `sys/~act/get_log`";

  static String m280(n, m, time) =>
      "${n} of ${m} lines within 2 min of ${time} UTC · newest first · `sys/~act/get_log`";

  static String m281(t) => "started ${t}";

  static String m282(n) => "Needs a look · ${n}";

  static String m283(m, time) =>
      "None of the newest ${m} lines is within 2 min of ${time} UTC. Ask for more lines, or clear the time.";

  static String m284(standby) =>
      "2. In `wyrmd.json5` on both hosts: `${standby}` and `peers.listen`; a lease `arbiter` on a third host is recommended.";

  static String m285(t) => "${t} · now";

  static String m286(n) => "of ${n}";

  static String m287(name) =>
      "File ${name}. A .cbor file is sent as it is; a JSON file is encoded first.";

  static String m288(name) => "Profile ${name} put";

  static String m289(name) => "Profile ${name} removed";

  static String m290(reason) =>
      "This broker does not list its profiles through the gateway (${reason}). You can still put one; it is then served at pub/<name>.";

  static String m291(name) => "Remove profile ${name}";

  static String m292(name) =>
      "The broker stops serving pub/${name} and records it in the audit journal (profile_remove).";

  static String m293(cn) => "external · CN ${cn}";

  static String m294(size) => "history ${size} · open History";

  static String m295(id) => "${id} failed · open Links";

  static String m296(site) => "${site} · open Sites";

  static String m297(cn) => "${cn} waits · open Quarantine";

  static String m298(measure, from, to) =>
      "${measure} in and out per second from ${from} to ${to}";

  static String m299(shown, total) => "${shown} of ${total} rows";

  static String m300(level) => "needs ${level}";

  static String m301(who) => "by ${who}";

  static String m302(n) => "failed at step ${n}";

  static String m303(agent) => "Each task is a node: ${agent}/tasks/<id>";

  static String m304(site) => "TLS · certificate of the ${site} CA";

  static String m305(seconds) => "hides in ${seconds} s";

  static String m306(site) => "stays until ${site} is back";

  static String m307(site) => "Tree · ${site}";

  static String m308(step) => "${step} avg";

  static String m309(rollup, from, to) => "${rollup} · ${from}–${to}";

  static String m310(at, delta, key, over) =>
      "Δ from A (${at}): ${delta} ${key} over ${over}";

  static String m311(what, range) =>
      "${what}, ${range}. Use the window below to choose the range.";

  static String m312(h, m) => "${h} h ${m} min";

  static String m313(key) => "You may not read ${key}";

  static String m314(t) => "A · ${t}";

  static String m315(min, max) => "min ${min} · max ${max}";

  static String m316(m) => "${m} min";

  static String m317(t) => "raw · ${t}";

  static String m318(s) => "${s} s";

  static String m319(name) => "Show or hide ${name}";

  static String m320(n) => "${n} d";

  static String m321(n) => "${n} h";

  static String m322(n) => "${n} min";

  static String m323(unit) => "unit ${unit}";

  static String m324(d) => "up ${d}";

  static String m325(n) => "Update links: ${n}";

  static String m326(version) => "${version} stays, a link did not answer";

  static String m327(package) =>
      "Bring a zip of the package ${package} with a higher version. The broker checks it as any install and updates every link of the package.";

  static String m328(links) => "Hot start, no restart: ${links}";

  static String m329(version, when) =>
      "${version} stays installed until ${when}. A restore point is sealed for this broker and stays on it.";

  static String m330(n) => "links: ${n}";

  static String m331(n, links) => "Links that restart (${n}): ${links}";

  static String m332(link) => "Open ${link}";

  static String m333(link) => "${link} · before a restore from a backup";

  static String m334(link, version) => "${link} · ${version} · before update";

  static String m335(version, links) =>
      "These links stop and start on ${version}: ${links}. The broker puts their private data back to the restore point of the update when the update changed the store format or did not end well; after an update that ended well they keep the data they have. After it no version is kept: there is no second rollback.";

  static String m336(package, version) => "Roll back ${package} to ${version}?";

  static String m337(version) => "Roll back to ${version}…";

  static String m338(version) => "Rolled back to ${version}";

  static String m339(version) => "The links run ${version}";

  static String m340(links) => "${links}: back with all their nodes.";

  static String m341(state) =>
      "It changes the store format (from state ${state})";

  static String m342(state) => "Store format: same (state ${state})";

  static String m343(back, gone) =>
      "declared again: ${back} · not back yet or gone: ${gone}";

  static String m344(n) => "Custom package · links that run it: ${n}";

  static String m345(n) =>
      "Package of the repository · links that run it: ${n}";

  static String m346(package, from, to) => "Update ${package} ${from} → ${to}";

  static String m347(package, from) => "Update ${package} ${from} from a file";

  static String m348(package) => "${package} updated";

  static String m349(package) => "${package} update rolled back";

  static String m350(package) => "Updating ${package}";

  static String m351(package) => "Versions of ${package}";

  static String m352(version) => "What is new in ${version}";

  static String m353(v) => "Version ${v} · deployed";

  static String m354(site) => "via ${site}";

  static String m355(delimiter, header) =>
      "Read as the block reads it: delimiter ${delimiter}, ${header}";

  static String m356(keys) => "${keys} saves · Esc cancels";

  static String m357(keys) => "${keys} saves · Esc discards the changes";

  static String m358(n, who) => "${n} waiting to be let in: ${who}";

  static String m359(value) => "was ${value}";

  static String m360(n) => "Watch groups · ${n}";

  static String m361(user) => "Welcome, ${user}";

  static String m362(value) => "would run on ${value}";

  static String m363(value) => "would send ${value}";

  static String m364(value) => "would write ${value}";

  static String m365(level) => "Turning this on needs ${level} level";

  static String m366(site) => "wyrmd on ${site}";

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
    "approveCount": m7,
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Approve makes it an external link with its own branch and a link token; copy the token to the device. The router reloads for about a second. Reject refuses this CN from now on.",
    ),
    "approveNone": MessageLookupByLibrary.simpleMessage(
      "Tick at least one step.",
    ),
    "approveOtherSite": m8,
    "approveReasonNote": MessageLookupByLibrary.simpleMessage(
      "Approving in Studio comes with its next step. Approve with wyrm-agent for now.",
    ),
    "approveRefused": m9,
    "approveRefusedHint": MessageLookupByLibrary.simpleMessage(
      "Untick the step it names and approve the rest. When the plan is done, ask for the steps left out as a follow-up: they are approved then.",
    ),
    "approveSigns": m10,
    "askAdminFor": m11,
    "askAdminReason": MessageLookupByLibrary.simpleMessage(
      "The broker has no call to send a request to an admin yet.",
    ),
    "askButton": MessageLookupByLibrary.simpleMessage("Ask"),
    "askHint": MessageLookupByLibrary.simpleMessage(
      "Ask for a change, or a question about the network (Cmd+Enter)",
    ),
    "asksToJoin": MessageLookupByLibrary.simpleMessage("asks to join"),
    "asksToJoinRelays": m12,
    "asksToRelay": m13,
    "auditDone": MessageLookupByLibrary.simpleMessage("done"),
    "auditNeeds": MessageLookupByLibrary.simpleMessage(
      "The audit needs config on sys/audit.",
    ),
    "auditRefused": m14,
    "back": MessageLookupByLibrary.simpleMessage("Back"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("Back to Links"),
    "backupPassphrase": MessageLookupByLibrary.simpleMessage(
      "Passphrase of the backup",
    ),
    "backupPassphraseNote": MessageLookupByLibrary.simpleMessage(
      "Only for a backup sealed with one. One sealed for its site needs none and opens only on a broker with that site\'s keys. Studio never stores it.",
    ),
    "backupReplaces": m15,
    "backupRightsAsk": MessageLookupByLibrary.simpleMessage(
      "the broker asks if needed",
    ),
    "backupRightsNote": MessageLookupByLibrary.simpleMessage(
      "Needed when the link has grants or a network allowlist: without it the broker lists them and installs nothing. Its token, certificate and requester key are new.",
    ),
    "bakAbout": m16,
    "bakAll": MessageLookupByLibrary.simpleMessage("All"),
    "bakBackUp": MessageLookupByLibrary.simpleMessage("Back up…"),
    "bakCancelDownload": MessageLookupByLibrary.simpleMessage(
      "Cancel the download",
    ),
    "bakCard": MessageLookupByLibrary.simpleMessage("Backups"),
    "bakCardEmpty": MessageLookupByLibrary.simpleMessage(
      "No backup is kept on the broker.",
    ),
    "bakCardNote": m17,
    "bakCardOld": MessageLookupByLibrary.simpleMessage(
      "This broker has no backups from Studio (it runs a wyrmd before ADR 0048). Use the commands below.",
    ),
    "bakChooseConnection": MessageLookupByLibrary.simpleMessage(
      "Choose a link and a connection",
    ),
    "bakChooseFolder": m18,
    "bakConsistent": MessageLookupByLibrary.simpleMessage(
      "Each store is read at one consistent moment, inside its own read transaction; the broker keeps running and writing.",
    ),
    "bakDo": MessageLookupByLibrary.simpleMessage("Back up"),
    "bakDoLink": m19,
    "bakDoneSub": m20,
    "bakDoneTitle": MessageLookupByLibrary.simpleMessage("Backup ready"),
    "bakDownload": MessageLookupByLibrary.simpleMessage("Download…"),
    "bakDownloading": m21,
    "bakFactBy": MessageLookupByLibrary.simpleMessage("Made by"),
    "bakFactContents": MessageLookupByLibrary.simpleMessage("Contents"),
    "bakFactLink": MessageLookupByLibrary.simpleMessage("Link"),
    "bakFactSealed": MessageLookupByLibrary.simpleMessage("Secrets"),
    "bakFactSent": MessageLookupByLibrary.simpleMessage("Sent to"),
    "bakFailed": MessageLookupByLibrary.simpleMessage(
      "The broker did not make the backup",
    ),
    "bakFailedTitle": m22,
    "bakKeysNeedPassphrase": MessageLookupByLibrary.simpleMessage(
      "Give a passphrase of at least 12 characters below: the keys are sealed with it.",
    ),
    "bakKeysNeverSent": MessageLookupByLibrary.simpleMessage(
      "A backup with Keys and secrets is never sent: download it at the site\'s own gateway.",
    ),
    "bakKeysWarning": m23,
    "bakKindFull": MessageLookupByLibrary.simpleMessage("broker"),
    "bakKindLink": m24,
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
    "bakPassphraseShort": m25,
    "bakProgressSub": MessageLookupByLibrary.simpleMessage(
      "You can close this; the broker finishes it and keeps it under Backups.",
    ),
    "bakProgressTitle": m26,
    "bakRemoveNote": MessageLookupByLibrary.simpleMessage(
      "The file is deleted from the broker. A copy you downloaded or sent stays.",
    ),
    "bakRemoveRow": MessageLookupByLibrary.simpleMessage(
      "Remove it from the broker",
    ),
    "bakRemoveTitle": m27,
    "bakRestore": MessageLookupByLibrary.simpleMessage("Restore…"),
    "bakRowFailed": MessageLookupByLibrary.simpleMessage("failed"),
    "bakRowRunning": m28,
    "bakRowSending": m29,
    "bakSaved": m30,
    "bakSavedNote": m31,
    "bakSavedTo": m32,
    "bakSealedBroker": m33,
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
    "bakSendFailed": m34,
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
    "bakSending": m35,
    "bakSensitive": MessageLookupByLibrary.simpleMessage(
      "A backup is as sensitive as the broker\'s data directory: keep it where only administrators reach it.",
    ),
    "bakShow": MessageLookupByLibrary.simpleMessage("Show in Backups"),
    "bakSub": MessageLookupByLibrary.simpleMessage(
      "Pick what goes in. One .wyrm-backup file (a zip with a manifest); the broker keeps running while it is made.",
    ),
    "bakSubLink": m36,
    "bakTagAlways": MessageLookupByLibrary.simpleMessage("always"),
    "bakTagPassphrase": MessageLookupByLibrary.simpleMessage("passphrase"),
    "bakTagSite": MessageLookupByLibrary.simpleMessage("sealed for this site"),
    "bakTitle": m37,
    "bakTitleLink": m38,
    "bakWhatGoesIn": MessageLookupByLibrary.simpleMessage("What goes in"),
    "bakWhere": MessageLookupByLibrary.simpleMessage("Where"),
    "bakWhereBroker": MessageLookupByLibrary.simpleMessage(
      "Keep on the broker",
    ),
    "bakWhereBrokerNote": m39,
    "bakWhereComputer": MessageLookupByLibrary.simpleMessage("This computer"),
    "bakWhereComputerNote": m40,
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
    "blocksCount": m41,
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
    "brokersDevices": m42,
    "builtIn": MessageLookupByLibrary.simpleMessage("built in"),
    "builtInDriver": m43,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Built into wyrmd · nothing to download",
    ),
    "bupBackOn": m44,
    "bupBackOnNote": m45,
    "bupCard": MessageLookupByLibrary.simpleMessage("Broker version"),
    "bupCardAvailable": m46,
    "bupCardCurrent": m47,
    "bupCardRolledBack": m48,
    "bupCardTrial": m49,
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
    "bupCheckSchemaNote": m50,
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
    "bupDoneRestart": m51,
    "bupDoneStaged": m52,
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
    "bupLinksBack": m53,
    "bupLost": m54,
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
    "bupOpenLog": m55,
    "bupPillContainer": MessageLookupByLibrary.simpleMessage("container"),
    "bupPillRestarting": MessageLookupByLibrary.simpleMessage("restarting"),
    "bupReconnecting": MessageLookupByLibrary.simpleMessage("Reconnecting…"),
    "bupRestarting": m56,
    "bupRollBackNote": MessageLookupByLibrary.simpleMessage(
      "The broker restarts on the version before and restores the pre-update backup of its control plane. Changes made after the update are lost.",
    ),
    "bupRollBackTitle": m57,
    "bupRollBackUntil": m58,
    "bupRolledBack": MessageLookupByLibrary.simpleMessage("Update rolled back"),
    "bupRuns": m59,
    "bupRunsNote": m60,
    "bupSeconds": m61,
    "bupShow": MessageLookupByLibrary.simpleMessage("Show…"),
    "bupStep1": MessageLookupByLibrary.simpleMessage(
      "Pre-update backup of the control plane, secrets sealed (kept until the update is confirmed).",
    ),
    "bupStep2": m62,
    "bupStep3": m63,
    "bupStep4": m64,
    "bupStep5": m65,
    "bupSub": MessageLookupByLibrary.simpleMessage(
      "From the release channel of this broker · the broker restarts once",
    ),
    "bupTitle": m66,
    "bupType": m67,
    "bupUpdate": MessageLookupByLibrary.simpleMessage("Update…"),
    "bupUpdated": m68,
    "bupUpdating": m69,
    "bupUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "This screen reconnects by itself.",
    ),
    "caSigned": m70,
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
    "cbNote": m71,
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
    "childCount": m72,
    "childrenNote": MessageLookupByLibrary.simpleMessage(
      "Select a row: a node opens in the tree, a value opens in the inspector.",
    ),
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
    "connectNote": m73,
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
    "dataDir": m74,
    "dataflow": MessageLookupByLibrary.simpleMessage("Dataflow"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Its rights here are cut now and its next connection waits in quarantine. Its sites stay below it.",
    ),
    "deauthorizeTitle": m75,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Decide in Links"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "A link in quarantine is approved or rejected in Links › Quarantine.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("decide in Sites"),
    "deploy": MessageLookupByLibrary.simpleMessage("Deploy"),
    "deployAskMessage": m76,
    "deployAskTitle": MessageLookupByLibrary.simpleMessage("Deploy this flow?"),
    "deployInside": MessageLookupByLibrary.simpleMessage(
      "Go back to the flow to deploy",
    ),
    "deployedByWho": m77,
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
    "doneLeftOutNote": m78,
    "doneNote": MessageLookupByLibrary.simpleMessage(
      "The task is done. Its record keeps the plan and the log.",
    ),
    "doneOnTheDevice": m79,
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
    "editParamsOf": m80,
    "enableUser": MessageLookupByLibrary.simpleMessage("Enable"),
    "errAdviceBroker": m81,
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
    "errAdviceInputField": m82,
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
    "errAdviceRightsRole": m83,
    "errAdviceStudio": MessageLookupByLibrary.simpleMessage(
      "Try it again; restart Studio if it keeps happening.",
    ),
    "errAdviceUnsupported": MessageLookupByLibrary.simpleMessage(
      "This broker or link does not have this call; it may be older than Studio expects.",
    ),
    "errBackToForm": MessageLookupByLibrary.simpleMessage("Back to the form"),
    "errCallOn": m84,
    "errChipStudio": m85,
    "errCopied": MessageLookupByLibrary.simpleMessage("Copied"),
    "errCopyDetails": MessageLookupByLibrary.simpleMessage("Copy details"),
    "errCopyReport": MessageLookupByLibrary.simpleMessage("Copy report"),
    "errDetails": MessageLookupByLibrary.simpleMessage("Details"),
    "errDetailsCopied": MessageLookupByLibrary.simpleMessage(
      "The details are on the clipboard.",
    ),
    "errDoDeploy": m86,
    "errDoInstall": m87,
    "errDoList": m88,
    "errDoLogIn": m89,
    "errDoOpen": m90,
    "errDoRead": m91,
    "errDoRemove": m92,
    "errDoRun": m93,
    "errDoSave": m94,
    "errDoStart": m95,
    "errDoStep": m96,
    "errDoStop": m97,
    "errDoWrite": m98,
    "errDoingDeploy": m99,
    "errDoingInstall": m100,
    "errDoingList": m101,
    "errDoingLogIn": m102,
    "errDoingOpen": m103,
    "errDoingRead": m104,
    "errDoingRemove": m105,
    "errDoingRun": m106,
    "errDoingSave": m107,
    "errDoingStart": m108,
    "errDoingStop": m109,
    "errDoingWrite": m110,
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
    "errNounRun": m111,
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
    "errSilentReach": m112,
    "errSilentStatus": m113,
    "errStatusLine": m114,
    "errThingBroker": MessageLookupByLibrary.simpleMessage("the broker"),
    "errThingThis": MessageLookupByLibrary.simpleMessage("this"),
    "errTimeLocal": m115,
    "errTitleBroker": m116,
    "errTitleBrokerNoSite": m117,
    "errTitleBusy": m118,
    "errTitleGone": m119,
    "errTitleHistory": m120,
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
    "errTitleReach": m121,
    "errTitleReachNoSite": MessageLookupByLibrary.simpleMessage(
      "The broker did not answer",
    ),
    "errTitleRead": m122,
    "errTitleRights": m123,
    "errTitleStream": m124,
    "errTitleStudio": m125,
    "errTitleUnsupported": m126,
    "errTryAgain": MessageLookupByLibrary.simpleMessage("Try again"),
    "errTryAgainIn": m127,
    "errUserRole": m128,
    "errWhatYouCanDo": MessageLookupByLibrary.simpleMessage("What you can do"),
    "errWriteNote": MessageLookupByLibrary.simpleMessage(
      "A write that timed out may still have been applied. Check the value before you send it again.",
    ),
    "eventNone": MessageLookupByLibrary.simpleMessage("not yet"),
    "everySeconds": m129,
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
    "fatalMoveFailed": m130,
    "fatalNote": m131,
    "fatalQuit": MessageLookupByLibrary.simpleMessage("Quit"),
    "fatalTitle": MessageLookupByLibrary.simpleMessage(
      "Studio could not start",
    ),
    "faultBody": MessageLookupByLibrary.simpleMessage(
      "The rest of Studio still works; values and actions elsewhere are not affected.",
    ),
    "faultDrawAgain": MessageLookupByLibrary.simpleMessage("Draw it again"),
    "faultProblem": m132,
    "faultThisPart": MessageLookupByLibrary.simpleMessage("this part"),
    "faultTitle": m133,
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
    "firstSeen": m134,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "The draft does not validate.",
    ),
    "flowBack": MessageLookupByLibrary.simpleMessage("Back"),
    "flowDeployed": m135,
    "flowError": m136,
    "flowName": MessageLookupByLibrary.simpleMessage("Flow id"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.",
    ),
    "flowPropertiesNote2": MessageLookupByLibrary.simpleMessage(
      "A bound field shows the value that comes in; its wire and source light when you point at it. The link icon goes to the source or unbinds.",
    ),
    "flowStopped": m137,
    "flowVersion": m138,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "A deploy needs config on dataflows; the gateway adds your proofs for each target. Viewers can open a flow and only look.",
    ),
    "flowsOn": m139,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Each flow runs in the broker. You edit a draft; nothing changes until you deploy it.",
    ),
    "fmBlocks": m140,
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
    "fmUnpinField": m141,
    "followUpAsk": m142,
    "followUpLeftOut": MessageLookupByLibrary.simpleMessage(
      "Ask for the steps left out",
    ),
    "fromAddress": m143,
    "fromBackup": MessageLookupByLibrary.simpleMessage("From a backup"),
    "fromBackupNote": MessageLookupByLibrary.simpleMessage(
      "A link backup (.wyrm-link) made by Back up… on a link: its settings, private data and package. It comes back under its own id or a new one.",
    ),
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "From the official list",
    ),
    "gateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "gatewayAnswered": m144,
    "gatewayNoAnswer": m145,
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("Gateway URL"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445, or several separated by commas",
    ),
    "gatewayUser": MessageLookupByLibrary.simpleMessage("Gateway user"),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git repository (HTTPS)",
    ),
    "goTo": m146,
    "goToSource": MessageLookupByLibrary.simpleMessage("Go to source"),
    "goUp": MessageLookupByLibrary.simpleMessage("Go up"),
    "grantFor": m147,
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
    "hidePassword": MessageLookupByLibrary.simpleMessage("Hide password"),
    "hideSteps": MessageLookupByLibrary.simpleMessage("Hide steps"),
    "historianKeep": m148,
    "historianSeries": m149,
    "historianSize": m150,
    "historyFooter": MessageLookupByLibrary.simpleMessage(
      "Sync links read the historian\'s change journal, so nothing is lost while a database is down.",
    ),
    "historyOf": m151,
    "historyUnavailable": MessageLookupByLibrary.simpleMessage(
      "history unavailable",
    ),
    "historyUnavailableTip": m152,
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
    "inputsCount": m153,
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
    "installedOn": m154,
    "instancesInFlow": m155,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Not a gateway URL (http:// or https:// and a host)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Issue"),
    "keyCopied": MessageLookupByLibrary.simpleMessage("Key copied"),
    "keysCopied": m156,
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
    "lag": m157,
    "languageName": MessageLookupByLibrary.simpleMessage("English"),
    "lastRead": m158,
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
    "linksAlready": m159,
    "linksCount": m160,
    "linksLocalNote": m161,
    "linksOn": m162,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "Connections with a certificate from this site that no link is set up for. They can read and write nothing until you approve them.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "They run on their own machines and connect with a certificate from this site. You decide what they may reach and whether they may stay; the device itself is updated where it runs.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.",
    ),
    "listAnd": m163,
    "listFailedTip": m164,
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
    "logOf": m165,
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
    "mbInUse": m166,
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
    "mbUpdateTo": m167,
    "mbUsed": m168,
    "mbVersion": m169,
    "menuLanguage": MessageLookupByLibrary.simpleMessage("Language"),
    "menuOther": MessageLookupByLibrary.simpleMessage("Other"),
    "menuSubtitle": m170,
    "menuTheme": MessageLookupByLibrary.simpleMessage("Theme"),
    "messagesPerSecond": MessageLookupByLibrary.simpleMessage(
      "Router messages per second",
    ),
    "metaFailedTip": m171,
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
    "moreBytes": m172,
    "moreLines": m173,
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
    "nSelected": m174,
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
    "needsLevelYouHave": m175,
    "needsLevelYouHaveIt": m176,
    "networkError": MessageLookupByLibrary.simpleMessage("Connection problem"),
    "newCertificate": MessageLookupByLibrary.simpleMessage("new certificate"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("New dataflow"),
    "newTask": MessageLookupByLibrary.simpleMessage("New task"),
    "newValue": MessageLookupByLibrary.simpleMessage("New value"),
    "no": MessageLookupByLibrary.simpleMessage("no"),
    "noActionReason": m177,
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
    "noParamReason": m178,
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
    "noUpstream": m179,
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
    "openItsTreeNote": m180,
    "openNodeInExplorer": m181,
    "openingTree": MessageLookupByLibrary.simpleMessage("Opening the tree"),
    "openingTreeOf": m182,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Operate · runs now",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Runs on the device with your rights and is written to the audit.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("package"),
    "packageNamed": m183,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Package from your repository · SHA-256 checked against the index on download",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("Package URL (HTTPS)"),
    "pairsCount": m184,
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
    "paramCount": m185,
    "paramsJson": m186,
    "paramsNotJson": m187,
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
    "planNeedsStep": m188,
    "planNote": MessageLookupByLibrary.simpleMessage(
      "The plan is in the task\'s record. Studio shows it when the gateway can read documents (docs/studio.md §10 item 11). Read it with wyrm-agent for now.",
    ),
    "planSaved": m189,
    "planSleep": m190,
    "planSteps": m191,
    "planTimeout": m192,
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
    "pointsCount": m193,
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Values update live. Edits are staged in this session; nothing is written to the device until you apply.",
    ),
    "portsCount": m194,
    "preloadBlocks": MessageLookupByLibrary.simpleMessage(
      "Reading the flow blocks",
    ),
    "preloadFlows": MessageLookupByLibrary.simpleMessage("Reading the flows"),
    "preloadLater": m195,
    "preloadLinks": MessageLookupByLibrary.simpleMessage("Reading the links"),
    "preloadSites": MessageLookupByLibrary.simpleMessage("Reading the sites"),
    "preloadTree": m196,
    "previewInvalid": m197,
    "previewTag": MessageLookupByLibrary.simpleMessage("preview"),
    "problems": MessageLookupByLibrary.simpleMessage("Problems"),
    "problemsClear": MessageLookupByLibrary.simpleMessage("Clear all"),
    "problemsClose": MessageLookupByLibrary.simpleMessage("Close problems"),
    "problemsCount": m198,
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
    "qInstalled": m199,
    "qInstalling": m200,
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
    "reachesSites": m201,
    "readAgain": MessageLookupByLibrary.simpleMessage("Read again"),
    "readFailed": MessageLookupByLibrary.simpleMessage("read failed"),
    "readFailedTip": m202,
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
    "refuseNeedsBroker": m203,
    "refuseNoInput": m204,
    "refuseOutput": MessageLookupByLibrary.simpleMessage(
      "Outputs cannot be bound",
    ),
    "refuseSelf": MessageLookupByLibrary.simpleMessage(
      "A block cannot feed itself",
    ),
    "refuseType": m205,
    "reject": MessageLookupByLibrary.simpleMessage("Reject"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "This certificate is refused from now on.",
    ),
    "rejectPlanHint": MessageLookupByLibrary.simpleMessage("Reason"),
    "rejectPlanNote": MessageLookupByLibrary.simpleMessage(
      "The plan is not run. The reason is kept in the task\'s record.",
    ),
    "rejectPlanTitle": MessageLookupByLibrary.simpleMessage("Reject the plan?"),
    "rejectTitle": m206,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Nothing to do from here: it came in with its relay. Deauthorize the relay to cut it off.",
    ),
    "relaysSites": m207,
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
    "removeLinkTitle": m208,
    "removePair": MessageLookupByLibrary.simpleMessage("Remove the last case"),
    "removePort": MessageLookupByLibrary.simpleMessage("Remove the last port"),
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "It stops, its tree is deleted, and its id is retired: it cannot be used again.",
    ),
    "removeUser": MessageLookupByLibrary.simpleMessage("Remove user"),
    "removeUserNote": MessageLookupByLibrary.simpleMessage(
      "They cannot log in again; their sessions end.",
    ),
    "removeUserTitle": m209,
    "requiredField": MessageLookupByLibrary.simpleMessage("Required field"),
    "resultNoValue": MessageLookupByLibrary.simpleMessage("—"),
    "resultNote": MessageLookupByLibrary.simpleMessage(
      "The keys the plan touched, with their values now.",
    ),
    "resultOf": m210,
    "resultTitle": MessageLookupByLibrary.simpleMessage("Result"),
    "returns": m211,
    "review": MessageLookupByLibrary.simpleMessage("Review"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage("Review and apply"),
    "reviewNote": m212,
    "revision": m213,
    "revisionNow": m214,
    "rightsLine": m215,
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Without this the broker installs nothing. Grants change later with Grant access; other values with the link\'s params.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "The package asks for these rights",
    ),
    "roleOnSite": m216,
    "rollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Its parameters become a new revision and the link restarts with them.",
    ),
    "rollBackTo": m217,
    "rowsAdd": MessageLookupByLibrary.simpleMessage("Add a row"),
    "rowsAnswered": m218,
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
    "rstFile": m219,
    "rstFileNote": m220,
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
    "rstLinks": m221,
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
    "rstOtherSite": m222,
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
    "rstReplaceKeys": m223,
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
    "rstRestarting": m224,
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
    "rstTitle": m225,
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
    "rstUploading": m226,
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
    "runNowNote": m227,
    "runOff": MessageLookupByLibrary.simpleMessage("The block is disabled"),
    "runOnStartTitle": MessageLookupByLibrary.simpleMessage(
      "Run on every start?",
    ),
    "runPassed": MessageLookupByLibrary.simpleMessage("all steps passed"),
    "runPassedIn": m228,
    "runPassedLeftOut": m229,
    "runRunning": MessageLookupByLibrary.simpleMessage("running…"),
    "runStopped": m230,
    "runStoppedFirst": MessageLookupByLibrary.simpleMessage(
      "stopped · nothing was changed",
    ),
    "runStopsNote": MessageLookupByLibrary.simpleMessage(
      "stops at the first step that fails",
    ),
    "runTitle": m231,
    "runTitleEnded": m232,
    "runWaiting": MessageLookupByLibrary.simpleMessage("waiting"),
    "running": MessageLookupByLibrary.simpleMessage("Running"),
    "runningNote": MessageLookupByLibrary.simpleMessage(
      "The agent works on it. Cancel stops it; what was done stays done.",
    ),
    "runsOn": m233,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Runs on another device",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Same call from the CLI",
    ),
    "saveAsPlan": MessageLookupByLibrary.simpleMessage("Save as a plan"),
    "savePlanTitle": m234,
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
    "screenOf": m235,
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
    "setLogLevel": m236,
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
    "sitesAround": m237,
    "sitesSubtitle": m238,
    "sizeBytes": m239,
    "sizeChars": m240,
    "sizeColumns": m241,
    "sizeItems": m242,
    "sizeKeys": m243,
    "sizeLines": m244,
    "sizeRows": m245,
    "stage": MessageLookupByLibrary.simpleMessage("Stage"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "Stage puts it into Review and apply with your other edits.",
    ),
    "stagedChanges": m246,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Nothing is written until you apply. Each change runs with your own rights.",
    ),
    "stagedWas": m247,
    "stale": MessageLookupByLibrary.simpleMessage("stale"),
    "standbyAnswersAt": MessageLookupByLibrary.simpleMessage(
      "Its standby answers at",
    ),
    "standbyGateway": MessageLookupByLibrary.simpleMessage("Standby gateway"),
    "standbyIs": m248,
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
    "stepLeftOut": MessageLookupByLibrary.simpleMessage(
      "left out: it will not run",
    ),
    "stepOf": m249,
    "stepReaching": m250,
    "stepReading": MessageLookupByLibrary.simpleMessage(
      "Reading your role and sites",
    ),
    "stepSkippedNeeds": m251,
    "stepWhere": MessageLookupByLibrary.simpleMessage("Where it runs"),
    "stopRecording": MessageLookupByLibrary.simpleMessage("Stop recording"),
    "stoppedAt": m252,
    "stoppedNote": m253,
    "studioAbout": m254,
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio is signed in here",
    ),
    "studioVersion": m255,
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
    "sysAttnAcl": m256,
    "sysAttnAclDetail": m257,
    "sysAttnBehind": m258,
    "sysAttnBehindDetail": m259,
    "sysAttnBehindPlain": MessageLookupByLibrary.simpleMessage(
      "standby_lag is above 0: a takeover now loses records",
    ),
    "sysAttnBroker": m260,
    "sysAttnBrokerPlain": MessageLookupByLibrary.simpleMessage(
      "A downstream broker",
    ),
    "sysAttnBrokerRelays": m261,
    "sysAttnFork": MessageLookupByLibrary.simpleMessage(
      "The standby moved a fork aside",
    ),
    "sysAttnLinkDetail": m262,
    "sysAttnLinkFailed": m263,
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
    "sysAttnQuarantine": m264,
    "sysAttnQuarantineDetail": m265,
    "sysAttnQuarantineSince": m266,
    "sysBackup": MessageLookupByLibrary.simpleMessage("Back up and restore"),
    "sysBackupNote": m267,
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
    "sysBannerForks": m268,
    "sysBannerLag": m269,
    "sysBrokerAll": MessageLookupByLibrary.simpleMessage("broker (all)"),
    "sysBrokerLogLevel": MessageLookupByLibrary.simpleMessage(
      "Broker log level",
    ),
    "sysBytes": MessageLookupByLibrary.simpleMessage("Bytes"),
    "sysClear": m270,
    "sysClearAsk": MessageLookupByLibrary.simpleMessage(
      "Clear these disconnected links?",
    ),
    "sysClearAskBody": m271,
    "sysClearBoard": m272,
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
    "sysCleared": m273,
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
    "sysCopyCommand": m274,
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
    "sysGuideCopied": m275,
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
    "sysLinkSource": m276,
    "sysLogCopied": m277,
    "sysLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Staged in Review and apply; once applied it takes effect at once, no restart, and replaces `RUST_LOG`. Zenoh stays at warn below trace. Values and tokens are never logged below trace. A link\'s own level: Links › the link › Log.",
    ),
    "sysLogNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "The log is read with config on sys.",
    ),
    "sysLogNotSaved": MessageLookupByLibrary.simpleMessage(
      "Cannot save the log",
    ),
    "sysLogSaved": m278,
    "sysLogSummary": m279,
    "sysLogSummaryAround": m280,
    "sysLogSummaryNone": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/get_log` · config",
    ),
    "sysMessages": MessageLookupByLibrary.simpleMessage("Messages"),
    "sysMetaStarted": m281,
    "sysNeedsLook": m282,
    "sysNeedsLookNote": MessageLookupByLibrary.simpleMessage(
      "From the broker\'s own values. Each opens the screen where it is fixed.",
    ),
    "sysNoLines": MessageLookupByLibrary.simpleMessage(
      "No lines at this level.",
    ),
    "sysNoLinesAround": m283,
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
    "sysNoStandbyStep2": m284,
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
    "sysNow": m285,
    "sysOfTotal": m286,
    "sysOpenAuditRecord": MessageLookupByLibrary.simpleMessage(
      "Open the audit record ›",
    ),
    "sysOut": MessageLookupByLibrary.simpleMessage("out"),
    "sysPackages": MessageLookupByLibrary.simpleMessage("Packages"),
    "sysProfileFile": m287,
    "sysProfileName": MessageLookupByLibrary.simpleMessage("Name"),
    "sysProfileNameHint": MessageLookupByLibrary.simpleMessage(
      "<vendor>:<model>",
    ),
    "sysProfilePut": m288,
    "sysProfileRemoved": m289,
    "sysProfiles": MessageLookupByLibrary.simpleMessage("Device profiles"),
    "sysProfilesFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/profiles` › Put Profile, Remove Profile · config",
    ),
    "sysProfilesNote": MessageLookupByLibrary.simpleMessage(
      "Models served as `pub/<vendor>:<model>`: points, units and ranges that links and the assistant inherit.",
    ),
    "sysProfilesUnlisted": m290,
    "sysPulled": MessageLookupByLibrary.simpleMessage("pulled every 1 s"),
    "sysPut": MessageLookupByLibrary.simpleMessage("Put profile"),
    "sysPutProfile": MessageLookupByLibrary.simpleMessage("Put profile…"),
    "sysRecords": MessageLookupByLibrary.simpleMessage("records"),
    "sysRemove": MessageLookupByLibrary.simpleMessage("Remove"),
    "sysRemoveProfile": m291,
    "sysRemoveProfileAsk": m292,
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
    "sysStaleRow": m293,
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
    "sysSubData": m294,
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
    "sysSubLinkFailed": m295,
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
    "sysSubPeer": m296,
    "sysSubSessions": MessageLookupByLibrary.simpleMessage(
      "network sessions; gateway users not counted",
    ),
    "sysSubWaits": m297,
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
    "sysTrafficDescribe": m298,
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
    "tableFiltered": m299,
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
    "tagNeeds": m300,
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("runs now"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("staged"),
    "taskAwaiting": MessageLookupByLibrary.simpleMessage("awaiting approval"),
    "taskAwaitingAnswer": MessageLookupByLibrary.simpleMessage(
      "awaiting your answer",
    ),
    "taskBy": m301,
    "taskDone": MessageLookupByLibrary.simpleMessage("done"),
    "taskFailed": MessageLookupByLibrary.simpleMessage("failed or stopped"),
    "taskFailedAt": m302,
    "taskListNote": m303,
    "taskNoChanges": MessageLookupByLibrary.simpleMessage("nothing changed"),
    "taskPlanning": MessageLookupByLibrary.simpleMessage("planning"),
    "taskRunning": MessageLookupByLibrary.simpleMessage("running"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("this broker"),
    "tlsCertificateOf": m304,
    "toAccept": MessageLookupByLibrary.simpleMessage("to accept"),
    "toastDismiss": MessageLookupByLibrary.simpleMessage("Dismiss"),
    "toastHidesIn": m305,
    "toastNotifications": MessageLookupByLibrary.simpleMessage("Notifications"),
    "toastStays": m306,
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
    "treeOf": m307,
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
    "trendAvg": m308,
    "trendBadRecorded": MessageLookupByLibrary.simpleMessage(
      "bad quality recorded",
    ),
    "trendBucket": m309,
    "trendClearMarker": MessageLookupByLibrary.simpleMessage(
      "Click A again to clear it",
    ),
    "trendDelta": m310,
    "trendDescribe": m311,
    "trendFollowNow": MessageLookupByLibrary.simpleMessage("Follow now"),
    "trendHint": MessageLookupByLibrary.simpleMessage(
      "Hover for values · drag on the chart to zoom · click to set marker A · drag or resize the window below · double-click resets · ← → move the focused handle",
    ),
    "trendHoursMinutes": m312,
    "trendLocked": m313,
    "trendMarker": m314,
    "trendMinMax": m315,
    "trendMinutes": m316,
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
    "trendRawAt": m317,
    "trendResetZoom": MessageLookupByLibrary.simpleMessage("Reset zoom"),
    "trendSeconds": m318,
    "trendSetMarker": MessageLookupByLibrary.simpleMessage(
      "Click to set marker A",
    ),
    "trendShowHide": m319,
    "trendStepDays": m320,
    "trendStepHours": m321,
    "trendStepMinutes": m322,
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
    "unitNumber": m323,
    "unpinField": MessageLookupByLibrary.simpleMessage("Unpin from block"),
    "unreachableAdvice": MessageLookupByLibrary.simpleMessage(
      "The broker may be restarting or this computer is on another network.",
    ),
    "unsubscribeNote": MessageLookupByLibrary.simpleMessage(
      "The point stops being recorded; its rows stay.",
    ),
    "upFor": m324,
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
    "updDo": m325,
    "updFailed": m326,
    "updFailedNote": MessageLookupByLibrary.simpleMessage(
      "The health check ended without an answer from every link.",
    ),
    "updFromFile": MessageLookupByLibrary.simpleMessage("A newer archive"),
    "updFromFileNote": m327,
    "updFromFileRow": MessageLookupByLibrary.simpleMessage("Update from file…"),
    "updGoneTile": MessageLookupByLibrary.simpleMessage("gone"),
    "updHotStart": m328,
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
    "updKeptUntil": m329,
    "updLeave": MessageLookupByLibrary.simpleMessage(
      "You can leave this screen; it goes on.",
    ),
    "updLinksCount": m330,
    "updLinksRestart": m331,
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
    "updOpenLink": m332,
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
    "updPointBeforeRestore": m333,
    "updPointBeforeUpdate": m334,
    "updPoints": MessageLookupByLibrary.simpleMessage("Restore points"),
    "updRights": MessageLookupByLibrary.simpleMessage("Rights and network"),
    "updRightsNote": MessageLookupByLibrary.simpleMessage(
      "If the new version asks for more than the links have, the broker installs nothing and lists them here for you to accept.",
    ),
    "updRollBack": MessageLookupByLibrary.simpleMessage("Roll back"),
    "updRollBackNote": m335,
    "updRollBackTitle": m336,
    "updRollBackTo": m337,
    "updRolledBackNote": MessageLookupByLibrary.simpleMessage(
      "The links run the kept version again.",
    ),
    "updRolledBackTo": m338,
    "updRowChecking": MessageLookupByLibrary.simpleMessage("being checked"),
    "updRuns": m339,
    "updRunsNote": m340,
    "updStateChanges": m341,
    "updStateChangesNote": MessageLookupByLibrary.simpleMessage(
      "The old version cannot read the new store: a rollback restores the store of the restore point.",
    ),
    "updStateCustom": MessageLookupByLibrary.simpleMessage(
      "Store format: the archive says",
    ),
    "updStateCustomNote": MessageLookupByLibrary.simpleMessage(
      "If the archive does not read the installed store format, the broker refuses an update without a restore point.",
    ),
    "updStateSame": m342,
    "updStateSameNote": MessageLookupByLibrary.simpleMessage(
      "The new version reads the store of the installed one.",
    ),
    "updStepNodes": MessageLookupByLibrary.simpleMessage(
      "Health: every link back with its nodes",
    ),
    "updStepNodesCount": m343,
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
    "updSubCustom": m344,
    "updSubOfficial": m345,
    "updTab": MessageLookupByLibrary.simpleMessage("Updates"),
    "updTabNote": MessageLookupByLibrary.simpleMessage(
      "Links whose package has a newer version. Every link of a package is updated together, and the broker keeps what it needs to go back.",
    ),
    "updThen": MessageLookupByLibrary.simpleMessage("Then"),
    "updTitle": m346,
    "updTitleCustom": m347,
    "updTitleDone": m348,
    "updTitleRolledBack": m349,
    "updTogether": MessageLookupByLibrary.simpleMessage("updated together"),
    "updUpdating": m350,
    "updUpdatingButton": MessageLookupByLibrary.simpleMessage("Updating…"),
    "updUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Values of its links pause while each restarts.",
    ),
    "updVersionsOf": m351,
    "updWhatChanges": MessageLookupByLibrary.simpleMessage(
      "What changes for the broker",
    ),
    "updWhatIsNew": m352,
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
    "versionDeployed": m353,
    "viaSite": m354,
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
    "viewerCsvRules": m355,
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
    "viewerSaveHint": m356,
    "viewerTabTable": MessageLookupByLibrary.simpleMessage("As table"),
    "viewerTabText": MessageLookupByLibrary.simpleMessage("Text"),
    "viewerTableHint": m357,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Waiting in quarantine",
    ),
    "waitingToBeLetIn": m358,
    "wasValue": m359,
    "wasWord": MessageLookupByLibrary.simpleMessage("was"),
    "watchGroup": MessageLookupByLibrary.simpleMessage("Watch group"),
    "watchGroups": m360,
    "welcomeUser": m361,
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
    "wouldRun": m362,
    "wouldSend": m363,
    "wouldWrite": m364,
    "writableNeeds": m365,
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
    "wyrmdOn": m366,
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
