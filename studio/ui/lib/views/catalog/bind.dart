import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:genui/genui.dart';

import '../view_placeholder.dart';

/// The last segment of a template path: `/wy/…/<node>/~children`.
const childrenSegment = '~children';

/// The root of the data model where the bridge writes the unit and the
/// decimals of a key's `~meta`: `/~meta/<escaped key>/{unit,decimals}`.
const metaRoot = '~meta';

/// The root where the bridge writes a quality other than good:
/// `/~q/<escaped key>` (`uncertain`, `bad`, `none`).
const qualityRoot = '~q';

/// The name of an action's `confirm` text inside the event Studio
/// intercepts (never sent anywhere).
const confirmEntry = r'$confirm';

/// Whether the action's button was a `danger` one.
const dangerEntry = r'$danger';

/// How many times a [ViewBind] opened its subscriptions since the app
/// started: what a refine turn costs is read from here in tests.
@visibleForTesting
var viewBindSubscriptions = 0;

/// How many times any [ViewBind] built: what one write to the data model
/// costs is read from here in tests.
@visibleForTesting
var viewBindBuilds = 0;

/// The path of a bound property (`{"path": …}`), or null for a literal.
String? pathOf(Object? prop) => switch (prop) {
  {'path': final String p} => p,
  _ => null,
};

/// The WYRM key a data path stands for: the path without its leading `/`
/// and without the `~children` segment of a template instance.
String keyOfDataPath(String path) => path
    .split('/')
    .where((s) => s.isNotEmpty && s != childrenSegment)
    .join('/');

/// The key [prop] reads in [context], or null for a literal and for `$…`
/// names.
String? keyOfProp(DataContext context, Object? prop) {
  final p = pathOf(prop);
  if (p == null || p.split('/').last.startsWith(r'$')) {
    return null;
  }
  return keyOfDataPath(context.resolvePath(DataPath(p)).toString());
}

String _escape(String key) => key.replaceAll('~', '~0').replaceAll('/', '~1');

/// `[unit, decimals, quality]` of the key [prop] reads, as bound
/// properties; three nulls for a literal.
List<Object?> metaOf(DataContext context, Object? prop) {
  final key = keyOfProp(context, prop);
  if (key == null) {
    return const [null, null, null];
  }
  final e = _escape(key);
  return [
    {'path': '/$metaRoot/$e/unit'},
    {'path': '/$metaRoot/$e/decimals'},
    {'path': '/$qualityRoot/$e'},
  ];
}

/// Rebuilds with the values of [props] (each a literal or `{"path": …}`
/// read in [dataContext]). Only this widget rebuilds when one of its paths
/// is written; its subscriptions stay open across a rebuild of the surface
/// while the properties and the context's path are the same.
class ViewBind extends StatefulWidget {
  const ViewBind({
    required this.dataContext,
    required this.props,
    required this.builder,
    this.distinct,
    super.key,
  });

  final DataContext dataContext;
  final List<Object?> props;
  final Widget Function(BuildContext context, List<Object?> values) builder;

  /// When given, a write rebuilds only if this value of the new values
  /// differs from the last one (a container cares for the set of its
  /// children, not for what is written below them).
  final Object? Function(List<Object?> values)? distinct;

  @override
  State<ViewBind> createState() => _ViewBindState();
}

class _ViewBindState extends State<ViewBind> {
  static const _same = DeepCollectionEquality();
  final _subs = <ValueNotifier<Object?>?>[];
  Object? _last;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(ViewBind old) {
    super.didUpdateWidget(old);
    if (old.dataContext.path != widget.dataContext.path ||
        !identical(old.dataContext.dataModel, widget.dataContext.dataModel) ||
        !_same.equals(old.props, widget.props)) {
      _close();
      _open();
    }
  }

  void _open() {
    viewBindSubscriptions++;
    for (final p in widget.props) {
      final path = pathOf(p);
      _subs.add(
        path == null
            ? null
            : (widget.dataContext.subscribe<Object?>(DataPath(path))
                    as ValueNotifier<Object?>
                ..addListener(_changed)),
      );
    }
    _last = widget.distinct?.call(_values);
  }

  void _close() {
    for (final s in _subs) {
      s
        ?..removeListener(_changed)
        ..dispose();
    }
    _subs.clear();
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    if (widget.distinct case final pick?) {
      final now = pick(_values);
      if (_same.equals(now, _last)) {
        return;
      }
      _last = now;
    }
    setState(() {});
  }

  List<Object?> get _values => [
    for (final (i, p) in widget.props.indexed)
      if (_subs[i] case final sub?) sub.value else p,
  ];

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    viewBindBuilds++;
    return widget.builder(context, _values);
  }
}

/// The child [id] of [item], or a placeholder that names its part when the
/// catalog has none (genui itself throws and draws its own Material error
/// box, which would break the style contract).
Widget partOf(CatalogItemContext item, String id, [DataContext? context]) {
  final component = item.getComponent(id);
  if (component == null) {
    return ViewPlaceholder(part: '?', id: id);
  }
  if (item.getCatalogItem(component.type) == null) {
    return ViewPlaceholder(part: component.type, id: id);
  }
  return item.buildChild(id, context);
}

/// The children of a container: a list of ids, or a template
/// (`{path: "/…/~children", componentId}`) with one instance per entry of
/// the map the bridge keeps at the path, each in its own data context.
Widget childrenOf(
  CatalogItemContext item,
  Object? children,
  Widget Function(List<Widget> children) layout,
) {
  switch (children) {
    case final List<Object?> ids:
      return layout([
        for (final id in ids)
          if (id is String) partOf(item, id),
      ]);
    case final String id:
      return layout([partOf(item, id)]);
    case {'path': final String path, 'componentId': final String template}:
      return ViewBind(
        dataContext: item.dataContext,
        props: [
          {'path': path},
        ],
        distinct: (v) => switch (v.first) {
          final Map<Object?, Object?> m => m.keys.toList(),
          _ => null,
        },
        builder: (context, values) => layout([
          if (values.first case final Map<Object?, Object?> instances)
            for (final name in instances.keys)
              KeyedSubtree(
                key: ValueKey(name),
                child: partOf(
                  item,
                  template,
                  item.dataContext.nested(DataPath('$path/$name')),
                ),
              ),
        ]),
      );
    default:
      return layout(const []);
  }
}

/// The context of an action with its paths resolved by Studio's rules
/// (docs/design/specs/genui-views.md §3.1): `$value` is [value], `$key`
/// the key of the data context, `<rel>/$key` the key of `<rel>`, anything
/// else the value at the path.
Object? resolveAction(DataContext context, Object? v, Object? value) {
  switch (v) {
    case {'path': final String p}:
      if (p == r'$value') {
        return value;
      }
      if (p == r'$key') {
        return keyOfDataPath(context.path.toString());
      }
      if (p.endsWith(r'/$key')) {
        return keyOfDataPath(
          context
              .resolvePath(DataPath(p.substring(0, p.length - 5)))
              .toString(),
        );
      }
      return context.getValue<Object?>(DataPath(p));
    case final Map<Object?, Object?> m:
      return {
        for (final e in m.entries)
          '${e.key}': resolveAction(context, e.value, value),
      };
    case final List<Object?> l:
      return [for (final e in l) resolveAction(context, e, value)];
    default:
      return v;
  }
}

/// Sends [action] (`{event: {name, context}}`) of [item] to the surface's
/// action delegate, where Studio takes it. [value] is the control's new
/// value; [confirm] the component's own question, `{name}` replaced by the
/// instance's name.
void fireAction(
  CatalogItemContext item,
  Object? action, {
  Object? value,
  String? confirm,
  bool danger = false,
}) {
  if (action case {'event': {'name': final String name} && final event}) {
    final context = item.dataContext;
    final resolved = resolveAction(context, event['context'], value);
    final instance =
        context.getValue<Object?>(DataPath(r'$name'))?.toString() ??
        keyOfDataPath(context.path.toString()).split('/').last;
    item.dispatchEvent(
      UserActionEvent(
        name: name,
        sourceComponentId: item.id,
        context: {
          if (resolved is Map<String, Object?>) ...resolved,
          confirmEntry: ?confirm?.replaceAll('{name}', instance),
          if (danger) dangerEntry: true,
        },
      ),
    );
  }
}

/// `enabledWhen {path, equals}` as bound properties: `[value, equals]`.
List<Object?> enabledProps(Object? enabledWhen) => switch (enabledWhen) {
  {'path': final String p} && final m => [
    {'path': p},
    m['equals'],
  ],
  _ => const [null, null],
};

/// Whether a part with `enabledWhen` may be used, from [enabledProps]'
/// values: true when the part has none, else when the value is the one
/// named.
bool isEnabled(Object? enabledWhen, Object? value, Object? equals) =>
    enabledWhen == null || value == equals;

/// A bound value as a number: a bool counts as 0 or 1.
double? numberOf(Object? v) => switch (v) {
  final num n => n.toDouble(),
  true => 1,
  false => 0,
  final String s => double.tryParse(s),
  _ => null,
};

/// A bound value as a bool: a number is true when it is not zero.
bool? boolOf(Object? v) => switch (v) {
  final bool b => b,
  final num n => n != 0,
  _ => null,
};
