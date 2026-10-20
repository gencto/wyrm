// Key-space helpers (spec 01).

const String suffixMeta = '~meta';
const String suffixVal = '~val';
const String suffixSet = '~set';
const String suffixAct = '~act';

/// `wy/<site>/down/<link>/<path>/<suffix>`.
String downKey(String site, String link, String path, String suffix) {
  final parts = ['wy', site, 'down', link, if (path.isNotEmpty) path, if (suffix.isNotEmpty) suffix];
  return parts.join('/');
}

/// Prefix compression of `view=keys` (spec 02): `dir/` = push, `''` = pop.
List<String> compressKeys(Iterable<String> keys) {
  final out = <String>[];
  final stack = <String>[];
  for (final k in keys) {
    while (stack.isNotEmpty && !k.startsWith(stack.join())) {
      stack.removeLast();
      out.add('');
    }
    final rel = k.substring(stack.join().length);
    final i = rel.lastIndexOf('/');
    if (i >= 0) {
      final dir = rel.substring(0, i + 1);
      stack.add(dir);
      out.add(dir);
      out.add(rel.substring(i + 1));
    } else {
      out.add(rel);
    }
  }
  for (var i = 0; i < stack.length; i++) {
    out.add('');
  }
  return out;
}

/// Inverse of [compressKeys].
List<String> expandKeys(Iterable<String> items) {
  final out = <String>[];
  final stack = <String>[];
  for (final it in items) {
    if (it.isEmpty) {
      if (stack.isNotEmpty) stack.removeLast();
    } else if (it.endsWith('/')) {
      stack.add(it);
    } else {
      out.add(stack.join() + it);
    }
  }
  return out;
}
