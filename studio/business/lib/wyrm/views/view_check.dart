import 'package:models/view_check.dart';

import '../keys.dart';
import 'view_doc.dart';
import 'view_project.dart';

/// The actions Studio runs for a view; any other name is refused.
const viewActions = {'wyrm.set', 'wyrm.invoke', 'wyrm.open'};

/// Checks [doc] before and while it is shown (genui-views.md §4): every part
/// in [catalog] (part name → the JSON schema of its properties) and valid
/// against its schema, every key in [tree] (key → `ok` or the status that
/// refused its meta; a key not in it is not answered yet), read right on
/// each key and write right on each action target by [grants]
/// (`(pattern, level)`).
///
/// A schema is checked strictly: a property the schema does not name is
/// refused, which is how a colour, a font or a pixel size in a document
/// fails (§3.2). genui's own validation lets such properties through
/// (`CatalogItem.dataSchema` forces `additionalProperties: true`).
List<ViewCheck> checkView(
  ViewDoc doc,
  Map<String, Object?> catalog,
  Map<String, String> tree,
  List<(String, String)> grants,
) {
  final out = <ViewCheck>[];
  void bad(String text, {String? part, String? key}) =>
      out.add(ViewCheck(level: 'bad', text: text, part: part, key: key));
  void warn(String text, {String? part, String? key}) =>
      out.add(ViewCheck(level: 'warn', text: text, part: part, key: key));
  void ok(String text) => out.add(ViewCheck(level: 'ok', text: text));

  for (final f in doc.faults) {
    bad(f);
  }
  if (doc.surfaceId == null) {
    bad('The document creates no surface.');
    return out;
  }
  if (doc.catalogId != viewCatalogId) {
    bad('The catalog is `${doc.catalogId}`; Studio draws `$viewCatalogId`.');
  }
  if (doc.theme) {
    warn('`createSurface.theme` is ignored: colours come from the theme.');
  }
  if (!doc.components.containsKey('root')) {
    bad('There is no component `root`.');
    return out;
  }

  final b = bindingsOf(doc);
  var parts = 0;
  for (final MapEntry(key: id, value: c) in doc.components.entries) {
    final type = c['component'];
    if (!b.reached.contains(id)) {
      warn('`$id` is not reached from `root`.', part: id);
      continue;
    }
    final schema = catalog[type];
    if (type is! String || schema is! Map<String, Object?>) {
      warn(
        '`$type` is not in the catalog: a placeholder is drawn.',
        part: id,
      );
      continue;
    }
    final props = {...c}
      ..remove('id')
      ..remove('component');
    final errors = validateStrict(props, schema);
    if (errors.isEmpty) {
      parts++;
    }
    for (final e in errors) {
      bad('$type `$id`: $e', part: id);
    }
    for (final child in _childIds(c)) {
      if (!doc.components.containsKey(child)) {
        bad('`$id` names the child `$child`, which is not defined.', part: id);
      }
    }
  }
  for (final e in b.faults.entries) {
    bad(e.value, part: e.key);
  }
  if (parts > 0) {
    ok('Parts in the catalog and valid: $parts.');
  }

  final read = levelRank('read');
  var readable = 0;
  for (final key in b.read.toList()..sort()) {
    switch (tree[key]) {
      case null:
        break;
      case 'ok':
        if (levelRank(levelOn(key, grants)) < read) {
          bad('You may not read `$key`.', key: key);
        } else {
          readable++;
        }
      case 'not_found':
        bad('`$key` does not exist.', key: key);
      case 'permission_denied':
        bad('You may not read `$key`.', key: key);
      case final status:
        warn('`$key` did not answer ($status).', key: key);
    }
  }
  if (readable > 0) {
    ok('Keys that exist and that you may read: $readable.');
  }

  final write = levelRank('write');
  var writable = 0;
  for (final a in b.actions) {
    if (!viewActions.contains(a.name)) {
      bad('The action `${a.name}` is not one Studio runs.', part: a.part);
      continue;
    }
    final key = a.key;
    if (a.name == 'wyrm.open' || key == null) {
      continue;
    }
    if (levelRank(levelOn(key, grants)) < write) {
      bad(
        '`${a.part}` writes `$key`; you have no write right on it.',
        part: a.part,
        key: key,
      );
    } else {
      writable++;
    }
  }
  for (final t in b.templates) {
    for (final rel in t.targets) {
      final key = rel.isEmpty ? '${t.listKey}/*' : '${t.listKey}/*/$rel';
      if (levelRank(
            levelOn('${t.listKey}/x${rel.isEmpty ? '' : '/$rel'}', grants),
          ) <
          write) {
        bad(
          '`${t.component}` writes `$key`; you have no write right on it.',
          part: t.component,
          key: key,
        );
      } else {
        writable++;
      }
    }
  }
  if (writable > 0) {
    ok('Action targets you may write: $writable.');
  }
  return out;
}

Iterable<String> _childIds(Map<String, Object?> c) sync* {
  for (final name in const ['children', 'child']) {
    switch (c[name]) {
      case final List<Object?> ids:
        yield* ids.whereType<String>();
      case final String id:
        yield id;
      case {'componentId': final String id}:
        yield id;
      default:
    }
  }
}

/// What is wrong with [value] against [schema], a JSON schema of the
/// keywords the catalog uses (`type`, `enum`, `properties`, `required`,
/// `items`, `anyOf`, `oneOf`). An object may carry only the properties its
/// schema names.
List<String> validateStrict(
  Object? value,
  Map<String, Object?> schema, [
  String at = '',
]) {
  final where = at.isEmpty ? '' : '`$at` ';
  for (final any in const ['anyOf', 'oneOf']) {
    if (schema[any] case final List<Object?> options) {
      List<String>? best;
      for (final o in options) {
        final e = validateStrict(value, o! as Map<String, Object?>, at);
        if (e.isEmpty) {
          return const [];
        }
        if (best == null || e.length < best.length) {
          best = e;
        }
      }
      return best ?? const [];
    }
  }
  if (schema['enum'] case final List<Object?> allowed) {
    return allowed.contains(value)
        ? const []
        : ['${where}is `$value`; one of ${allowed.join(', ')} is read.'];
  }
  final type = schema['type'];
  final fits = switch (type) {
    'string' => value is String,
    'number' => value is num,
    'integer' => value is int,
    'boolean' => value is bool,
    'array' => value is List,
    'object' => value is Map,
    _ => true,
  };
  if (!fits) {
    return ['${where}is not a $type.'];
  }
  final out = <String>[];
  if (value is Map<String, Object?>) {
    final props = schema['properties'] as Map<String, Object?>? ?? const {};
    for (final r in schema['required'] as List<Object?>? ?? const []) {
      if (!value.containsKey(r)) {
        out.add('${where}has no `$r`.');
      }
    }
    for (final e in value.entries) {
      final s = props[e.key];
      if (s is Map<String, Object?>) {
        out.addAll(
          validateStrict(e.value, s, at.isEmpty ? e.key : '$at.${e.key}'),
        );
      } else if (schema['additionalProperties'] != true) {
        out.add(
          'the property `${at.isEmpty ? e.key : '$at.${e.key}'}` is not one '
          'a document may set.',
        );
      }
    }
  }
  if (value is List<Object?>) {
    if (schema['items'] case final Map<String, Object?> items) {
      for (var i = 0; i < value.length; i++) {
        out.addAll(validateStrict(value[i], items, '$at[$i]'));
      }
    }
  }
  return out;
}
