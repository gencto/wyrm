// The `@` chips of the Assistant's composer: node keys that go with an ask
// as its `context` (ADR 0049 §9).

/// Keys one ask may attach (the agent link's `MAX_CONTEXT`).
const maxContextKeys = 16;

/// The full node key that [text] names on the site [root]
/// (`wy/<site>`): a full key under [root], or one relative to it
/// (`downstream/modbus/plc1`). Null when it is no plain node key of that
/// site: another site, an empty segment, a `~` segment, a wildcard. The
/// agent link refuses such a key too; the picker never offers it.
String? contextKey(String? root, String text) {
  if (root == null) {
    return null;
  }
  final t = text.trim();
  final p = t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  if (p.isEmpty) {
    return null;
  }
  final key = p == 'wy' || p.startsWith('wy/') ? p : '$root/$p';
  if (!key.startsWith('$root/')) {
    return null;
  }
  for (final seg in key.split('/')) {
    if (seg.isEmpty || seg.startsWith('~') || seg.contains(RegExp(r'[*$?#]'))) {
      return null;
    }
  }
  return key;
}
