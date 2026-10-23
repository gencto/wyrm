// The WYRM node explorer: a virtual tree of 30px rows ("Data"), a context
// menu with the node's actions, an action flyout (params, Invoke, status,
// results) and a "Metrics" panel with the selected node's values, configs
// and attributes. Colours and measures: explorer_theme.dart.

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'explorer_theme.dart';
import 'tree.dart' show formatValue, unitSuffix, historyStores, isRecorded, historyReadKey;

part 'history.dart';

/// Tab bar: 40px, `#1d1c1c`, active tab `#2ebed7` with a 2px
/// underline, 12px text with 10px side margins, 10px bar padding.
class WyTabBar extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int>? onSelect;
  final Widget? trailing;
  const WyTabBar({super.key, required this.tabs, this.selected = 0, this.onSelect, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        height: WyStyle.tabBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: WyStyle.tabBar,
          border: Border(top: BorderSide(color: WyStyle.tabBar), bottom: BorderSide(color: WyStyle.line)),
        ),
        child: Row(children: [
          for (var i = 0; i < tabs.length; i++)
            GestureDetector(
              onTap: onSelect == null ? null : () => onSelect!(i),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: i == selected
                    ? const BoxDecoration(border: Border(bottom: BorderSide(color: WyStyle.accent, width: 2)))
                    : null,
                child: Text(tabs[i], style: WyStyle.tab.copyWith(color: i == selected ? WyStyle.accent : WyStyle.text)),
              ),
            ),
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
      );
}

/// The expander: a triangle in a 16px box.
class _Triangle extends CustomPainter {
  final bool? expanded; // null = leaf, nothing drawn
  final Color color;
  _Triangle(this.expanded, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final e = expanded;
    if (e == null) return;
    final p = Path();
    if (e) {
      p
        ..moveTo(6, 6) // M 6 6 H 12 L 9 11 Z
        ..lineTo(12, 6)
        ..lineTo(9, 11);
    } else {
      p
        ..moveTo(6, 6) // M 6 6 V 12 L 11 9 Z
        ..lineTo(6, 12)
        ..lineTo(11, 9);
    }
    p.close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Triangle old) => old.expanded != expanded || old.color != color;
}

/// A value point: a leaf with a type. The tree shows the rest.
bool _isPoint(NodeMeta m) => !m.isContainer && m.ty != null;

class _Row {
  final String key;
  final String name;
  final NodeMeta meta;
  final int depth;
  const _Row(this.key, this.name, this.meta, this.depth);
}

/// Data panel over Metrics panel. [rootKey] is a node key
/// (`wy/edge/downstream`) or a site (`wy/central`), which shows `downstream`, `upstream`,
/// `dataflows`, `storage` and `sys` (spec 01; a site root has no `~meta` to list). A node
/// with `@root` (a peer broker: `downstream/<site>`, `upstream/<site>`) also opens
/// that site's sections, so peer sites appear inside the tree
/// of the connected broker. A site already on the path is not opened
/// again, so the tree has no loop.
class WyExplorer extends StatefulWidget {
  final WyrmApi api;
  final String rootKey;
  const WyExplorer({super.key, required this.api, required this.rootKey});

  @override
  State<WyExplorer> createState() => _WyExplorerState();
}

/// `wy/<site>`: a site root.
bool _isSiteKey(String k) => RegExp(r'^wy/[^/]+$').hasMatch(k);

/// `wy/<site>/downstream`: the links of a site, listed by liveliness.
bool _isLinksRoot(String k) => RegExp(r'^wy/[^/]+/downstream$').hasMatch(k);

/// The site key a peer-broker node refers to (`@root`).
String? _refRoot(NodeMeta m) => switch (m.attr?['root']) {
      VStr(:final v) when _isSiteKey(v) => v,
      _ => null,
    };

class _WyExplorerState extends State<WyExplorer> {
  final _kids = <String, List<Child>>{};
  final _subs = <String, StreamSubscription<ListUpdate>>{};
  final _expanded = <String>{};
  String? _selected;
  String? _error;

  /// Site sections (spec 01 keys, also their names).
  static const _sections = [
    'downstream',
    'dataflows',
    'storage',
    'sys',
    'upstream',
  ];

  /// Site roots: built here, not listed.
  final _sites = <String>{};

  @override
  void initState() {
    super.initState();
    if (_isSiteKey(widget.rootKey)) {
      _site(widget.rootKey);
    } else {
      _watch(widget.rootKey);
    }
  }

  void _site(String key) {
    if (_sites.add(key)) {
      _kids[key] = [
        for (final s in _sections) Child(s, NodeMeta(hasChildren: true)),
      ];
    }
  }

  bool _synthetic(String key) => _sites.contains(key);

  /// Whether a node has children for the tree (not only value points, which
  /// go to Metrics): known after one `children` call per container row.
  final _treeKids = <String, bool>{};
  final _probing = <String>{};

  static bool _treeChild(Child c) => !_isPoint(c.meta) || _refRoot(c.meta) != null;

  /// `null` while not known yet (no triangle until then).
  bool? _expandable(_Row r) {
    if (_synthetic(r.key) || _refRoot(r.meta) != null) return true;
    if (!r.meta.isContainer) return false;
    final listed = _kids[r.key];
    if (listed != null) return listed.any(_treeChild);
    final known = _treeKids[r.key];
    if (known == null && _probing.add(r.key)) {
      widget.api.children(r.key).then(
            (kids) => _treeKids[r.key] = kids.any(_treeChild),
            onError: (Object _) => _treeKids[r.key] = false,
          ).whenComplete(() {
        _probing.remove(r.key);
        if (mounted) setState(() {});
      });
    }
    return known;
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }

  void _watch(String key) {
    if (_subs.containsKey(key)) return;
    _subs[key] = widget.api.list(key).listen((u) {
      setState(() {
        final list = _kids[key] ?? [];
        switch (u) {
          case ListRefreshed(:final children):
            _kids[key] = [...children];
          case ChildAdded(:final child) || ChildChanged(:final child):
            final i = list.indexWhere((c) => c.name == child.name);
            if (i < 0) {
              list.add(child);
            } else {
              list[i] = child;
            }
            _kids[key] = list;
          case ChildRemoved(:final name):
            _kids[key] = list..removeWhere((c) => c.name == name);
          case ChildConnected() || ChildDisconnected():
            break;
        }
      });
    }, onError: (Object e) => setState(() => _error = '$e'));
  }

  void _toggle(String key) => setState(() {
        if (!_expanded.remove(key)) {
          _expanded.add(key);
          if (!_synthetic(key)) _watch(key);
        } else if (!_synthetic(key)) {
          _subs.remove(key)?.cancel();
          _kids.remove(key);
        }
      });

  List<_Row> _rows() {
    final out = <_Row>[];
    // `path`: the sites opened on the way here.
    void walk(String key, int depth, Set<String> path) {
      for (final c in _kids[key] ?? const <Child>[]) {
        // Value points go to the Metrics panel, not the tree.
        if (_isPoint(c.meta)) continue;
        final k = '$key/${c.name}';
        out.add(_Row(k, c.meta.displayName ?? c.name, c.meta, depth));
        if (!_expanded.contains(k)) continue;
        walk(k, depth + 1, path);
        final ref = _refRoot(c.meta);
        if (ref != null && !path.contains(ref)) {
          _site(ref);
          walk(ref, depth + 1, {...path, ref});
        }
      }
    }

    walk(widget.rootKey, 0, {widget.rootKey});
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return DefaultTextStyle(
      style: WyStyle.label,
      child: Container(
        color: WyStyle.panel,
        child: Column(children: [
          Expanded(
            flex: 3,
            child: Column(children: [
              WyTabBar(tabs: const ['Data'], trailing: _menuIcon()),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(_error!, style: WyStyle.label.copyWith(color: Colors.redAccent))),
              Expanded(
                child: ListView.builder(
                  itemExtent: WyStyle.rowHeight,
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _rowWidget(rows[i]),
                ),
              ),
            ]),
          ),
          Container(height: 1, color: WyStyle.line),
          Expanded(
            flex: 2,
            child: WyMetrics(
              key: ValueKey(_selected),
              api: widget.api,
              nodeKey: _selected == null || _synthetic(_selected!) ? null : _selected,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _menuIcon() => const Padding(
        padding: EdgeInsets.only(right: 6),
        child: Icon(Icons.format_list_bulleted, size: 16, color: WyStyle.text),
      );

  Widget _rowWidget(_Row r) {
    final selected = r.key == _selected;
    final fg = selected ? Colors.white : WyStyle.text;
    // A triangle only where the tree has something to show below.
    final isContainer = _expandable(r) ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selected = r.key),
      onDoubleTap: isContainer ? () => _toggle(r.key) : null,
      onSecondaryTapDown: (d) {
        setState(() => _selected = r.key);
        if (_synthetic(r.key)) return;
        WyContextMenu.show(context, d.globalPosition, widget.api, r.key);
      },
      child: Container(
        color: selected ? WyStyle.selected : null,
        padding: EdgeInsets.only(left: WyStyle.treePaddingLeft + WyStyle.treeIndent * r.depth),
        child: Row(children: [
          GestureDetector(
            onTap: isContainer ? () => _toggle(r.key) : null,
            child: SizedBox.square(
              dimension: 16,
              child: CustomPaint(painter: _Triangle(isContainer ? _expanded.contains(r.key) : null, fg)),
            ),
          ),
          const SizedBox(width: 5 + 8), // icon spacer + item spacer
          Flexible(
            child: Text(r.name,
                maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: WyStyle.label.copyWith(color: fg)),
          ),
          if (isRecorded(r.meta)) _HistoryMark(api: widget.api, nodeKey: r.key, color: fg),
        ]),
      ),
    );
  }
}

/// The mark of a recorded point (`attr.history`, ADR 0016): a click opens
/// its history.
class _HistoryMark extends StatelessWidget {
  final WyrmApi api;
  final String nodeKey;
  final Color color;
  const _HistoryMark({required this.api, required this.nodeKey, required this.color});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Recorded: open its history',
        child: GestureDetector(
          key: ValueKey('history-mark:$nodeKey'),
          onTap: () => WyHistory.open(context, api, nodeKey),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.history, size: 14, color: color),
            ),
          ),
        ),
      );
}

/// One action in the menu: its key, meta (`null` = the `@set` pseudo-action)
/// and the name people see.
class _Act {
  final String id;
  final ActionMeta? meta;
  const _Act(this.id, this.meta);

  String get label => meta?.display ?? id;

  /// Opens a form (`@set` always has its `value` field).
  bool get hasParams => meta == null || meta!.params.isNotEmpty;
}

/// A menu row: one action, or a group submenu.
sealed class _Entry {
  const _Entry();
}

final class _ActEntry extends _Entry {
  final _Act act;
  const _ActEntry(this.act);
}

final class _GroupEntry extends _Entry {
  final String label;
  final List<_Act> acts;
  const _GroupEntry(this.label, this.acts);
}

/// Spec 02 groups: `new` first, then the top level, then `edit`; a group
/// with one action shows it inline, a bigger group as a submenu.
List<_Entry> _menuEntries(NodeMeta m) {
  final groups = <String?, List<_Act>>{};
  for (final e in (m.actions ?? const <String, ActionMeta>{}).entries) {
    // Level `none`: not for people (a link handshake).
    if (e.value.level == Perm.none) continue;
    groups.putIfAbsent(e.value.group, () => []).add(_Act(e.key, e.value));
  }
  if (m.isSettable) groups.putIfAbsent(null, () => []).add(const _Act('@set', null));
  for (final g in groups.values) {
    g.sort((a, b) => a.label.compareTo(b.label));
  }
  String title(String g) => switch (g) {
        'new' => 'New',
        'edit' => 'Edit',
        _ => g.isEmpty ? g : g[0].toUpperCase() + g.substring(1),
      };
  final order = [
    'new',
    null,
    ...groups.keys.whereType<String>().where((g) => g != 'new' && g != 'edit').toList()..sort(),
    'edit',
  ];
  final out = <_Entry>[];
  for (final g in order) {
    final acts = groups[g];
    if (acts == null || acts.isEmpty) continue;
    if (g == null || acts.length == 1) {
      out.addAll(acts.map(_ActEntry.new));
    } else {
      out.add(_GroupEntry(title(g), acts));
    }
  }
  return out;
}

/// The node's context menu: its actions by group (`New ▸`, the top level,
/// `Edit ▸`), `@set` for a writable node, a separator, "View History" for
/// a point and "Copy Path".
/// Every action opens its form to the right of its row: its params (if
/// any), Invoke, the status and the result.
abstract final class WyContextMenu {
  static void show(BuildContext context, Offset at, WyrmApi api, String key) {
    final overlay = Overlay.of(context);
    // layers[0]: the backdrop and the menu; then submenus and forms.
    final layers = <OverlayEntry>[];
    // What each layer shows (a group or an action), so hovering the same row
    // again keeps the open form and what was typed into it.
    final shown = <Object>[];
    void closeFrom(int depth) {
      while (layers.length > depth) {
        layers.removeLast().remove();
      }
      if (shown.length > depth - 1 && depth >= 1) shown.length = depth - 1;
    }

    void close() => closeFrom(0);

    void open(int depth, Rect anchor, Object what, Widget child) {
      if (layers.length == depth + 1 && shown.length == depth && shown.last == what) return;
      closeFrom(depth);
      // Up by the menu's border and padding: the next panel's top is level
      // with this menu's, as in DSA UIs (not a few pixels lower).
      final e = OverlayEntry(
          builder: (_) => Positioned(left: anchor.right, top: anchor.top - _menuInset, child: child));
      layers.add(e);
      shown.add(what);
      overlay.insert(e);
    }

    late void Function(int depth, Rect anchor, _Entry entry, NodeMeta node) onEntry;

    Widget panel(int depth, List<_Entry> entries, NodeMeta node, {List<Widget> tail = const []}) => _MenuPanel(
          children: [
            for (final e in entries)
              switch (e) {
                // Every action opens its form (params, if any, and Invoke).
                _ActEntry(:final act) => _MenuItem(
                    label: act.label,
                    submenu: true,
                    onHover: (r) => onEntry(depth + 1, r, e, node),
                    onTap: (r) => onEntry(depth + 1, r, e, node),
                  ),
                _GroupEntry(:final label) => _MenuItem(
                    label: label,
                    submenu: true,
                    onHover: (r) => onEntry(depth + 1, r, e, node),
                    onTap: (r) => onEntry(depth + 1, r, e, node),
                  ),
              },
            ...tail,
          ],
        );

    onEntry = (depth, anchor, entry, node) {
      switch (entry) {
        case _GroupEntry(:final label, :final acts):
          open(depth, anchor, 'group:$label', panel(depth, [for (final a in acts) _ActEntry(a)], node));
        case _ActEntry(:final act):
          open(
            depth,
            anchor,
            'act:${act.id}',
            _ActionFlyout(
              api: api,
              nodeKey: key,
              action: act.id,
              meta: act.meta,
              node: node,
            ),
          );
      }
    };

    final root = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: close, onSecondaryTap: close),
        ),
        Positioned(
          left: at.dx,
          top: at.dy,
          child: FutureBuilder<NodeMeta>(
            future: api.meta(key),
            builder: (context, snap) {
              final m = snap.data;
              if (m == null) {
                return _MenuPanel(children: [
                  _MenuItem(label: snap.hasError ? '${snap.error}' : 'Loading…', disabled: true),
                ]);
              }
              final entries = _menuEntries(m);
              return panel(0, entries, m, tail: [
                if (entries.isEmpty) const _MenuItem(label: 'No actions', disabled: true),
                Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 2), color: WyStyle.line),
                // A point (no children): its recorded values (sys/history).
                if (!m.isContainer)
                  _MenuItem(
                    label: 'View History',
                    onHover: (_) => closeFrom(1),
                    onTap: (_) {
                      close();
                      WyHistory.open(context, api, key);
                    },
                  ),
                _MenuItem(
                  label: 'Copy Path',
                  onHover: (_) => closeFrom(1),
                  onTap: (_) {
                    Clipboard.setData(ClipboardData(text: key));
                    close();
                  },
                ),
              ]);
            },
          ),
        ),
      ]),
    );
    layers.add(root);
    overlay.insert(root);
  }
}

/// Border plus padding of a menu panel, above its first row.
const double _menuInset = 3;

/// The menu box: `#323232`, 1px `#424244`, shadow, 2px padding.
class _MenuPanel extends StatelessWidget {
  final List<Widget> children;
  const _MenuPanel({required this.children});

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 360),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: WyStyle.panel, border: Border.all(color: WyStyle.line), boxShadow: WyStyle.shadow),
          child: IntrinsicWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      );
}

class _MenuItem extends StatefulWidget {
  final String label;
  final bool submenu;
  final bool disabled;
  final void Function(Rect)? onTap;

  /// Called when the pointer enters the row (submenus open on hover).
  final void Function(Rect)? onHover;
  const _MenuItem({required this.label, this.submenu = false, this.disabled = false, this.onTap, this.onHover});

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  Rect _rect() {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final on = _hover && !widget.disabled;
    final color = widget.disabled ? WyStyle.disabled : (on ? Colors.white : WyStyle.text);
    return MouseRegion(
      cursor: widget.disabled ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hover = true);
        if (!widget.disabled) widget.onHover?.call(_rect());
      },
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : () => widget.onTap?.call(_rect()),
        child: Container(
          height: 30,
          color: on ? WyStyle.selected : null,
          padding: const EdgeInsets.only(left: 15, right: 10),
          child: Row(children: [
            // a long label (a store key) ends in an ellipsis
            Expanded(
              child: Text(widget.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: WyStyle.menu.copyWith(color: color)),
            ),
            const SizedBox(width: 10),
            if (widget.submenu)
              SizedBox(
                width: 6,
                height: 8,
                child: CustomPaint(painter: _MenuTriangle(on ? Colors.white : WyStyle.text)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Submenu marker: a 5px right-pointing triangle.
class _MenuTriangle extends CustomPainter {
  final Color color;
  _MenuTriangle(this.color);
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
      Path()
        ..moveTo(1, 1)
        ..lineTo(1, 7)
        ..lineTo(6, 4)
        ..close(),
      Paint()..color = color);
  @override
  bool shouldRepaint(_MenuTriangle old) => old.color != color;
}

/// The action form: one row per param (label column, then the field, all
/// fields on one edge), "Invoke", the status indicator, then the results.
class _ActionFlyout extends StatefulWidget {
  final WyrmApi api;
  final String nodeKey;
  final String action;

  /// `null` for the `@set` pseudo-action (one `value` param of the node type).
  final ActionMeta? meta;
  final NodeMeta node;
  const _ActionFlyout({
    required this.api,
    required this.nodeKey,
    required this.action,
    required this.meta,
    required this.node,
  });

  @override
  State<_ActionFlyout> createState() => _ActionFlyoutState();
}

enum _Status { idle, running, ok, error }

class _ActionFlyoutState extends State<_ActionFlyout> {
  late final Map<String, ParamMeta> _params =
      widget.meta?.params ?? {'value': ParamMeta(ty: widget.node.ty, enumValues: widget.node.enumValues)};
  final _text = <String, TextEditingController>{};
  final _bool = <String, bool>{};
  final _enum = <String, String?>{};

  /// `editor: file` params (spec 02 0.1.7): the chosen file, if any.
  final _files = <String, ({String name, Uint8List bytes})?>{};
  final _results = <Value>[];
  _Status _status = _Status.idle;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final e in _params.entries) {
      final p = e.value;
      final d = p.defaultValue;
      if (p.isFile) {
        _files[e.key] = null;
      } else if (p.ty == TypeCode.bool_) {
        _bool[e.key] = d is VBool && d.v;
      } else if (p.enumValues != null) {
        // A list, also an empty one (nothing to choose: shown, not typed).
        _enum[e.key] = d is VStr ? d.v : p.enumValues!.firstOrNull;
      } else {
        _text[e.key] = TextEditingController(text: d == null || d is VNull ? '' : formatValue(d, null));
      }
    }
  }

  Value _value(String k, ParamMeta p) {
    if (_files.containsKey(k)) return VBytes(_files[k]!.bytes);
    if (_bool.containsKey(k)) return VBool(_bool[k]!);
    if (_enum.containsKey(k)) {
      final s = _enum[k] ?? '';
      // An enum node value is its index; an action param travels as text.
      final i = widget.meta == null ? (p.enumValues ?? const []).indexOf(s) : -1;
      return i >= 0 ? VInt(i) : VStr(s);
    }
    final t = _text[k]!.text.trim();
    if (p.ty == TypeCode.number) {
      return int.tryParse(t) != null ? VInt(int.parse(t)) : VFloat(double.tryParse(t) ?? 0);
    }
    return VStr(t);
  }

  Future<void> _invoke() async {
    setState(() {
      _status = _Status.running;
      _results.clear();
      _error = null;
    });
    try {
      if (widget.meta == null) {
        await widget.api.set(widget.nodeKey, _value('value', _params['value']!));
      } else {
        final args = <String, Value>{};
        for (final e in _params.entries) {
          if (_text.containsKey(e.key) && _text[e.key]!.text.trim().isEmpty) continue;
          if (_files.containsKey(e.key) && _files[e.key] == null) continue;
          if (_enum.containsKey(e.key) && _enum[e.key] == null) continue;
          args[e.key] = _value(e.key, e.value);
        }
        await for (final v in widget.api.invoke(widget.nodeKey, widget.action, VMap(args))) {
          if (!mounted) return;
          setState(() => _results.add(v));
        }
      }
      if (mounted) setState(() => _status = _Status.ok);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.error;
          // the message alone, not `WyrmException(status): …`
          _error = e is WyrmException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: Container(
          width: _formWidth,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 5),
          decoration: BoxDecoration(color: WyStyle.panel, border: Border.all(color: WyStyle.line), boxShadow: WyStyle.shadow),
          child: DefaultTextStyle(
            style: WyStyle.label,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              for (final e in _params.entries) _paramRow(e.key, e.value),
              // Invoke across the form, the status after it (as in DSA UIs).
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: _Button(
                        label: widget.meta == null ? 'Set' : 'Invoke',
                        onTap: _status == _Status.running ? null : _invoke),
                  ),
                  const SizedBox(width: 8),
                  SizedBox.square(
                    dimension: 20,
                    child: switch (_status) {
                      _Status.idle => null,
                      _Status.running => const Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2, color: WyStyle.accent)),
                      _Status.ok => const Icon(Icons.check, size: 20, color: WyStyle.text),
                      _Status.error => const Icon(Icons.error_outline, size: 20, color: WyStyle.error),
                    },
                  ),
                ]),
              ),
              if (_error != null) _errorRow(_error!),
              // Output only for an action that declares a result, or that
              // sent one (an action without a result shows none).
              if (_declaresResult || _results.isNotEmpty) ..._outputRows(context),
            ]),
          ),
        ),
      );

  /// The error as an output row: label, then a read-only box with the
  /// whole message (wrapped, selectable).
  Widget _errorRow(String message) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(
            width: _labelWidth,
            height: 30,
            child: Align(alignment: Alignment.centerLeft, child: Text('error', style: WyStyle.formLabel)),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 30),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: WyStyle.field,
                border: Border.all(color: WyStyle.error.withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(message, style: WyStyle.input.copyWith(color: WyStyle.error, height: 1.3)),
            ),
          ),
        ]),
      );

  bool get _declaresResult => switch (widget.meta?.result) {
        null || ResultVoid() => false,
        _ => true,
      };

  /// The result as DSA shows an action's columns: a label per column and a
  /// value box; a table (several rows) as a "Table.." button that opens the
  /// table window. `Null` until there is a result.
  List<Widget> _outputRows(BuildContext context) {
    Widget row(String label, Widget box) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(
              width: _labelWidth,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: WyStyle.formLabel),
            ),
            const SizedBox(width: _gap),
            Expanded(child: box),
          ]),
        );
    final results = _results;
    if (results.isEmpty) return [row('output', const _ValueBox(text: 'Null'))];
    // A stream gives several results: one table; one result shows as is.
    final v = results.length == 1 ? results.single : VArray(List.of(results));
    if (_ResultTable.isTable(v)) {
      final title = widget.meta?.display ?? widget.action;
      return [
        row('output', _ValueBox(text: 'Table..', onTap: () => _ResultTable.open(context, title, v))),
      ];
    }
    if (v is VMap) {
      return [
        for (final e in _ResultTable.flat(v.v).entries) row(e.key, _ValueBox(text: _ResultTable.text(e.value))),
      ];
    }
    return [row('output', _ValueBox(text: _ResultTable.text(v)))];
  }

  /// The label (the name for people; the hint in a tooltip) in a fixed
  /// column, the field after it: every field starts at the same x.
  Widget _paramRow(String name, ParamMeta p) {
    final label = p.display ?? name;
    final tip = [label, if (p.description != null) p.description!].join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SizedBox(
        height: p.editor == 'textarea' ? 66 : 30,
        child: Row(children: [
          SizedBox(
            width: _labelWidth,
            child: Tooltip(
              message: tip,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: WyStyle.formLabel),
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(child: _editor(name, p)),
        ]),
      ),
    );
  }

  /// Hint in an empty field: the param's example, and `optional` for a
  /// param that may stay empty (required ones carry no mark).
  static String? _hint(ParamMeta p) {
    if (p.required == true) return p.placeholder;
    return p.placeholder == null ? 'optional' : '${p.placeholder} (optional)';
  }

  /// Pick a local file for an `editor: file` param.
  Future<void> _pick(String name) async {
    final f = await openFile();
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (mounted) setState(() => _files[name] = (name: f.name, bytes: bytes));
  }

  Widget _editor(String name, ParamMeta p) {
    if (_files.containsKey(name)) {
      final f = _files[name];
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _pick(name),
          child: _FieldBox(
            child: Row(children: [
              const Icon(Icons.attach_file, size: 14, color: WyStyle.placeholder),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  f == null ? 'Choose File…' : '${f.name} (${(f.bytes.length / 1024).ceil()} KiB)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: f == null ? WyStyle.input.copyWith(color: WyStyle.placeholder) : WyStyle.input,
                ),
              ),
            ]),
          ),
        ),
      );
    }
    if (_bool.containsKey(name)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Transform.scale(
          scale: 0.7,
          child: Switch(
            value: _bool[name]!,
            activeThumbColor: WyStyle.accent,
            onChanged: (v) => setState(() => _bool[name] = v),
          ),
        ),
      );
    }
    if (_enum.containsKey(name)) {
      // Not DropdownButton: its list is a route under the menu overlay.
      return _EnumField(
        value: _enum[name],
        options: p.enumValues!,
        empty: p.placeholder ?? 'nothing to choose',
        onChanged: (v) => setState(() => _enum[name] = v),
      );
    }
    final area = p.editor == 'textarea';
    return _FieldBox(
      height: area ? 62 : 26,
      child: TextField(
        controller: _text[name],
        style: WyStyle.input,
        cursorColor: WyStyle.accent,
        // A secret: hidden, never pre-filled (spec 02 `editor: password`).
        obscureText: p.isPassword,
        maxLines: area ? 3 : 1,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: _hint(p),
          hintStyle: WyStyle.input.copyWith(color: WyStyle.placeholder),
        ),
        onSubmitted: area ? null : (_) => _invoke(),
      ),
    );
  }
}

/// A result value in the form: a button-like box (`Null`, the value, or
/// `Table..` that opens the table window). Long text is cut; the full text
/// is in a tooltip.
class _ValueBox extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const _ValueBox({required this.text, this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 600),
        child: _Button(label: text, onTap: onTap, passive: onTap == null),
      );
}

/// An enum field: the box shows the value; a click opens the options in
/// the same overlay as the menu, right under the box.
class _EnumField extends StatefulWidget {
  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  /// Shown, dimmed, when there are no options; the field does not open.
  final String empty;
  const _EnumField({required this.value, required this.options, required this.onChanged, this.empty = '—'});

  @override
  State<_EnumField> createState() => _EnumFieldState();
}

class _EnumFieldState extends State<_EnumField> {
  OverlayEntry? _list;

  void _close() {
    _list?.remove();
    _list = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _open() {
    final box = context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero) & box.size;
    _list = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close)),
        Positioned(
          left: at.left,
          top: at.bottom,
          width: at.width,
          child: _MenuPanel(children: [
            for (final o in widget.options)
              _MenuItem(
                label: o,
                onTap: (_) {
                  _close();
                  widget.onChanged(o);
                },
              ),
          ]),
        ),
      ]),
    );
    Overlay.of(context).insert(_list!);
  }

  @override
  Widget build(BuildContext context) {
    final none = widget.options.isEmpty;
    return GestureDetector(
      onTap: none ? null : _open,
      child: MouseRegion(
        cursor: none ? MouseCursor.defer : SystemMouseCursors.click,
        child: _FieldBox(
          child: Row(children: [
            Expanded(
              child: Text(
                none ? widget.empty : widget.value ?? '',
                style: none ? WyStyle.input.copyWith(color: WyStyle.disabled) : WyStyle.input,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: none ? WyStyle.disabled : WyStyle.text),
          ]),
        ),
      ),
    );
  }
}

/// A tabular result (an array of records, or of values) in its own window:
/// a title bar with the action's name and a close button, then a grid
/// with one column per field found in the rows (as many as the data has).
abstract final class _ResultTable {
  /// A table: records (maps). A list of plain values is text.
  static bool isTable(Value v) => v is VArray && v.v.isNotEmpty && v.v.every((e) => e is VMap);

  /// Nested records become their own columns (`params.points`), so every
  /// cell holds one value.
  static Map<String, Value> flat(Map<String, Value> m, [String prefix = '']) => {
        for (final e in m.entries)
          if (e.value case VMap(:final v) when v.isNotEmpty)
            ...flat(v, '$prefix${e.key}.')
          else
            '$prefix${e.key}': e.value,
      };

  static String text(Value v) => switch (v) {
        VNull() => 'Null',
        VMap(:final v) => flat(v).entries.map((e) => '${e.key}: ${text(e.value)}').join(', '),
        VArray(:final v) => v.map(text).join(', '),
        VStr(:final v) => v,
        _ => formatValue(v, null),
      };

  /// Columns: the union of the record keys in order of appearance; values
  /// that are not records go to one column `value`.
  static (List<String>, List<List<Value>>) grid(VArray a) {
    final rows = [for (final r in a.v) flat((r as VMap).v)];
    final cols = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!cols.contains(k)) cols.add(k);
      }
    }
    return (cols, [for (final r in rows) [for (final c in cols) r[c] ?? const VNull()]]);
  }

  static void open(BuildContext context, String title, Value v) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Positioned(
          left: size.width * 0.25,
          top: 40,
          width: size.width * 0.7,
          height: size.height - 80,
          child: _TableWindow(title: title, value: v as VArray, onClose: entry.remove),
        );
      },
    );
    overlay.insert(entry);
  }
}

class _TableWindow extends StatelessWidget {
  final String title;
  final VArray value;
  final VoidCallback onClose;
  const _TableWindow({required this.title, required this.value, required this.onClose});

  static const _colWidth = 180.0;

  @override
  Widget build(BuildContext context) {
    final (cols, rows) = _ResultTable.grid(value);
    Widget cell(String t, {bool head = false}) => Container(
          width: _colWidth,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: head ? WyStyle.panel : null,
            border: Border.all(color: WyStyle.line, width: 0.5),
          ),
          child: Tooltip(
            message: t,
            waitDuration: const Duration(milliseconds: 600),
            child: Text(t,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WyStyle.formLabel.copyWith(color: head ? WyStyle.text : WyStyle.accent)),
          ),
        );
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(color: WyStyle.field, border: Border.all(color: WyStyle.line), boxShadow: WyStyle.shadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 34,
            color: WyStyle.tabBar,
            padding: const EdgeInsets.only(left: 14, right: 6),
            child: Row(children: [
              Expanded(child: Text(title, style: WyStyle.tab.copyWith(fontSize: 14))),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, size: 18, color: WyStyle.text),
                onPressed: onClose,
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _colWidth * cols.length,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 40),
                  Row(children: [for (final c in cols) cell(c, head: true)]),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemExtent: 30,
                      itemBuilder: (_, i) => Row(children: [for (final v in rows[i]) cell(_ResultTable.text(v))]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Form layout: width, label column, gap between label and field.
const _formWidth = 340.0;
const _labelWidth = 120.0;
const _gap = 10.0;

/// Input and select box: `#2B2B2B`, 1px `#424244`, 26px.
class _FieldBox extends StatelessWidget {
  final Widget child;
  final double height;
  const _FieldBox({required this.child, this.height = 26});
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.only(left: 5, right: 2),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: WyStyle.field, border: Border.all(color: WyStyle.line)),
        child: child,
      );
}

/// Button: `#2B2B2B`, 1px `#424244`, radius 4, 11px arial; hover
/// `#2D7581`, pressed `#2ebed7`, white text.
class _Button extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;

  /// A value box, not a control: no hover or press colours.
  final bool passive;
  const _Button({required this.label, this.onTap, this.passive = false});
  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _hover = false;
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final live = !widget.passive;
    final bg = live && _down ? WyStyle.accent : (live && _hover ? WyStyle.selected : WyStyle.field);
    final fg = live && (_down || _hover) ? Colors.white : WyStyle.text;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: bg, border: Border.all(color: WyStyle.line), borderRadius: BorderRadius.circular(4)),
          child: Text(widget.label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: WyStyle.formLabel.copyWith(fontSize: 13, color: fg)),
        ),
      ),
    );
  }
}

/// The "Metrics" panel for the selected node: search row (zoom icon
/// `#2ebed7`, input, menu icon), then rows of its value children with live
/// values, its own value, configs (`$name`) and attributes (`@name`).
/// Writable values are edited in place.
class WyMetrics extends StatefulWidget {
  final WyrmApi api;
  final String? nodeKey;
  const WyMetrics({super.key, required this.api, this.nodeKey});

  @override
  State<WyMetrics> createState() => _WyMetricsState();
}

class _WyMetricsState extends State<WyMetrics> {
  final _search = TextEditingController();
  NodeMeta? _meta;
  List<Child> _children = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final k = widget.nodeKey;
    if (k == null) return;
    // A site root and its `downstream` are built by the client (sections; links
    // by liveliness): no `~meta`, no values of their own.
    if (_isSiteKey(k) || _isLinksRoot(k)) {
      setState(() => _meta = NodeMeta(hasChildren: true));
      return;
    }
    try {
      final m = await widget.api.meta(k);
      final kids = m.isContainer ? await widget.api.children(k) : const <Child>[];
      if (mounted) {
        setState(() {
          _meta = m;
          _children = kids;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is WyrmException ? e.message : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.toLowerCase();
    final m = _meta;
    final rows = <Widget>[];
    bool match(String s) => q.isEmpty || s.toLowerCase().contains(q);
    if (m != null && widget.nodeKey != null) {
      if (!m.isContainer && m.ty != null && match('value')) {
        rows.add(_MetricRow(api: widget.api, name: 'value', key2: widget.nodeKey!, meta: m));
      }
      for (final c in _children.where((c) => _isPoint(c.meta) && match(c.meta.displayName ?? c.name))) {
        rows.add(_MetricRow(
            api: widget.api, name: c.meta.displayName ?? c.name, key2: '${widget.nodeKey}/${c.name}', meta: c.meta));
      }
      final info = <String, String?>{
        r'$is': m.profileName,
        r'$type': m.ty?.wireName,
        r'$writable': m.writable?.wireName,
        r'$invokable': m.invokable?.wireName,
        r'$unit': switch (m.unit) { TText(:final text) => text, null => null, final u => '$u' },
        for (final e in (m.cfg ?? const {}).entries) '\$${e.key}': formatValue(e.value, null),
        for (final e in (m.attr ?? const {}).entries) '@${e.key}': formatValue(e.value, null),
      };
      for (final e in info.entries) {
        if (e.value != null && match(e.key)) rows.add(_StaticRow(name: e.key, value: e.value!));
      }
    }
    return Column(children: [
      const WyTabBar(tabs: ['Metrics']),
      Container(
        height: 49,
        padding: const EdgeInsets.fromLTRB(15, 10, 6, 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: WyStyle.line))),
        child: Row(children: [
          const Icon(Icons.search, size: 18, color: WyStyle.accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: TextField(
                controller: _search,
                style: WyStyle.input,
                cursorColor: WyStyle.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search',
                  hintStyle: WyStyle.input.copyWith(color: WyStyle.placeholder),
                ),
              ),
            ),
          ),
          const Icon(Icons.format_list_bulleted, size: 16, color: WyStyle.text),
        ]),
      ),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(10), child: Text(_error!, style: WyStyle.label.copyWith(color: WyStyle.error))),
      Expanded(child: ListView(children: rows)),
    ]);
  }
}

/// Metrics rows start at the tree's label column: 10 + 16 + 5 + 8.
const _metricInset = 39.0;

class _StaticRow extends StatelessWidget {
  final String name;
  final String value;
  final double inset;
  const _StaticRow({required this.name, required this.value, this.inset = 0});
  @override
  Widget build(BuildContext context) => Container(
        height: WyStyle.rowHeight,
        padding: EdgeInsets.only(left: _metricInset + inset, right: 10),
        alignment: Alignment.centerLeft,
        child: Text('$name : $value', maxLines: 1, overflow: TextOverflow.ellipsis, style: WyStyle.label),
      );
}

/// One value row: name, live value in `#2ebed7` (orange/red when not
/// good); a writable value turns into an input on tap.
class _MetricRow extends StatefulWidget {
  final WyrmApi api;
  final String name;
  final String key2;
  final NodeMeta meta;
  const _MetricRow({required this.api, required this.name, required this.key2, required this.meta});
  @override
  State<_MetricRow> createState() => _MetricRowState();
}

class _MetricRowState extends State<_MetricRow> {
  StreamSubscription<ValEvent>? _sub;
  ValSample? _last;
  TextEditingController? _edit;

  /// `view=list` carries no enum labels: an enum leaf (`status`) loads its
  /// full `~meta` once.
  late NodeMeta _meta = widget.meta;

  /// Expanded: the point's own properties (full `~meta`) below the row.
  bool _open = false;
  Future<NodeMeta>? _full;

  void _toggle() => setState(() {
        _open = !_open;
        if (_open) _full = widget.api.meta(widget.key2);
      });

  List<Widget> _props(NodeMeta m) {
    final rows = <String, String?>{
      r'$is': m.profileName,
      r'$type': m.ty?.wireName,
      r'$writable': m.writable?.wireName,
      r'$unit': switch (m.unit) { TText(:final text) => text, null => null, final u => '$u' },
      r'$enum': m.enumValues?.join(','),
      if (m.displayName != null) r'$name': m.displayName,
      for (final e in (m.cfg ?? const {}).entries) '\$${e.key}': formatValue(e.value, null),
      for (final e in (m.attr ?? const {}).entries) '@${e.key}': formatValue(e.value, null),
      for (final a in (m.actions ?? const {}).keys) a: 'action',
      if (_last?.qual != null) r'$qual': _last!.qual,
    };
    return [
      for (final e in rows.entries)
        if (e.value != null) _StaticRow(name: e.key, value: e.value!, inset: WyStyle.treeIndent),
    ];
  }

  @override
  void initState() {
    super.initState();
    _sub = widget.api.subscribe(widget.key2).listen((e) {
      if (e.key == widget.key2 && mounted) setState(() => _last = e is ValSample ? e : null);
    }, onError: (Object _) {});
    if (_meta.ty == TypeCode.enum_ && _meta.enumValues == null) {
      widget.api.meta(widget.key2).then((m) {
        if (mounted) setState(() => _meta = m);
      }, onError: (Object _) {});
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Why the last `set` was refused, shown under the row.
  String? _setError;

  Future<void> _commit() async {
    final t = _edit!.text.trim();
    setState(() => _edit = null);
    final v = switch (_meta.ty) {
      TypeCode.number => int.tryParse(t) != null ? VInt(int.parse(t)) : VFloat(double.tryParse(t) ?? 0),
      TypeCode.bool_ => VBool(t == 'true' || t == '1'),
      _ => VStr(t),
    };
    await _set(v);
  }

  Future<void> _set(Value v) async {
    setState(() => _setError = null);
    try {
      await widget.api.set(widget.key2, v);
    } catch (e) {
      if (mounted) setState(() => _setError = e is WyrmException ? e.message : '$e');
    }
  }

  /// The value as an editor when someone may set it: a switch for a bool,
  /// the choices for an enum, else the text (tap to edit). `null` when the
  /// node is read only.
  Widget? _valueEditor(ValSample? s, String text, Color color) {
    if (!_meta.isSettable) return null;
    final v = s?.sample.v;
    if (_meta.ty == TypeCode.bool_) {
      return SizedBox(
        height: WyStyle.rowHeight,
        child: Transform.scale(
          scale: 0.6,
          alignment: Alignment.centerLeft,
          child: Switch(
            value: v is VBool && v.v,
            activeThumbColor: WyStyle.accent,
            onChanged: (on) => _set(VBool(on)),
          ),
        ),
      );
    }
    final labels = _meta.enumValues;
    if (_meta.ty == TypeCode.enum_ && labels != null && labels.isNotEmpty) {
      // An enum node's value is the index of its label.
      final i = v is VInt ? v.v : -1;
      return SizedBox(
        // a menu panel is at least 160 wide: the list fits under the field
        width: 160,
        child: _EnumField(
          value: i >= 0 && i < labels.length ? labels[i] : null,
          options: labels,
          onChanged: (label) => _set(VInt(labels.indexOf(label))),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = _last;
    final text = s == null ? '' : formatValue(s.sample.v, _meta);
    // The driver framework's `status` (Failed red, Connecting orange,
    // Stopped dim) and `error` leaves.
    final profile = _meta.profileName;
    final stateColor = profile != 'wy:df-status'
        ? null
        : switch (text) {
            'Failed' => Colors.redAccent,
            'Connecting' => Colors.orange,
            'Stopped' || 'Stopped by Parent' || 'Unknown' => WyStyle.disabled,
            _ => null,
          };
    final color = switch (s?.sample.q) {
      Quality.uncertain => Colors.orange,
      Quality.bad => Colors.redAccent,
      _ when profile == 'wy:df-error' => Colors.redAccent,
      _ => stateColor ?? WyStyle.text,
    };
    final row = Container(
      height: WyStyle.rowHeight,
      padding: const EdgeInsets.only(left: WyStyle.treePaddingLeft, right: 10),
      child: Row(children: [
        GestureDetector(
          onTap: _toggle,
          child: SizedBox.square(
            dimension: 16,
            child: CustomPaint(painter: _Triangle(_open, WyStyle.text)),
          ),
        ),
        const SizedBox(width: 5 + 8),
        GestureDetector(
          onDoubleTap: _toggle,
          child: Text(widget.name),
        ),
        if (isRecorded(_meta)) _HistoryMark(api: widget.api, nodeKey: widget.key2, color: WyStyle.text),
        if (s != null) const Text(' : '),
        if (_edit != null)
          SizedBox(
            width: 110,
            child: _FieldBox(
              child: TextField(
                controller: _edit,
                autofocus: true,
                style: WyStyle.input,
                cursorColor: WyStyle.accent,
                decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                onSubmitted: (_) => _commit(),
                onTapOutside: (_) => setState(() => _edit = null),
              ),
            ),
          )
        else if (_valueEditor(s, text, color) case final editor?)
          editor
        else
          GestureDetector(
            onTap: _meta.isSettable
                ? () => setState(() => _edit = TextEditingController(text: s == null ? '' : text))
                : null,
            child: MouseRegion(
              cursor: _meta.isSettable ? SystemMouseCursors.text : MouseCursor.defer,
              child: s == null
                  ? const SizedBox.shrink()
                  : Text(
                      s.sample.q != Quality.good ? '$text (${s.qual ?? s.sample.q.wireName})' : text,
                      style: WyStyle.label.copyWith(color: color),
                    ),
            ),
          ),
      ]),
    );
    // A point has actions too (edit, remove, @set): right click as in the tree.
    final menuRow = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (d) => WyContextMenu.show(context, d.globalPosition, widget.api, widget.key2),
      child: row,
    );
    final failed = _setError == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(_metricInset, 0, 10, 6),
            child: Text(_setError!, style: WyStyle.label.copyWith(color: WyStyle.error)),
          );
    if (!_open && failed == null) return menuRow;
    if (!_open) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [menuRow, failed!]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      menuRow,
      if (failed != null) failed,
      FutureBuilder<NodeMeta>(
        future: _full,
        builder: (context, snap) => snap.hasData
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _props(snap.data!))
            : _StaticRow(name: 'loading', value: '…', inset: WyStyle.treeIndent),
      ),
    ]);
  }
}
