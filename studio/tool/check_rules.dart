// Counts the patterns that `.claude/skills/studio-rules` forbids, per file,
// and compares them with `tool/rules_baseline.json`: a count may only go
// down, and a file that is not in the baseline must have none.
//
//   dart run tool/check_rules.dart           check (CI)
//   dart run tool/check_rules.dart --lower   write the counts that went down
//   dart run tool/check_rules.dart --init    write the baseline from scratch
//
// Run from `studio/`. No dependencies beyond `dart:io`.

import 'dart:convert';
import 'dart:io';

/// One rule: a name, the folders it covers, the folders it leaves out, and
/// how a file is counted.
final class Rule {
  const Rule(this.name, this.roots, this.count, {this.except = const []});

  final String name;
  final List<String> roots;
  final List<String> except;
  final int Function(String text) count;

  bool covers(String path) =>
      roots.any(path.startsWith) && !except.any(path.startsWith);
}

int _matches(String text, RegExp re) => re.allMatches(text).length;

/// Code without line comments, so a rule quoted in a comment is not counted.
String _code(String text) => text
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

final _rules = <Rule>[
  // 1. no `unawaited` around a dispatch
  Rule(
    'unawaited-dispatch',
    ['app/lib/', 'business/lib/', 'ui/lib/'],
    (t) => _matches(_code(t), RegExp(r'unawaited\(\s*(?:\w+\.)?dispatch\w*\(')),
  ),
  // 2. enums, not strings: switch arms and cases on string literals
  Rule('string-case', ['app/lib/', 'business/lib/', 'ui/lib/'], (t) {
    final c = _code(t);
    return _matches(c, RegExp(r"'[^'\n]*'(?:\s*\|\|\s*'[^'\n]*')*\s*=>")) +
        _matches(c, RegExp(r"^\s*case\s+'[^'\n]*'", multiLine: true));
  }, except: ['business/lib/wyrm/decode/']),
  // 3. connectors map, they do not compute: their size
  Rule('connector-lines', [
    'app/lib/connectors/',
  ], (t) => '\n'.allMatches(t).length),
  // 4. no BuildContext in connectors or business
  Rule('context-in-connector', [
    'app/lib/connectors/',
    'app/lib/mappers/',
    'app/lib/common/',
    'business/lib/',
  ], (t) => _matches(_code(t), RegExp(r'\bBuildContext\b'))),
  // 5. text belongs to localization and ui
  Rule('l10n-in-connector', [
    'app/lib/connectors/',
    'app/lib/mappers/',
    'app/lib/common/',
    'business/lib/',
  ], (t) => _matches(_code(t), RegExp(r'\bS\.(?:current|of\()'))),
  // 6. tokens, not numbers
  Rule('number-literal', ['ui/lib/', 'app/lib/'], (t) {
    final c = _code(t);
    return _matches(c, RegExp(r'fontSize:\s*\d')) +
        _matches(c, RegExp(r'EdgeInsets\.\w+\([^)]*\b\d')) +
        _matches(c, RegExp(r'SizedBox\(\s*(?:width|height):\s*\d')) +
        _matches(c, RegExp(r'(?:BorderRadius|Radius)\.circular\(\s*\d')) +
        _matches(c, RegExp(r'\bColor\(0x'));
  }, except: ['ui/lib/theme/']),
  // 7. callbacks have shared types
  Rule(
    'ad-hoc-callback',
    ['app/lib/connectors/', 'app/lib/common/', 'ui/lib/'],
    (t) => _matches(
      _code(t),
      RegExp(r'final\s+[\w<>?, ]+\s+Function\([^)]*\)\??\s+\w+;'),
    ),
    except: ['ui/lib/models/'],
  ),
  // 8. one typed decode boundary
  Rule(
    'untyped-wire',
    ['app/lib/', 'business/lib/'],
    (t) {
      final c = _code(t);
      return _matches(
            c,
            RegExp(r'\bas\s+(?:String|int|double|num|bool|Map|List)\b\??'),
          ) +
          _matches(c, RegExp(r'Map<Object\?,\s*Object\?>')) +
          _matches(c, RegExp(r'\btoDart\(')) +
          // the loose readers of values.dart, outside a decoder
          _matches(
            c,
            RegExp(
              r'(?<![\w.])(?:str|text|integer|number|boolean|strings|time)\(',
            ),
          ) +
          // a wire Value taken apart by hand, outside a decoder
          _matches(
            c,
            RegExp(r'\bV(?:Map|Str|Int|Float|Bool|Array|Bytes|Null)\('),
          );
    },
    except: [
      'business/lib/wyrm/decode/',
      'business/lib/wyrm/mappers/values.dart',
    ],
  ),
  // 9. one intent, one dispatch
  const Rule('multi-dispatch', [
    'app/lib/connectors/',
    'app/lib/pages/',
    'app/lib/dialogs/',
    'app/lib/common/',
  ], _multiDispatch),
];

/// Callback bodies (`(…) { … }` or `(…) async { … }`) with two or more
/// dispatches: one intent is one action (rule 9).
int _multiDispatch(String text) {
  final c = _code(text);
  final open = RegExp(r'\([^(){};]*\)\s*(?:async\s*)?\{');
  final call = RegExp(r'(?<![\w.])(?:\w+\.)?dispatch\w*\(');
  var n = 0;
  for (final m in open.allMatches(c)) {
    var depth = 1;
    var j = m.end;
    while (j < c.length && depth > 0) {
      final ch = c[j];
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
      }
      j++;
    }
    final body = c.substring(m.end, j);
    // only the body's own level: a nested callback is counted by itself
    final own = body.replaceAll(RegExp(r'\{[^{}]*\}'), '');
    if (call.allMatches(own).length >= 2) {
      n++;
    }
  }
  return n;
}

const _baselinePath = 'tool/rules_baseline.json';

Map<String, Map<String, int>> _measure() {
  final out = <String, Map<String, int>>{for (final r in _rules) r.name: {}};
  for (final root in ['app/lib', 'business/lib', 'ui/lib']) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      continue;
    }
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart') ||
          path.endsWith('.g.dart') ||
          path.endsWith('.freezed.dart') ||
          path.endsWith('.gr.dart') ||
          path.contains('/generated/')) {
        continue;
      }
      final text = f.readAsStringSync();
      for (final r in _rules) {
        if (r.covers(path)) {
          final n = r.count(text);
          if (n > 0) {
            out[r.name]![path] = n;
          }
        }
      }
    }
  }
  return out;
}

Map<String, Map<String, int>> _readBaseline() {
  final f = File(_baselinePath);
  if (!f.existsSync()) {
    return {};
  }
  final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      e.key: {
        for (final f in (e.value as Map<String, dynamic>).entries)
          f.key: f.value as int,
      },
  };
}

void _write(Map<String, Map<String, int>> counts) {
  final sorted = {
    for (final r in _rules)
      r.name: Map.fromEntries(
        (counts[r.name] ?? {}).entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      ),
  };
  File(_baselinePath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
  );
}

void main(List<String> args) {
  final now = _measure();
  if (args.contains('--init')) {
    _write(now);
    stdout.writeln('baseline written: $_baselinePath');
    return;
  }
  final base = _readBaseline();
  final over = <String>[];
  final lowered = <String, Map<String, int>>{};
  for (final r in _rules) {
    final b = base[r.name] ?? const {};
    final n = now[r.name]!;
    for (final e in n.entries) {
      final was = b[e.key] ?? 0;
      if (e.value > was) {
        over.add('${r.name}  ${e.key}: ${e.value} (baseline $was)');
      }
    }
    lowered[r.name] = {
      for (final e in b.entries)
        if ((n[e.key] ?? 0) > 0)
          e.key: (n[e.key]! < e.value ? n[e.key]! : e.value),
    };
  }
  if (args.contains('--lower')) {
    if (over.isNotEmpty) {
      stderr.writeln('not lowered: counts above the baseline first');
    } else {
      _write(lowered);
      stdout.writeln('baseline lowered: $_baselinePath');
      return;
    }
  }
  if (over.isEmpty) {
    final total = now.values.fold<int>(
      0,
      (s, m) => s + m.values.fold<int>(0, (a, b) => a + b),
    );
    stdout.writeln('studio rules: no count above the baseline ($total left)');
    return;
  }
  stderr
    ..writeln('studio rules: counts above the baseline')
    ..writeln('(see .claude/skills/studio-rules/SKILL.md)')
    ..writeAll(over.map((o) => '  $o\n'));
  exitCode = 1;
}
