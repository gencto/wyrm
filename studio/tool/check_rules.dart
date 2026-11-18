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
  Rule('unawaited-dispatch', ['app/lib/', 'business/lib/', 'ui/lib/'], (t) {
    final c = _code(t);
    return _matches(
          c,
          RegExp(r'unawaited\(\s*(?:\w+\.)?dispatch\w*(?:<[^>]*>)?\('),
        ) +
        // `dispatchAll([x])` of one action is `dispatch(x)` with its Future
        // dropped where `discarded_futures` cannot see it (audit of #115)
        _matches(
          c,
          RegExp(r'dispatchAll\w*\(\s*\[(?!\s*(?:for|if)\b)[^\],\[]*\]\s*\)'),
        ) +
        // a list built by `for`/`if` can hold one action just the same
        _matches(c, RegExp(r'dispatchAll\w*\(\s*\[\s*(?:for|if)\b'));
  }),
  // 2. enums, not strings: switch arms and cases on string literals
  Rule('string-case', ['app/lib/', 'business/lib/', 'ui/lib/'], (t) {
    final c = _code(t);
    return _matches(c, RegExp(r"'[^'\n]*'(?:\s*\|\|\s*'[^'\n]*')*\s*=>")) +
        _matches(c, RegExp(r"^\s*case\s+'[^'\n]*'", multiLine: true));
  }, except: ['business/lib/wyrm/decode/']),
  // 2. a closed set carried as text: string ids and records of strings
  // (owner, 2026-11-15: `id: 'git'`, `List<(String, String)>`)
  Rule('string-id', ['app/lib/', 'business/lib/', 'ui/lib/'], (t) {
    final c = _code(t);
    return _matches(c, RegExp(r"\bid:\s*'")) +
        _matches(c, RegExp(r'\((?:\s*String\??\s*,)+\s*String\??\s*,?\s*\)')) +
        // the same pair with named fields (`({String key, String scope})`):
        // a record of two or more strings, every field a String
        _matches(
          c,
          RegExp(
            r'\(\{(?:\s*String\??\s+\w+\s*,)+\s*String\??\s+\w+\s*,?\s*\}\)',
          ),
        );
  }, except: ['business/lib/wyrm/decode/']),
  // 2, 7. a record with named fields used as a type (`({String key, bool
  // reads})`, a `typedef X = ({…})`): an ad-hoc model with no name, no
  // constructor and no place for its rule (audit of #137). Not a named
  // parameter list: that one follows a name (`f({int a})`).
  Rule(
    'record-type',
    ['app/lib/', 'business/lib/', 'ui/lib/'],
    (t) => _matches(
      _code(t),
      RegExp(r'(?<![\w>?\]])\(\{\s*(?:[A-Za-z_][\w<>?, ]*\s+\w+\s*,?\s*)+\}\)'),
    ),
  ),
  // 3. connectors map, they do not compute: their size
  Rule('connector-lines', [
    'app/lib/connectors/',
  ], (t) => '\n'.allMatches(t).length),
  // 4. no BuildContext in connectors or business
  Rule(
    'context-in-connector',
    [
      'app/lib/connectors/',
      'app/lib/mappers/',
      'app/lib/common/',
      'business/lib/',
    ],
    (t) {
      // A connector's own `Widget build(BuildContext context)` is how a
      // connector is a widget, not a context leaking into it (owner decision
      // 2026-11-15): it is not counted.
      final c = _code(t);
      return _matches(c, RegExp(r'\bBuildContext\b')) -
          _matches(c, RegExp(r'\bWidget\s+build\(\s*BuildContext\b'));
    },
  ),
  // 5. text belongs to localization and ui
  Rule('l10n-in-connector', [
    'app/lib/connectors/',
    'app/lib/mappers/',
    'app/lib/common/',
    'business/lib/',
  ], (t) => _matches(_code(t), RegExp(r'\bS\.(?:current|of\()'))),
  // 6. tokens, not numbers
  const Rule(
    'number-literal',
    ['ui/lib/', 'app/lib/'],
    _numberLiteral,
    except: ['ui/lib/theme/'],
  ),
  // 7. callbacks have shared types
  Rule(
    'ad-hoc-callback',
    ['app/lib/', 'ui/lib/'],
    (t) => _matches(
      _code(t),
      RegExp(r'final\s+[\w<>?, ]+\s+Function\([^)]*\)\??\s+\w+;'),
    ),
    except: ['ui/lib/models/'],
  ),
  // 8. one typed decode boundary
  Rule(
    'untyped-wire',
    // `ui/lib` too: a cast moved out of a connector into a widget is the same
    // untyped read (audit of #123)
    ['app/lib/', 'business/lib/', 'ui/lib/'],
    (t) {
      final c = _code(t);
      return _matches(
            c,
            RegExp(r'\bas\s+(?:String|int|double|num|bool|Map|List)\b\??'),
          ) +
          _matches(c, RegExp(r'Map<Object\?,\s*Object\?>')) +
          // a cast written as a pattern (`case final Map<String, Object?> m`)
          // is the same untyped read (audit of #117)
          _matches(c, RegExp(r'\bcase\s+final\s+(?:Map|List)<')) +
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
  // 9. a rebuild is decided: a view-model compares what is drawn. A plain
  // List/Set/Map made in `fromStore` is never equal to the last one (the
  // screen is built on every dispatch in the app); an optional callback is
  // compared as `onX != null`, or a view-model kept as equal holds a
  // callback of a moment that has passed (audit of 2026-11-16)
  const Rule('vm-equality', ['app/lib/', 'ui/lib/'], _vmEquality),
  // 9. a view-model made of the clock is new on every dispatch (and stale
  // between them): the time a screen shows is state (`clock.now`, ticked by
  // `TickClockAction`), not `DateTime.now()` in `fromStore`
  Rule('vm-clock', [
    'app/lib/connectors/',
    'app/lib/mappers/',
  ], (t) => _matches(_code(t), RegExp(r'\bDateTime\.now\('))),
  // 1, 9. a dispatch whose Future is dropped behind a method of its own
  // (`void _start(a) => dispatch(a);`): `unawaited` by another name. A
  // service listener's own callback (an `@override` of a class that
  // implements a `…ServiceListener`) is the edge rule 1 names: a stream
  // listener or a timer does not wait, it dispatches and returns.
  const Rule('dispatch-wrapper', [
    'app/lib/',
    'business/lib/',
    'ui/lib/',
  ], _dispatchWrapper),
  // 9. one dispatch per intent: a cascade of dispatches is several states,
  // each one built (a cascade of one dispatch is one state)
  const Rule('dispatch-cascade', [
    'app/lib/',
    'business/lib/',
    'ui/lib/',
  ], _dispatchCascade),
  // 6. text is set in tokens: a font size, a line height, a letter spacing
  // written as a number (also behind `?:`, and in the argument of
  // `mono`/`boardText`/`wordmark`, whose types refuse it too), and a field
  // or a parameter that carries one as a bare `double`
  const Rule(
    'raw-type',
    ['ui/lib/', 'app/lib/'],
    _rawType,
    except: ['ui/lib/theme/'],
  ),
  // 2, 6. an icon is a case of `AppIcon`: not a file name of the set, not
  // a text field named for an icon, not a Material glyph or an `IconData`
  // of its own, and it is drawn at a size of `IconSizes`/`AppSizes`
  const Rule(
    'icon-id',
    ['app/lib/', 'business/lib/', 'ui/lib/', 'models/lib/'],
    _iconId,
    except: [
      'ui/lib/indicators/app_icon.dart',
      'ui/lib/indicators/app_icon_view.dart',
      // the one drawing made in code: its strands are chosen by `compact`
      // and its stroke is a parameter, so it is no file of the set
      'ui/lib/indicators/biometric_icon.dart',
      // where `IconSize` is made
      'ui/lib/theme/sizes.dart',
    ],
  ),
];

/// The argument list of each call of [head] in [code] (`head` is a regular
/// expression that ends before the `(`).
Iterable<String> _args(String code, String head) sync* {
  for (final m in RegExp('$head\\(').allMatches(code)) {
    var depth = 1;
    var j = m.end;
    while (j < code.length && depth > 0) {
      final ch = code[j];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      }
      j++;
    }
    yield code.substring(m.end, j - 1);
  }
}

/// A number written in the value of the argument: `12`, `1.5`, `-.26`,
/// `dense ? 12 : 13`, `size + 2`, and the same after the line break the
/// formatter puts behind a long name. A token (`FontSizes.sm`) has no
/// digit that stands alone. The value ends at the `,` or the `)` that
/// closes it.
const _numberValue = r'\s*:[^,;{})]*?(?<![\w.])\.?\d';

/// As [_numberValue], but a `0` alone is not a size: `width: none ? 0 : w`
/// folds a box away and `leading > 0` asks a question.
const _sizeValue = r'\s*:[^,;{})]*?(?<![\w.])(?!0(?![\d.]))\.?\d';

/// [args] without what is nested in it: `width: 3, child: Text(…)` keeps
/// `width: 3, child: Text`.
String _ownLevel(String args) {
  var s = args;
  final nested = RegExp(r'\([^()]*\)');
  while (nested.hasMatch(s)) {
    s = s.replaceAll(nested, '');
  }
  return s;
}

/// Sizes, gaps, radii and colours written as numbers (rule 6).
int _numberLiteral(String text) {
  final c = _code(text);
  var n =
      _matches(c, RegExp(r'fontSize:\s*\d')) +
      // `TextStyle.apply`: a size moved by a number is a size of its own
      _matches(c, RegExp(r'\bfontSize(?:Delta|Factor)\s*:\s*-?\.?\d')) +
      _matches(c, RegExp(r'EdgeInsets(?:Directional)?\.\w+\([^)]*\b\d')) +
      // the same in dot shorthand: `padding: const .all(3)`,
      // `.symmetric(horizontal: 6)`, `.only(top: 2)`, `.fromLTRB(…)`. A
      // border's `.all(color: …)` and a radius' `.only(topLeft: …)` are
      // not insets.
      _matches(
        c,
        RegExp(
          r'(?<![\w.)\]])\.(?:all|symmetric|only|fromLTRB|fromSTEB)\('
          r'(?!\s*(?:color|width|style)\s*:)(?![^)]*circular)[^)]*\b\d',
        ),
      ) +
      // a radius, with its class or in dot shorthand (`.circular(10)`)
      _matches(c, RegExp(r'\.(?:circular|elliptical)\(\s*\d')) +
      _matches(c, RegExp(r'\bColor\(0x')) +
      // a size kept as a number of the file's own, then passed on
      // (`static const double _inset = 2;` … `.all(_inset)`)
      _matches(c, RegExp(r'\bconst\s+double\s+\w+\s*=\s*-?\.?\d'));
  // a box sized by a number, whichever constructor and whichever argument
  // comes first: `SizedBox(key: k, width: 13)`, `SizedBox.square(
  // dimension: 20)`, `SizedBox.fromSize(size: Size(200, 30))`
  final sizeOf = RegExp(r'\bSize(?:\.\w+)?\(\s*\d');
  for (final a in _args(c, r'\bSizedBox(?:\.\w+)?')) {
    final own = _ownLevel(a);
    if (RegExp('\\b(?:width|height|dimension)$_sizeValue').hasMatch(own) ||
        (RegExp(r'\bsize\s*:').hasMatch(own) && sizeOf.hasMatch(a))) {
      n++;
    }
  }
  return n;
}

/// Typography written as numbers.
int _rawType(String text) {
  final c = _code(text);
  // these two are text wherever they are written
  var n = _matches(c, RegExp('\\b(?:fontSize|letterSpacing)$_numberValue'));
  // a height and a size are text inside a text style
  final inStyle = RegExp('\\b(?:height|size|tracking)$_numberValue');
  for (final a in _args(
    c,
    r'(?:\bTextStyle|\bStrutStyle|\bmono|\bboardText|\bwordmark)',
  )) {
    n += _matches(a, inStyle);
  }
  // `style.copyWith(height: 1.5)`: a `copyWith` that names a text field
  for (final a in _args(c, r'\.copyWith')) {
    if (RegExp(
      r'\b(?:fontSize|fontWeight|fontFamily|letterSpacing|decoration)\s*:',
    ).hasMatch(a)) {
      n += _matches(a, RegExp('\\bheight$_numberValue'));
    }
  }
  n += _matches(c, RegExp('\\.copyWith\\(\\s*height$_numberValue'));
  // a carrier of a size typed as a bare number
  return n +
      _matches(
        c,
        RegExp(
          r'\bdouble\??\s+(?:fontSize|textSize|lineHeight|letterSpacing|'
          r'tracking)\b',
        ),
      ) +
      // a number made into a token by a cast: the types are closed by
      // their private constructors, and `13.0 as FontSize` opens them
      _matches(c, RegExp(r'\bas\s+(?:FontSize|LineHeight|Tracking)\b'));
}

/// The file names of the icon set (`ui/assets/svg/icons/<name>.svg`).
final Set<String> _iconFiles = () {
  final dir = Directory('ui/assets/svg/icons');
  return {
    if (dir.existsSync())
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.svg'))
          f.path.replaceAll(r'\', '/').split('/').last.replaceAll('.svg', ''),
  };
}();

/// Icons named or sized outside `AppIcon`.
int _iconId(String text) {
  final c = _code(text);
  var n = 0;
  // a file name of the set, as text
  for (final m in RegExp(r"'([a-z0-9_]+)'").allMatches(c)) {
    if (_iconFiles.contains(m.group(1))) {
      n++;
    }
  }
  // a path into the set, built by hand
  n += _matches(c, RegExp(r'assets/svg/icons/'));
  // a drawing of its own, beside the set (`SvgPicture.string`, `.asset`)
  n += _matches(c, RegExp(r'\bSvgPicture\b'));
  // an icon size made of a number by a cast
  n += _matches(c, RegExp(r'\bas\s+IconSize\b'));
  // an icon carried as text
  n += _matches(c, RegExp(r'\bString\??\s+\w*[iI]con(?:Name|Id)?\b'));
  // a Material glyph, an `IconData`, an `Icon` of its own
  n += _matches(c, RegExp(r'(?<![\w.])Icons\.\w'));
  n += _matches(c, RegExp(r'\bIconData\b'));
  n += _matches(c, RegExp(r'(?<![\w.])Icon\('));
  // an icon drawn at a size that is a number
  for (final a in _args(c, r'\bAppIconView')) {
    n += _matches(a, RegExp('\\bsize$_numberValue'));
  }
  return n;
}

/// Each method whose whole body is a dispatch, but a service listener's
/// own callback.
int _dispatchWrapper(String text) {
  // `dispatchSync` gives its status at once: no Future is dropped
  const call = r'(?:\w+\.)?dispatch(?:AndWait\w*|All\w*)?(?:<[^>]*>)?\(';
  const head = r'^[ \t]*(?:[\w<>?,]+[ \t]+)?_?\w+\([^()]*\)\s*';
  final c = _code(text);
  final listener = RegExp(r'implements\s+\w*ServiceListener\b').hasMatch(c);
  var n = 0;
  for (final re in [
    RegExp('$head=>\\s*$call', multiLine: true),
    // the same with a body of one statement: `void f() { dispatch(x); }`
    RegExp('$head\\{\\s*$call[^;]*;\\s*\\}', multiLine: true),
    // a dispatch behind a condition is the whole body all the same:
    // `=> cond ? dispatch(x) : null` and `{ if (cond) dispatch(x); }`
    // (the condition at the body's own level: its parentheses close
    // before the `?`, so a ternary inside an argument is not this)
    RegExp(
      '$head=>[^;{}()]*(?:\\([^()]*\\)[^;{}()]*)*\\?\\s*$call',
      multiLine: true,
    ),
    RegExp(
      '$head\\{\\s*if\\s*\\([^{};]*\\)\\s*\\{?\\s*$call[^;]*;\\s*\\}?\\s*\\}',
      multiLine: true,
    ),
  ]) {
    for (final m in re.allMatches(c)) {
      final before = c.substring(0, m.start).trimRight();
      if (listener && before.endsWith('@override')) {
        continue;
      }
      n++;
    }
  }
  return n;
}

/// Each dispatch of a cascade after the first in the same statement.
int _dispatchCascade(String text) {
  final c = _code(text);
  var n = 0;
  var last = -1;
  for (final m in RegExp(r'\.\.\s*dispatch\w*\(').allMatches(c)) {
    if (last >= 0 && !c.substring(last, m.start).contains(';')) {
      n++;
    }
    last = m.end;
  }
  return n;
}

/// The body of each `class … extends Vm { … }` in [text].
Iterable<String> _vmBodies(String text) sync* {
  for (final m in RegExp(r'class\s+\w+\s+extends\s+Vm\s*\{').allMatches(text)) {
    var depth = 1;
    var j = m.end;
    while (j < text.length && depth > 0) {
      final ch = text[j];
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
      }
      j++;
    }
    yield text.substring(m.end, j);
  }
}

/// In a view-model: each field that is a plain collection, and each
/// optional callback its `equals` does not hold as `name != null`.
int _vmEquality(String text) {
  var n = 0;
  for (final body in _vmBodies(_code(text))) {
    // a plain collection, and a type that compares by identity
    n += _matches(
      body,
      RegExp(
        r'^\s*final\s+(?:List|Set|Map|Iterable|Object|dynamic|Future|Stream|'
        r'Function)\b[^;(]*;',
        multiLine: true,
      ),
    );
    final equals =
        RegExp(r'equals:\s*\[([\s\S]*?)\]').firstMatch(body)?.group(1) ?? '';
    for (final f in RegExp(
      r'^\s*final\s+(?:VoidCallback|ValueChanged<[^;]*>|[\w<>?, ]*'
      r'Function\([^;]*\))\?\s+(\w+);',
      multiLine: true,
    ).allMatches(body)) {
      if (!RegExp('\\b${f.group(1)}\\s*!=\\s*null').hasMatch(equals)) {
        n++;
      }
    }
  }
  return n;
}

/// Samples each rule must count ([bad], at least once) and must not
/// ([good]): a change to a pattern that stops seeing what it is for fails
/// here, not in review.
const _probes = <String, ({String bad, String good})>{
  'record-type': (
    bad: '''
  ({String key, bool reads})? typedChip(String text) => null;
typedef ReadFail = ({ReadFailure what, String reason});
  final List<({int start, int end})> spans;
''',
    good: '''
  TypedChip? typedChip(String text) => null;
  void onTick(int n, {required bool on}) {}
  const TaskRow({required this.key, this.label = ''});
  Future<void> open(Uri gateway, {String? user, String? device}) async {}
''',
  ),
  'vm-equality': (
    bad: '''
class _Vm extends Vm {
  _Vm({required this.rows, this.onTap}) : super(equals: [rows]);
  final List<RowVm> rows;
  final VoidCallback? onTap;
  final Object? extra;
  final Future<int> later;
}
''',
    good: '''
class _Vm extends Vm {
  _Vm({required this.rows, this.onTap})
    : super(equals: [rows, onTap != null]);
  final IList<RowVm> rows;
  final VoidCallback? onTap;
  final ValueChanged<String> onPick;
}
''',
  ),
  'vm-clock': (
    bad: '''
  _Vm fromStore() => _vm(now: DateTime.now());
''',
    good: '''
  _Vm fromStore() => _vm(now: clock.now);
''',
  ),
  'dispatch-wrapper': (
    bad: '''
  void _start(ReduxAction<AppState> action) => dispatch(action);
  void _load(String id) =>
      _store.dispatchAndWait(LoadAction(id));
  void _read(String id) {
    _store.dispatch(ReadAction(id));
  }
  void report(Object e) =>
      fresh(e)
      ? store.dispatch(ReportAction(e))
      : null;
  void _maybe(String id) {
    if (id.isNotEmpty) {
      _store.dispatch(ReadAction(id));
    }
  }
class D implements TasksServiceListener {
  void _load(String id) => _store.dispatch(LoadAction(id));
}
''',
    good: '''
      onShow: () => dispatch(ShowAction()),
      onPick: (k) => dispatchSync(PickAction(k)),
  void _toggle(String id, {required bool on}) => _store.dispatchSync(
    ToggleAction(id, on: on),
  );
class D implements TasksServiceListener {
  @override
  void onTask(String id) => _store.dispatch(ReadAction(id));
}
  Future<void> run() async => await dispatchAndWait(RunAction());
''',
  ),
  'dispatch-cascade': (
    bad: '''
    store
      ..dispatchSync(AAction())
      ..dispatchSync(BAction());
''',
    good: '''
    store.dispatchSync(OneAction());
    final store = AppStore.of(context)
      ..dispatchSync(OpenAction());
    other
      ..dispatchSync(NextAction());
''',
  ),
  'raw-type': (
    bad: '''
  style: mono(size: 12, color: c.text3),
  style: TextStyle(fontSize: dense ? 12 : 13, height: 1.5),
  style: boardText(height: 1.55, tracking: -0.28),
  style: base.copyWith(letterSpacing: .66),
  style: mono(color: c.text1).copyWith(height: 1.1),
  final double fontSize;
''',
    good: '''
  style: mono(size: FontSizes.sm, color: c.text3),
  style: TextStyle(
    fontSize: dense ? FontSizes.sm : FontSizes.md,
    height: LineHeights.body,
  ),
  style: boardText(height: LineHeights.prose, tracking: Trackings.faultTitle),
  style: mono(color: c.text1).copyWith(height: LineHeights.glyph),
  final FontSize fontSize;
  child: SizedBox(height: box.height, width: w2),
  final next = box.copyWith(height: h);
''',
  ),
  'icon-id': (
    bad: '''
  final String icon;
  icon: Icon(Icons.close, size: 18),
  final IconData glyph;
  child: AppIconView(AppIcon.uiClose, size: 16),
  SvgPicture.asset('assets/svg/icons/\$name.svg'),
''',
    good: '''
  final AppIcon icon;
  child: AppIconView(AppIcon.uiClose, size: IconSizes.md, color: c.text3),
  child: AppIconView(icon, size: AppSizes.flowPinIcon),
  child: BiometricIcon(kind: kind),
  await askOne(api, root, 'node_types'),
''',
  ),
};

/// Forms a rule must count one by one (each sample at least once), and
/// forms it must leave alone (each sample not at all): the forms an audit
/// found a rule blind to stay seen.
const _forms = <String, ({List<String> counted, List<String> left})>{
  'number-literal': (
    counted: [
      'padding: const EdgeInsets.all(12),',
      'padding: const EdgeInsetsDirectional.only(start: 12),',
      'padding: const .all(3),',
      'padding: const .symmetric(horizontal: 6, vertical: 2),',
      'margin: const .only(top: 2),',
      'borderRadius: const .all(.circular(10)),',
      'borderRadius: BorderRadius.circular(13),',
      'static const double _inset = 2;',
      'const SizedBox(height: 10),',
      'SizedBox(key: k, width: 13),',
      'SizedBox(width: wide ? 0.5 : w),',
      'SizedBox.square(dimension: 20, child: mark),',
      'SizedBox.fromSize(size: const Size(200, 30), child: field),',
      'SizedBox(\n  height:\n      36,\n  child: row,\n)',
      'style: base.apply(fontSizeDelta: 2),',
      'color: const Color(0xFF1A1110),',
    ],
    left: [
      'padding: Insets.dialog,',
      'border: .all(color: c.line1),',
      'borderRadius: Radii.card,',
      'SizedBox(height: AppSizes.pointsBar, child: Text(n, maxLines: 2)),',
      'SizedBox.square(dimension: AppSizes.stepMark, child: mark),',
      'static const double rowHeight = AppSizes.flowBlockRow;',
      'padding: i == 0 ? EdgeInsets.zero : Insets.factValueNext,',
      'SizedBox(width: toasts.isEmpty ? 0 : ToastStack.width, child: c),',
      'SizedBox(height: lead > 0 ? AppSizes.heroStacked : h, child: c),',
    ],
  ),
  'raw-type': (
    counted: [
      'style: mono(size: 12),',
      'style: TextStyle(\n  height:\n      1.5,\n),',
      'style: boardText(\n  tracking:\n      -0.28,\n),',
      'letterSpacing:\n    0.72,',
      'final size = 13.0 as FontSize;',
      'height: 1.5 as LineHeight,',
      'final t = x as Tracking;',
    ],
    left: [
      'style: mono(size: FontSizes.sm),',
      'style: TextStyle(\n  height:\n      LineHeights.body,\n),',
      'child: Container(height: 40, child: Text(s, style: mono())),',
    ],
  ),
  'icon-id': (
    counted: [
      "SvgPicture.string(_triangle, width: 18, height: 18),",
      'child: AppIconView(icon, size: 16),',
      'child: AppIconView(\n  icon,\n  size:\n      16,\n),',
      'final s = 16.0 as IconSize;',
      'final String iconName;',
    ],
    left: [
      'child: AppIconView(AppIcon.uiCaution, size: IconSizes.lg),',
      'final IconSize size;',
    ],
  ),
};

/// Runs [_probes] and [_forms]; the names of the rules that fail them.
List<String> _failedProbes() => [
  for (final e in _probes.entries)
    for (final r in _rules)
      if (r.name == e.key &&
          (r.count(e.value.bad) == 0 || r.count(e.value.good) != 0))
        r.name,
  for (final e in _forms.entries)
    for (final r in _rules)
      if (r.name == e.key) ...[
        for (final s in e.value.counted)
          if (r.count(s) == 0) '${r.name}: not counted: $s',
        for (final s in e.value.left)
          if (r.count(s) != 0) '${r.name}: counted: $s',
      ],
];

/// Callback bodies with two or more dispatches: one intent is one action
/// (rule 9). A callback is a closure passed as an argument — positional or
/// named, `(…) { … }` or `(…) async { … }` after `(`, `,` or `name:` — not a
/// method body, an `if` or a `switch` block (owner decision 2026-11-15).
int _multiDispatch(String text) {
  final c = _code(text);
  final open = RegExp(r'(?:[(,]|\w\s*:)\s*\([^(){};]*\)\s*(?:async\s*)?\{');
  final call = RegExp(r'(?<![\w.])(?:\w+\.)?dispatch\w*(?:<[^>]*>)?\(');
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
  for (final root in ['app/lib', 'business/lib', 'ui/lib', 'models/lib']) {
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
  final probes = _failedProbes();
  if (probes.isNotEmpty) {
    stderr.writeln('studio rules: probes not counted right: $probes');
    exitCode = 1;
    return;
  }
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
