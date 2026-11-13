import 'dart:convert';

/// The catalog a WYRM view is written against
/// (docs/design/specs/genui-views.md §3).
const viewCatalogId = 'wyrm:views/0.1';

/// The last segment of a template path: `/wy/…/<node>/~children`.
const childrenSegment = '~children';

/// The WYRM key of a data path (`/wy/plant/…` → `wy/plant/…`).
String keyOfPath(String path) =>
    path.startsWith('/') ? path.substring(1) : path;

/// One A2UI document of a view: its messages as genui takes them, and the
/// components they leave (a later message replaces a component of the same
/// id, as the refine turn does).
final class ViewDoc {
  ViewDoc({
    required this.messages,
    required this.components,
    this.surfaceId,
    this.catalogId,
    this.theme = false,
    this.faults = const [],
  });

  /// The messages in order, `version` rewritten to the one genui accepts
  /// and page parameters filled in.
  final List<Map<String, Object?>> messages;

  /// Component id → its last definition (`id`, `component`, properties).
  final Map<String, Map<String, Object?>> components;
  final String? surfaceId;
  final String? catalogId;

  /// `createSurface` carried a `theme` (ignored, §3.2).
  final bool theme;

  /// The lines that are not A2UI messages, as sentences.
  final List<String> faults;

  /// [messages] as JSON text, one line each: what the surface is handed.
  late final List<String> lines = [for (final m in messages) jsonEncode(m)];

  bool get isEmpty => messages.isEmpty;
}

/// Reads [jsonl] (one A2UI message per line), then [refine] on top of it.
/// `{name}` in a path or in an action's context is replaced by
/// `params[name]` (a full key).
ViewDoc parseViewDoc(
  String jsonl, {
  String refine = '',
  Map<String, String> params = const {},
}) {
  final messages = <Map<String, Object?>>[];
  final components = <String, Map<String, Object?>>{};
  final faults = <String>[];
  String? surfaceId;
  String? catalogId;
  var theme = false;
  var n = 0;
  for (final line in [
    ...const LineSplitter().convert(jsonl),
    ...const LineSplitter().convert(refine),
  ]) {
    if (line.trim().isEmpty) {
      continue;
    }
    n++;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (e) {
      faults.add('Line $n is not JSON: ${e.message}');
      continue;
    }
    if (decoded is! Map<String, Object?>) {
      faults.add('Line $n is not an A2UI message.');
      continue;
    }
    final version = decoded['version'];
    if (version is! String || !version.startsWith('v0.9')) {
      faults.add('Line $n has version $version; this renderer reads v0.9.');
      continue;
    }
    final msg =
        _fill({...decoded, 'version': 'v0.9'}, params, false)!
            as Map<String, Object?>;
    if (msg['createSurface'] case final Map<String, Object?> create) {
      if (surfaceId != null) {
        faults.add('Line $n creates a second surface; a view has one.');
        continue;
      }
      surfaceId = create['surfaceId'] as String?;
      catalogId = create['catalogId'] as String?;
      theme = create['theme'] != null;
      // The theme never reaches the renderer (§3.2).
      msg['createSurface'] = {...create}..remove('theme');
    } else if (msg['updateComponents'] case final Map<String, Object?> up) {
      final list = up['components'];
      if (list is! List) {
        faults.add('Line $n has no components.');
        continue;
      }
      for (final c in list) {
        if (c case {'id': final String id}) {
          components[id] = c as Map<String, Object?>;
        } else {
          faults.add('Line $n has a component without an id.');
        }
      }
    } else if (msg.containsKey('updateDataModel')) {
      faults.add('Line $n writes values; a stored view carries none.');
      continue;
    } else if (!msg.containsKey('deleteSurface')) {
      faults.add('Line $n is not an A2UI message.');
      continue;
    }
    messages.add(msg);
  }
  return ViewDoc(
    messages: messages,
    components: components,
    surfaceId: surfaceId,
    catalogId: catalogId,
    theme: theme,
    faults: faults,
  );
}

/// [v] with `{name}` filled in: in every `path`, and in the texts of an
/// action's `context`.
Object? _fill(Object? v, Map<String, String> params, bool inContext) {
  if (params.isEmpty) {
    return v;
  }
  switch (v) {
    case final Map<String, Object?> m:
      return {
        for (final e in m.entries)
          e.key: e.key == 'path' && e.value is String
              ? _fillPath(e.value! as String, params)
              : _fill(e.value, params, inContext || e.key == 'context'),
      };
    case final List<Object?> l:
      return [for (final e in l) _fill(e, params, inContext)];
    case final String s when inContext:
      return _replace(s, params);
    default:
      return v;
  }
}

String _replace(String s, Map<String, String> params) {
  var out = s;
  for (final e in params.entries) {
    out = out.replaceAll('{${e.key}}', e.value);
  }
  return out;
}

String _fillPath(String path, Map<String, String> params) {
  final out = _replace(path, params);
  return out != path && !out.startsWith('/') ? '/$out' : out;
}

/// The template of a container: one instance of [component] per child of
/// [listKey].
final class ViewTemplate {
  const ViewTemplate({
    required this.listKey,
    required this.component,
    required this.rel,
    required this.targets,
  });

  /// The node whose children are listed.
  final String listKey;

  /// The id of the repeated component.
  final String component;

  /// The paths below a child the template reads (`temp`, `sp`).
  final Set<String> rel;

  /// The paths below a child its actions write or invoke (`sp`; empty text
  /// for the child itself).
  final Set<String> targets;

  /// Where the instances live in the data model.
  String get path => '/$listKey/$childrenSegment';
}

/// One action of a document.
final class ViewActionUse {
  const ViewActionUse({required this.part, required this.name, this.key});

  final String part;

  /// `wyrm.set`, `wyrm.invoke`, `wyrm.open`, or anything else (refused).
  final String name;

  /// The key written or invoked, when the document names it outright.
  final String? key;
}

/// What a document reads and writes.
final class ViewBindings {
  const ViewBindings({
    this.keys = const {},
    this.templates = const [],
    this.actions = const [],
    this.faults = const {},
    this.reached = const {},
  });

  /// The keys read outside a template.
  final Set<String> keys;
  final List<ViewTemplate> templates;
  final List<ViewActionUse> actions;

  /// Component id → what is wrong with one of its paths.
  final Map<String, String> faults;

  /// The components reachable from `root`.
  final Set<String> reached;

  /// Every key the document reads, a template counted as its node.
  Set<String> get read => {...keys, for (final t in templates) t.listKey};
}

/// Walks [doc] from `root` and collects its bindings.
ViewBindings bindingsOf(ViewDoc doc) {
  final keys = <String>{};
  final templates = <ViewTemplate>[];
  final actions = <ViewActionUse>[];
  final faults = <String, String>{};
  final reached = <String>{};

  void walk(String id, Set<String>? rel, Set<String>? targets) {
    final c = doc.components[id];
    if (c == null || !reached.add(id)) {
      return;
    }
    final inTemplate = rel != null;

    void path(String p) {
      if (p.startsWith(r'$')) {
        return;
      }
      if (p.split('/').contains(childrenSegment)) {
        faults[id] = '`$childrenSegment` is only read by a container.';
        return;
      }
      if (p.startsWith('/')) {
        keys.add(keyOfPath(p));
      } else if (inTemplate) {
        rel.add(p);
      } else {
        faults[id] = 'The path `$p` is relative outside a template.';
      }
    }

    void scan(Object? v) {
      switch (v) {
        case {'path': final String p}:
          path(p);
        case final Map<String, Object?> m:
          m.values.forEach(scan);
        case final List<Object?> l:
          l.forEach(scan);
        default:
      }
    }

    for (final e in c.entries) {
      switch (e.key) {
        case 'id' || 'component':
          break;
        case 'children' || 'child':
          switch (e.value) {
            case final List<Object?> ids:
              for (final child in ids) {
                if (child is String) {
                  walk(child, rel, targets);
                }
              }
            case final String child:
              walk(child, rel, targets);
            case {'path': final String p, 'componentId': final String t}:
              final parts = keyOfPath(p).split('/');
              if (!p.startsWith('/') ||
                  parts.last != childrenSegment ||
                  parts.indexOf(childrenSegment) != parts.length - 1) {
                faults[id] =
                    'A template path is `/<node key>/$childrenSegment`.';
              } else if (inTemplate) {
                faults[id] = 'A template inside a template is not read.';
              } else {
                final r = <String>{};
                final w = <String>{};
                walk(t, r, w);
                templates.add(
                  ViewTemplate(
                    listKey: parts.sublist(0, parts.length - 1).join('/'),
                    component: t,
                    rel: r,
                    targets: w,
                  ),
                );
              }
            default:
          }
        case 'action':
          if (e.value case {'event': {'name': final String name} && final ev}) {
            final ctx = ev['context'];
            final target = ctx is Map<String, Object?> ? ctx['key'] : null;
            String? key;
            switch (target) {
              case final String k:
                key = k;
              case {'path': final String p}:
                final rest = p == r'$key'
                    ? ''
                    : p.endsWith(r'/$key')
                    ? p.substring(0, p.length - 5)
                    : null;
                if (rest == null) {
                  faults[id] = r'An action key is a text or a `…/$key` path.';
                } else if (rest.startsWith('/')) {
                  key = keyOfPath(rest);
                } else if (inTemplate) {
                  targets!.add(rest);
                } else if (rest.isNotEmpty) {
                  faults[id] = 'The path `$p` is relative outside a template.';
                }
              default:
            }
            actions.add(ViewActionUse(part: id, name: name, key: key));
          } else {
            faults[id] = 'An action is `{event: {name, context}}`.';
          }
        default:
          scan(e.value);
      }
    }
  }

  walk('root', null, null);
  return ViewBindings(
    keys: keys,
    templates: templates,
    actions: actions,
    faults: faults,
    reached: reached,
  );
}
