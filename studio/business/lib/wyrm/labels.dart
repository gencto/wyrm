/// The words Studio shows for the names the broker uses (owner
/// 2026-11-11): an action, a parameter, a column, a value name or an enum
/// choice reads as the meta's `display` when it has one, else its name
/// made readable. The raw name stays reachable where it is shown (a
/// tooltip, a mono line); keys and the tree never change.
///
/// The rule is the broker's own (ADR 0042, `crates/wyrm-core/src/display.rs`):
/// [humanize] derives a name from a key, [sentence] turns a Title Case text
/// into sentence case, [check] says whether a text follows the style. The
/// lists ([words], [units], [names], [phrases]) and the tests
/// (`business/test/labels_test.dart`, the same cases as the Rust tests) keep
/// the two sides equal: change both together.
library;

/// Key tokens that are not written as plain lower-case words: acronyms and
/// names (`WORDS`). A text may use each written form anywhere.
const words = <String, String>{
  'acl': 'ACL',
  'aes': 'AES',
  'ahu': 'AHU',
  'apdu': 'APDU',
  'api': 'API',
  'aws': 'AWS',
  'azure': 'Azure',
  'bacnet': 'BACnet',
  'bbmd': 'BBMD',
  'ca': 'CA',
  'cbor': 'CBOR',
  'cel': 'CEL',
  'cpu': 'CPU',
  'crc': 'CRC',
  'csr': 'CSR',
  'csv': 'CSV',
  'db': 'DB',
  'dns': 'DNS',
  'dql': 'DQL',
  'dsa': 'DSA',
  'fc': 'FC',
  'gzip': 'gzip',
  'hmac': 'HMAC',
  'html': 'HTML',
  'http': 'HTTP',
  'https': 'HTTPS',
  'id': 'ID',
  'ids': 'IDs',
  'io': 'I/O',
  'iot': 'IoT',
  'ip': 'IP',
  'json': 'JSON',
  'jwt': 'JWT',
  'llm': 'LLM',
  'mac': 'MAC',
  'mcp': 'MCP',
  'modbus': 'Modbus',
  'mqtt': 'MQTT',
  'mtls': 'mTLS',
  'oauth': 'OAuth',
  'oid': 'OID',
  'oids': 'OIDs',
  'opcua': 'OPC UA',
  'pdu': 'PDU',
  'pem': 'PEM',
  'pki': 'PKI',
  'plc': 'PLC',
  'qos': 'QoS',
  'rtu': 'RTU',
  's3': 'S3',
  's7': 'S7',
  'sas': 'SAS',
  'sha': 'SHA',
  'slack': 'Slack',
  'snmp': 'SNMP',
  'sparkplug': 'Sparkplug',
  'sql': 'SQL',
  'ssh': 'SSH',
  'ssl': 'SSL',
  'tcp': 'TCP',
  'telegram': 'Telegram',
  'tls': 'TLS',
  'ttl': 'TTL',
  'udp': 'UDP',
  'uri': 'URI',
  'url': 'URL',
  'urls': 'URLs',
  'usb': 'USB',
  'utc': 'UTC',
  'uuid': 'UUID',
  'wasm': 'WASM',
  'wyrm': 'WYRM',
  'xml': 'XML',
  'zenoh': 'Zenoh',
  'zip': 'ZIP',
};

/// A last key token that is a unit, written in brackets (`UNITS`):
/// `timeout_ms` → `Timeout (ms)`.
const units = <String, String>{
  'ms': 'ms',
  'us': 'µs',
  's': 's',
  'hz': 'Hz',
  'kb': 'kB',
  'kib': 'KiB',
  'mb': 'MB',
  'mib': 'MiB',
  'pct': '%',
  'days': 'days',
};

/// Capitalised words a text may hold after its first word besides [words]:
/// names of products and companies (`NAMES`).
const names = <String>{
  'Amazon',
  'Git',
  'Google',
  'Markdown',
  'Microsoft',
  'Prometheus',
  'Siemens',
  'Studio',
  'Unicode',
};

/// Names of several words, kept as written wherever they stand
/// (`PHRASES`): `Use Socket Mode` stays, `Write Mode` does not.
const phrases = <String>[
  'Block Kit',
  'Bot API',
  'Google Drive',
  'IoT Core',
  'IoT Hub',
  'Socket Mode',
];

/// What the key splits at: `_`, `-`, `.` and white space.
final _split = RegExp(r'[_.\-\s]');

/// A letter or a digit of any script.
final _alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);

String _upperFirst(String s) {
  if (s.isEmpty) {
    return s;
  }
  final first = String.fromCharCode(s.runes.first);
  return first.toUpperCase() + s.substring(first.length);
}

/// The name for people of a key: `add_device` → `Add device`, `unit_id` →
/// `Unit ID`, `timeout_ms` → `Timeout (ms)`, `base_url` → `Base URL`.
///
/// Tokens are split at `_`, `-`, `.` and spaces, written in lower case
/// except [words], the first one capitalised; a last token of [units]
/// (after at least one other) goes into brackets. An empty key gives an
/// empty text.
String humanize(String key) {
  final tokens = [
    for (final t in key.split(_split))
      if (t.isNotEmpty) t.toLowerCase(),
  ];
  final unit = tokens.length > 1 ? units[tokens.last] : null;
  if (unit != null) {
    tokens.removeLast();
  }
  final out = StringBuffer();
  for (final (i, t) in tokens.indexed) {
    if (i > 0) {
      out.write(' ');
    }
    out.write(words[t] ?? (i == 0 ? _upperFirst(t) : t));
  }
  if (unit != null) {
    out.write(' ($unit)');
  }
  return out.toString();
}

/// A capitalised plain word (`Device`): one upper-case letter, then only
/// lower-case ones.
bool _capitalised(String word) {
  final chars = [for (final r in word.runes) String.fromCharCode(r)];
  bool upper(String c) => c != c.toLowerCase() && c == c.toUpperCase();
  bool lower(String c) => c != c.toUpperCase() && c == c.toLowerCase();
  return chars.length > 1 && upper(chars.first) && chars.skip(1).every(lower);
}

bool _known(String word) => names.contains(word) || words.values.contains(word);

/// [word] without the punctuation around it.
String _bare(String word) {
  final chars = [for (final r in word.runes) String.fromCharCode(r)];
  var a = 0;
  var b = chars.length;
  while (a < b && !_alnum.hasMatch(chars[a])) {
    a++;
  }
  while (b > a && !_alnum.hasMatch(chars[b - 1])) {
    b--;
  }
  return chars.sublist(a, b).join();
}

int _count(String s, String c) => c.allMatches(s).length;

/// A phrase in sentence case: every capitalised plain word after the first
/// goes to lower case unless it is a name ([words], [names], [phrases]);
/// text in brackets stays (`Add IP Connection` → `Add IP connection`).
String sentence(String text) {
  final ws = text.split(' ');
  // Words that belong to a phrase name stay as written.
  final kept = List.filled(ws.length, false);
  for (final phrase in phrases) {
    final n = phrase.split(' ').length;
    for (var i = 0; i + n <= ws.length; i++) {
      if (ws.sublist(i, i + n).map(_bare).join(' ') == phrase) {
        for (var j = i; j < i + n; j++) {
          kept[j] = true;
        }
      }
    }
  }
  var depth = 0;
  var first = true;
  return [
    for (final (i, w) in ws.indexed)
      () {
        final inside = depth > 0 || w.startsWith('(');
        depth += _count(w, '(');
        depth = (depth - _count(w, ')')).clamp(0, depth);
        final b = _bare(w);
        final wasFirst = first;
        first = first && b.isEmpty;
        if (inside || wasFirst || kept[i] || !_capitalised(b) || _known(b)) {
          return w;
        }
        return w.replaceFirst(b, b.toLowerCase());
      }(),
  ].join(' ');
}

/// Whether [text] follows the style of a `display`: null when it does, else
/// what is wrong.
String? check(String text) {
  String bad(String why) => 'display "$text": $why';
  if (text.isEmpty || text != text.trim()) {
    return bad('empty or with spaces around it');
  }
  if (text.contains('_')) {
    return bad('holds `_` (a key, not a name)');
  }
  if (text.endsWith('.') && !text.endsWith('...')) {
    return bad('ends with a dot');
  }
  final head = String.fromCharCode(text.runes.first);
  if (head != head.toUpperCase() &&
      !words.values.contains(text.split(' ').first)) {
    return bad('starts with a lower-case letter');
  }
  for (final w in text.split(' ').map(_bare)) {
    final form = words[w.toLowerCase()];
    if (form != null && form != w) {
      return bad('writes "$w" in another case than the word list');
    }
  }
  final want = sentence(text);
  if (want != text) {
    return bad('not in sentence case (expected "$want")');
  }
  return null;
}

/// What a human reads for [name]: [display] when it says something, else
/// [humanize]d [name].
String labelOf(String name, {String? display}) =>
    display != null && display.trim().isNotEmpty ? display : humanize(name);

/// Snake_case words of letters only (`a_ab`, `read_back`); a code with
/// digits (`f32_wbswap`, `u16_swapped`) is an id, not words.
final _snake = RegExp(r'^[a-z]+(_[a-z]+)+$');

/// What a human reads for the enum choice [value]: a snake_case word made
/// readable; anything else as it is (an id, a name, a key, a unit like
/// `1m`, a word the broker already wrote for people). The value sent is
/// always [value].
String choiceLabel(String value) =>
    _snake.hasMatch(value) ? humanize(value) : value;

/// The labels of [choices] that differ from the choice itself.
Map<String, String> choiceLabels(Iterable<String> choices) => {
  for (final c in choices)
    if (choiceLabel(c) != c) c: choiceLabel(c),
};
