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

/// Does the agent link [agent] (its full key) read [key]? Under one of its
/// `allowed_prefixes` (full keys or below the site [root]) or the site's
/// `pub`, never its own subtree: as the link's `Policy::may_read`. A key it
/// does not read refuses the whole ask, so the picker does not offer it.
bool agentReads(
  String root,
  String? agent,
  Iterable<String> prefixes,
  String key,
) {
  bool under(String k, String p) => k == p || k.startsWith('$p/');
  if (agent != null && under(key, agent)) {
    return false;
  }
  if (under(key, '$root/pub')) {
    return true;
  }
  return prefixes.any((p) {
    final full = contextKey(root, p);
    return full != null && under(key, full);
  });
}
