// `~meta` (spec 02): node metadata, `{rev, patch}` publications and
// profiles (`pub/<profile>/~meta` with the text key `extends`).

import 'dart:typed_data';

import 'cbor.dart';
import 'tables.dart';
import 'value.dart';

/// Interned code or full text (`is`, `unit`).
sealed class TextOrCode {
  const TextOrCode();

  void encode(CborWriter w);

  static TextOrCode decode(CborReader r) =>
      r.peek() == CborType.text ? TText(r.readText()) : TCode(r.readUint());
}

final class TCode extends TextOrCode {
  final int code;
  const TCode(this.code);
  @override
  void encode(CborWriter w) => w.uint(code);
  @override
  bool operator ==(Object other) => other is TCode && other.code == code;
  @override
  int get hashCode => code;
  @override
  String toString() => isCodes[code] ?? '#$code';
}

final class TText extends TextOrCode {
  final String text;
  const TText(this.text);
  @override
  void encode(CborWriter w) => w.text(text);
  @override
  bool operator ==(Object other) => other is TText && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => text;
}

/// Parameter metadata inside `actions.*.params`.
class ParamMeta {
  TypeCode? ty;
  TextOrCode? unit;
  List<String>? enumValues;
  Value? defaultValue;
  bool? required;

  /// Field label for people (the key stays the `args` name).
  String? display;
  String? description;

  /// Example value shown in an empty field.
  String? placeholder;

  /// `password` (hidden, never echoed), `textarea` or `file` (a binary
  /// parameter from a local file); others are ignored.
  String? editor;

  ParamMeta(
      {this.ty,
      this.unit,
      this.enumValues,
      this.defaultValue,
      this.required,
      this.display,
      this.description,
      this.placeholder,
      this.editor});

  bool get isPassword => editor == 'password';

  bool get isFile => editor == 'file';

  void encode(CborWriter w) {
    final n = [ty, unit, enumValues, defaultValue, required, display, description, placeholder, editor]
        .where((x) => x != null)
        .length;
    w.mapHeader(n);
    if (ty != null) {
      w.uint(1);
      w.uint(ty!.code);
    }
    if (unit != null) {
      w.uint(2);
      unit!.encode(w);
    }
    if (enumValues != null) {
      w.uint(3);
      _encStrings(w, enumValues!);
    }
    // text keys after int keys, by length then bytes: "editor"(6)
    // "default" "display"(7) "required"(8) "description" "placeholder"(11)
    if (editor != null) {
      w.text('editor');
      w.text(editor!);
    }
    if (defaultValue != null) {
      w.text('default');
      defaultValue!.encode(w);
    }
    if (display != null) {
      w.text('display');
      w.text(display!);
    }
    if (required != null) {
      w.text('required');
      w.boolean(required!);
    }
    if (description != null) {
      w.text('description');
      w.text(description!);
    }
    if (placeholder != null) {
      w.text('placeholder');
      w.text(placeholder!);
    }
  }

  static ParamMeta decode(CborReader r) {
    final p = ParamMeta();
    final n = r.readMapLen();
    for (var i = 0; i < n; i++) {
      if (r.peek() == CborType.text) {
        switch (r.readText()) {
          case 'default':
            p.defaultValue = r.readValue();
          case 'required':
            p.required = r.readBool();
          case 'display':
            p.display = r.readText();
          case 'description':
            p.description = r.readText();
          case 'placeholder':
            p.placeholder = r.readText();
          case 'editor':
            p.editor = r.readText();
          default:
            r.skip();
        }
        continue;
      }
      switch (r.readUint()) {
        case 1:
          p.ty = _typeCode(r);
        case 2:
          p.unit = TextOrCode.decode(r);
        case 3:
          p.enumValues = _decStrings(r);
        default:
          r.skip();
      }
    }
    return p;
  }
}

/// Action result kind: a type code, `"stream"` or `"void"`.
sealed class ActionResult {
  const ActionResult();
}

final class ResultType extends ActionResult {
  final TypeCode type;
  const ResultType(this.type);
}

final class ResultStream extends ActionResult {
  const ResultStream();
}

final class ResultVoid extends ActionResult {
  const ResultVoid();
}

class ActionMeta {
  Map<String, ParamMeta> params;
  ActionResult? result;
  bool? stream;
  Perm? level;
  int? timeoutMs;

  /// Name for people (`Add Device`); the key stays a key segment.
  String? display;

  /// Menu: `new` (adds children), `edit` (changes or removes the node),
  /// another name = own submenu, null = top level.
  String? group;

  ActionMeta(
      {Map<String, ParamMeta>? params, this.result, this.stream, this.level, this.timeoutMs, this.display, this.group})
      : params = params ?? {};

  void encode(CborWriter w) {
    // by length then bytes: "group" "level"(5) "params" "result" "stream"(6)
    // "display"(7) "timeout_ms"(10)
    final n = 1 + [result, stream, level, timeoutMs, display, group].where((x) => x != null).length;
    w.mapHeader(n);
    if (group != null) {
      w.text('group');
      w.text(group!);
    }
    if (level != null) {
      w.text('level');
      w.uint(level!.code);
    }
    w.text('params');
    encodeTextMap<ParamMeta>(w, params, (w, p) => p.encode(w));
    final res = result;
    if (res != null) {
      w.text('result');
      switch (res) {
        case ResultType(:final type):
          w.uint(type.code);
        case ResultStream():
          w.text('stream');
        case ResultVoid():
          w.text('void');
      }
    }
    if (stream != null) {
      w.text('stream');
      w.boolean(stream!);
    }
    if (display != null) {
      w.text('display');
      w.text(display!);
    }
    if (timeoutMs != null) {
      w.text('timeout_ms');
      w.uint(timeoutMs!);
    }
  }

  static ActionMeta decode(CborReader r) {
    final a = ActionMeta();
    final n = r.readMapLen();
    for (var i = 0; i < n; i++) {
      switch (r.readText()) {
        case 'params':
          final m = r.readMapLen();
          for (var j = 0; j < m; j++) {
            final k = r.readText();
            a.params[k] = ParamMeta.decode(r);
          }
        case 'result':
          if (r.peek() == CborType.text) {
            a.result = switch (r.readText()) {
              'stream' => const ResultStream(),
              'void' => const ResultVoid(),
              final other => throw CborError('bad action result $other'),
            };
          } else {
            a.result = ResultType(_typeCode(r));
          }
        case 'stream':
          a.stream = r.readBool();
        case 'level':
          final c = r.readUint();
          a.level = Perm.fromCode(c) ?? (throw CborError('bad level $c'));
        case 'timeout_ms':
          a.timeoutMs = r.readUint();
        case 'display':
          a.display = r.readText();
        case 'group':
          a.group = r.readText();
        default:
          r.skip();
      }
    }
    return a;
  }
}

/// Full `~meta`. Every field is optional; an absent field comes from the
/// profile `is`.
class NodeMeta {
  TextOrCode? is_;
  TypeCode? ty;
  TextOrCode? unit;
  List<String>? enumValues;
  Writable? writable;
  Perm? invokable;
  Map<String, Value>? cfg;
  Map<String, Value>? attr;
  Map<String, ActionMeta>? actions;
  List<String>? children;
  int? rev;
  bool? hasChildren;
  String? display;
  bool? hasOverride;
  int? childrenCount;
  int? q;

  /// `view=list`: `attr.history` is not empty (spec 02 0.2.1, key 16).
  bool? hasHistory;

  /// A child without a type (a node, not a value) exists now: the tree draws
  /// a triangle (spec 02 0.2.6, key 17).
  bool? hasNodes;

  NodeMeta({
    this.is_,
    this.ty,
    this.unit,
    this.enumValues,
    this.writable,
    this.invokable,
    this.cfg,
    this.attr,
    this.actions,
    this.children,
    this.rev,
    this.hasChildren,
    this.display,
    this.hasOverride,
    this.childrenCount,
    this.q,
    this.hasHistory,
    this.hasNodes,
  });

  /// Profile name (`wy:number`) or `#<code>` for codes this table lacks.
  String? get profileName => is_?.toString();

  /// Display name: key 12, else `attr.display`.
  String? get displayName => display ?? switch (attr?['display']) { VStr(:final v) => v, _ => null };

  /// A container: it has (or may have) children.
  bool get isContainer =>
      hasChildren ?? (children != null || childrenCount != null || (ty == null && is_ == const TCode(1)));

  bool get isWritable => writable == Writable.write;

  /// Settable by someone: `write`, or `config` (the responder checks the
  /// caller's level).
  bool get isSettable => writable == Writable.write || writable == Writable.config;

  /// The `(key, writer)` pairs that are present, in canonical key order.
  List<(int, void Function(CborWriter))> _fields() => [
        if (is_ != null) (0, is_!.encode),
        if (ty != null) (1, (w) => w.uint(ty!.code)),
        if (unit != null) (2, unit!.encode),
        if (enumValues != null) (3, (w) => _encStrings(w, enumValues!)),
        if (writable != null) (4, (w) => w.uint(writable!.code)),
        if (invokable != null) (5, (w) => w.uint(invokable!.code)),
        if (cfg != null) (6, (w) => VMap(cfg!).encode(w)),
        if (attr != null) (7, (w) => VMap(attr!).encode(w)),
        if (actions != null) (8, (w) => encodeTextMap<ActionMeta>(w, actions!, (w, a) => a.encode(w))),
        if (children != null) (9, (w) => _encStrings(w, children!)),
        if (rev != null) (10, (w) => w.uint(rev!)),
        if (hasChildren != null) (11, (w) => w.boolean(hasChildren!)),
        if (display != null) (12, (w) => w.text(display!)),
        if (hasOverride != null) (13, (w) => w.boolean(hasOverride!)),
        if (childrenCount != null) (14, (w) => w.uint(childrenCount!)),
        if (q != null) (15, (w) => w.uint(q!)),
        if (hasHistory != null) (16, (w) => w.boolean(hasHistory!)),
        if (hasNodes != null) (17, (w) => w.boolean(hasNodes!)),
      ];

  void _encodeEntries(CborWriter w, List<(int, void Function(CborWriter))> fields) {
    for (final (k, f) in fields) {
      w.uint(k);
      f(w);
    }
  }

  void encode(CborWriter w) {
    final f = _fields();
    w.mapHeader(f.length);
    _encodeEntries(w, f);
  }

  /// Read one integer-keyed entry (the key is already consumed).
  void _decodeField(int key, CborReader r) {
    switch (key) {
      case 0:
        is_ = TextOrCode.decode(r);
      case 1:
        ty = _typeCode(r);
      case 2:
        unit = TextOrCode.decode(r);
      case 3:
        enumValues = _decStrings(r);
      case 4:
        final c = r.readUint();
        writable = Writable.fromCode(c) ?? (throw CborError('bad writable $c'));
      case 5:
        final c = r.readUint();
        invokable = Perm.fromCode(c) ?? (throw CborError('bad invokable $c'));
      case 6:
        cfg = _textMap(r);
      case 7:
        attr = _textMap(r);
      case 8:
        final m = r.readMapLen();
        final acts = <String, ActionMeta>{};
        for (var j = 0; j < m; j++) {
          final k = r.readText();
          acts[k] = ActionMeta.decode(r);
        }
        actions = acts;
      case 9:
        children = _decStrings(r);
      case 10:
        rev = r.readUint();
      case 11:
        hasChildren = r.readBool();
      case 12:
        display = r.readText();
      case 13:
        hasOverride = r.readBool();
      case 14:
        childrenCount = r.readUint();
      case 15:
        q = r.readUint();
      case 16:
        hasHistory = r.readBool();
      case 17:
        hasNodes = r.readBool();
      default:
        r.skip();
    }
  }

  static NodeMeta decode(CborReader r) {
    final m = NodeMeta();
    final n = r.readMapLen();
    for (var i = 0; i < n; i++) {
      if (r.peek() == CborType.text) {
        r.skip(); // unknown text key (forward compatibility)
        r.skip();
        continue;
      }
      m._decodeField(r.readUint(), r);
    }
    return m;
  }

  Uint8List toCbor() => encodeCbor(encode);
  static NodeMeta fromCbor(List<int> b) => decodeCbor(b, decode);

  /// `~meta?view=list`: an array of child summaries.
  static List<NodeMeta> decodeList(CborReader r) {
    final n = r.readArrayHeader() ?? (throw CborError('indefinite list'));
    return [for (var i = 0; i < n; i++) decode(r)];
  }

  static void encodeList(CborWriter w, List<NodeMeta> l) {
    w.arrayHeader(l.length);
    for (final m in l) {
      m.encode(w);
    }
  }
}

/// `~meta` publication `{10: rev, "patch": {<key>: <value>}}`.
class MetaPatch {
  final int rev;
  final Map<int, Value> patch;

  MetaPatch(this.rev, this.patch);

  void encode(CborWriter w) {
    w.mapHeader(2);
    w.uint(10);
    w.uint(rev);
    w.text('patch');
    final keys = patch.keys.toList()..sort();
    w.mapHeader(keys.length);
    for (final k in keys) {
      w.uint(k);
      patch[k]!.encode(w);
    }
  }

  static MetaPatch decode(CborReader r) {
    int? rev;
    final patch = <int, Value>{};
    final n = r.readMapLen();
    for (var i = 0; i < n; i++) {
      if (r.peek() == CborType.text) {
        if (r.readText() == 'patch') {
          final m = r.readMapLen();
          for (var j = 0; j < m; j++) {
            final k = r.readUint();
            patch[k] = r.readValue();
          }
        } else {
          r.skip();
        }
      } else if (r.readUint() == 10) {
        rev = r.readUint();
      } else {
        r.skip();
      }
    }
    return MetaPatch(rev ?? (throw CborError('patch without rev')), patch);
  }

  Uint8List toCbor() => encodeCbor(encode);
  static MetaPatch fromCbor(List<int> b) => decodeCbor(b, decode);
}

/// A profile `pub/<name>/~meta`: the fields of `~meta` plus `"extends"`,
/// the parent profile (spec 02 "Успадкування").
class ProfileDef {
  final NodeMeta meta;
  final String? extends_;

  ProfileDef(this.meta, {this.extends_});

  void encode(CborWriter w) {
    // Integer keys first, then the text key (canonical order).
    final f = meta._fields();
    w.mapHeader(f.length + (extends_ != null ? 1 : 0));
    meta._encodeEntries(w, f);
    if (extends_ != null) {
      w.text('extends');
      w.text(extends_!);
    }
  }

  static ProfileDef decode(CborReader r) {
    final m = NodeMeta();
    String? ext;
    final n = r.readMapLen();
    for (var i = 0; i < n; i++) {
      if (r.peek() == CborType.text) {
        if (r.readText() == 'extends') {
          ext = r.readText();
        } else {
          r.skip();
        }
        continue;
      }
      m._decodeField(r.readUint(), r);
    }
    return ProfileDef(m, extends_: ext);
  }

  Uint8List toCbor() => encodeCbor(encode);
  static ProfileDef fromCbor(List<int> b) => decodeCbor(b, decode);
}

TypeCode _typeCode(CborReader r) {
  final c = r.readUint();
  return TypeCode.fromCode(c) ?? (throw CborError('bad type code $c'));
}

void _encStrings(CborWriter w, List<String> a) {
  w.arrayHeader(a.length);
  for (final s in a) {
    w.text(s);
  }
}

List<String> _decStrings(CborReader r) {
  final n = r.readArrayHeader();
  final out = <String>[];
  if (n == null) {
    while (!r.takeBreak()) {
      out.add(r.readText());
    }
  } else {
    for (var i = 0; i < n; i++) {
      out.add(r.readText());
    }
  }
  return out;
}

Map<String, Value> _textMap(CborReader r) => switch (r.readValue()) {
      VMap(:final v) => v,
      _ => throw CborError('expected text-keyed map'),
    };

/// Compressed `view=keys` list (array of text).
List<String> decodeKeyList(CborReader r) => _decStrings(r);
void encodeKeyList(CborWriter w, List<String> keys) => _encStrings(w, keys);
