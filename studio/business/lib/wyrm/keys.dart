/// [key] matches [pattern], whose segments may be `*` (one segment) or `**`
/// (any number, none included), as in Zenoh key expressions and grants.
bool keyMatches(String pattern, String key) {
  if (!pattern.contains('*')) {
    return pattern == key;
  }
  final p = pattern.split('/');
  final k = key.split('/');
  bool at(int i, int j) {
    if (i == p.length) {
      return j == k.length;
    }
    if (p[i] == '**') {
      for (var n = j; n <= k.length; n++) {
        if (at(i + 1, n)) {
          return true;
        }
      }
      return false;
    }
    if (j == k.length) {
      return false;
    }
    return (p[i] == '*' || p[i] == k[j]) && at(i + 1, j + 1);
  }

  return at(0, 0);
}

/// The access levels, lowest first.
const levels = ['none', 'list', 'read', 'write', 'config'];

/// The rank of [level] in [levels]; -1 for an unknown one.
int levelRank(String? level) => level == null ? -1 : levels.indexOf(level);
