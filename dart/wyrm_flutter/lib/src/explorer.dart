// The WYRM node explorer: a virtual tree of 30px rows ("Data"), a context
// menu with the node's actions, an action flyout (params, Invoke, status,
// results) and a "Metrics" panel with the selected node's values, configs
// and attributes. Colours and measures: explorer_theme.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'explorer_theme.dart';
import 'tree.dart' show formatValue;

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
/// (`wy/edge/down`) or a site (`wy/central`), which shows `down`, `up`,
/// `flows` and `sys` (spec 01; a site root has no `~meta` to list). A node
/// with `@root` (a peer broker: `down/<site>`, `up/<site>`) also opens
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

  static const _sections = ['down', 'up', 'flows', 'sys'];

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
      _kids[key] = [for (final s in _sections) Child(s, NodeMeta(hasChildren: true))];
    }
  }

  bool _synthetic(String key) => _sites.contains(key);

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
    final isContainer = r.meta.isContainer;
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
        ]),
      ),
    );
  }
}

/// The node's context menu: its actions, `@set` for a
/// writable node, a separator and "Copy Path". An action with params opens
/// the flyout to the right of its item.
abstract final class WyContextMenu {
  static void show(BuildContext context, Offset at, WyrmApi api, String key) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    OverlayEntry? flyout;
    void close() {
      flyout?.remove();
      flyout = null;
      entry.remove();
    }

    void openFlyout(Rect item, String action, ActionMeta? meta, NodeMeta node) {
      flyout?.remove();
      flyout = OverlayEntry(
        builder: (_) => Positioned(
          left: item.right,
          top: item.top,
          child: _ActionFlyout(
            api: api,
            nodeKey: key,
            action: action,
            meta: meta,
            node: node,
            // No params: run at once, the flyout shows status and results.
            autoRun: meta != null && meta.params.isEmpty,
          ),
        ),
      );
      overlay.insert(flyout!);
    }

    entry = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: close,
            onSecondaryTap: close,
          ),
        ),
        Positioned(
          left: at.dx,
          top: at.dy,
          child: _Menu(
            api: api,
            nodeKey: key,
            onClose: close,
            onAction: openFlyout,
          ),
        ),
      ]),
    );
    overlay.insert(entry);
  }
}

class _Menu extends StatefulWidget {
  final WyrmApi api;
  final String nodeKey;
  final VoidCallback onClose;
  final void Function(Rect item, String action, ActionMeta? meta, NodeMeta node) onAction;
  const _Menu({required this.api, required this.nodeKey, required this.onClose, required this.onAction});

  @override
  State<_Menu> createState() => _MenuState();
}

class _MenuState extends State<_Menu> {
  late final Future<NodeMeta> _meta = widget.api.meta(widget.nodeKey);

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 360),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: WyStyle.panel,
            border: Border.all(color: WyStyle.line),
            boxShadow: WyStyle.shadow,
          ),
          child: FutureBuilder<NodeMeta>(
            future: _meta,
            builder: (context, snap) {
              final m = snap.data;
              if (snap.hasError) return IntrinsicWidth(child: _item(context, '${snap.error}', disabled: true));
              if (m == null) return IntrinsicWidth(child: _item(context, 'Loading…', disabled: true));
              // Level `none`: not for people (a link handshake).
              final actions = [
                for (final e in (m.actions ?? const <String, ActionMeta>{}).entries)
                  if (e.value.level != Perm.none) e.key,
              ]..sort();
              return IntrinsicWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final a in actions)
                    _item(context, a, submenu: m.actions![a]!.params.isNotEmpty, onTap: (rect) {
                      widget.onAction(rect, a, m.actions![a], m);
                    }),
                  if (m.isWritable)
                    _item(context, '@set', submenu: true, onTap: (rect) => widget.onAction(rect, '@set', null, m)),
                  if (actions.isEmpty && !m.isWritable) _item(context, 'No actions', disabled: true),
                  Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 2), color: WyStyle.line),
                  _item(context, 'Copy Path', onTap: (_) {
                    Clipboard.setData(ClipboardData(text: widget.nodeKey));
                    widget.onClose();
                  }),
                ]),
              );
            },
          ),
        ),
      );

  Widget _item(BuildContext context, String label,
          {bool submenu = false, bool disabled = false, void Function(Rect)? onTap}) =>
      _MenuItem(label: label, submenu: submenu, disabled: disabled, onTap: onTap);
}

class _MenuItem extends StatefulWidget {
  final String label;
  final bool submenu;
  final bool disabled;
  final void Function(Rect)? onTap;
  const _MenuItem({required this.label, this.submenu = false, this.disabled = false, this.onTap});

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
        // Submenus open on hover.
        if (widget.submenu && !widget.disabled) widget.onTap?.call(_rect());
      },
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : () => widget.onTap?.call(_rect()),
        child: Container(
          height: 30,
          color: on ? WyStyle.selected : null,
          padding: const EdgeInsets.only(left: 15, right: 10),
          child: Row(children: [
            Text(widget.label, style: WyStyle.menu.copyWith(color: color)),
            const SizedBox(width: 10),
            const Spacer(),
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

/// The action flyout (200px): one row per param (label
/// 30% + editor), "Invoke", the status indicator, then the results.
class _ActionFlyout extends StatefulWidget {
  final WyrmApi api;
  final String nodeKey;
  final String action;

  /// `null` for the `@set` pseudo-action (one `value` param of the node type).
  final ActionMeta? meta;
  final NodeMeta node;
  final bool autoRun;
  const _ActionFlyout(
      {required this.api,
      required this.nodeKey,
      required this.action,
      required this.meta,
      required this.node,
      this.autoRun = false});

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
  final _results = <String>[];
  _Status _status = _Status.idle;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final e in _params.entries) {
      final p = e.value;
      final d = p.defaultValue;
      if (p.ty == TypeCode.bool_) {
        _bool[e.key] = d is VBool && d.v;
      } else if (p.enumValues != null && p.enumValues!.isNotEmpty) {
        _enum[e.key] = d is VStr ? d.v : p.enumValues!.first;
      } else {
        _text[e.key] = TextEditingController(text: d == null || d is VNull ? '' : formatValue(d, null));
      }
    }
    if (widget.autoRun) _invoke();
  }

  Value _value(String k, ParamMeta p) {
    if (_bool.containsKey(k)) return VBool(_bool[k]!);
    if (_enum.containsKey(k)) {
      final s = _enum[k]!;
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
          args[e.key] = _value(e.key, e.value);
        }
        await for (final v in widget.api.invoke(widget.nodeKey, widget.action, VMap(args))) {
          if (!mounted) return;
          setState(() => _results.addAll(_lines(v)));
        }
      }
      if (mounted) setState(() => _status = _Status.ok);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.error;
          _error = '$e';
        });
      }
    }
  }

  List<String> _lines(Value v) => switch (v) {
        VMap(:final v) => [for (final e in v.entries) '${e.key}: ${formatValue(e.value, null)}'],
        VArray(:final v) => [for (final e in v) formatValue(e, null)],
        _ => [formatValue(v, null)],
      };

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: WyStyle.panel, border: Border.all(color: WyStyle.line), boxShadow: WyStyle.shadow),
          child: DefaultTextStyle(
            style: WyStyle.label,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              for (final e in _params.entries) _paramRow(e.key, e.value),
              Row(children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 5, 0, 5),
                    child: _Button(
                        label: widget.meta == null ? 'Set' : 'Invoke',
                        onTap: _status == _Status.running ? null : _invoke),
                  ),
                ),
                if (_status != _Status.idle) ...[
                  const SizedBox(width: 5),
                  switch (_status) {
                    _Status.running => const SizedBox.square(
                        dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: WyStyle.accent)),
                    _Status.ok => const Icon(Icons.check, size: 16, color: WyStyle.accent),
                    _ => const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
                  },
                ],
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: Text(_error!, style: WyStyle.label.copyWith(color: Colors.redAccent)),
                ),
              for (final r in _results)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  child: SelectableText(r, style: WyStyle.label.copyWith(color: WyStyle.accent)),
                ),
            ]),
          ),
        ),
      );

  Widget _paramRow(String name, ParamMeta p) => SizedBox(
        height: 30,
        child: Row(children: [
          SizedBox(
            width: 56, // 30% of the 190px content
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Expanded(child: _editor(name, p)),
        ]),
      );

  Widget _editor(String name, ParamMeta p) {
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
      return _FieldBox(
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _enum[name],
            isExpanded: true,
            dropdownColor: WyStyle.field,
            iconEnabledColor: WyStyle.text,
            iconSize: 16,
            style: WyStyle.input,
            items: [for (final o in p.enumValues!) DropdownMenuItem(value: o, child: Text(o))],
            onChanged: (v) => setState(() => _enum[name] = v),
          ),
        ),
      );
    }
    return _FieldBox(
      child: TextField(
        controller: _text[name],
        style: WyStyle.input,
        cursorColor: WyStyle.accent,
        decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
        onSubmitted: (_) => _invoke(),
      ),
    );
  }
}

/// Input and select box: `#2B2B2B`, 1px `#424244`, 26px.
class _FieldBox extends StatelessWidget {
  final Widget child;
  const _FieldBox({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        height: 26,
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
  const _Button({required this.label, this.onTap});
  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _hover = false;
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final bg = _down ? WyStyle.accent : (_hover ? WyStyle.selected : WyStyle.field);
    final fg = (_down || _hover) ? Colors.white : WyStyle.text;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: Container(
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: bg, border: Border.all(color: WyStyle.line), borderRadius: BorderRadius.circular(4)),
          child: Text(widget.label, style: TextStyle(fontFamily: 'Arial', fontSize: 11, color: fg)),
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
      if (mounted) setState(() => _error = '$e');
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
      for (final c in _children.where((c) => _isPoint(c.meta) && match(c.name))) {
        rows.add(_MetricRow(api: widget.api, name: c.name, key2: '${widget.nodeKey}/${c.name}', meta: c.meta));
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
        Padding(padding: const EdgeInsets.all(10), child: Text(_error!, style: WyStyle.label.copyWith(color: Colors.redAccent))),
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
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _commit() async {
    final t = _edit!.text.trim();
    setState(() => _edit = null);
    final v = switch (widget.meta.ty) {
      TypeCode.number => int.tryParse(t) != null ? VInt(int.parse(t)) : VFloat(double.tryParse(t) ?? 0),
      TypeCode.bool_ => VBool(t == 'true' || t == '1'),
      _ => VStr(t),
    };
    try {
      await widget.api.set(widget.key2, v);
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _last;
    final text = s == null ? '' : formatValue(s.sample.v, widget.meta);
    // A status map that is not `connected` reads as a fault.
    final faulty = switch (s?.sample.v) {
      VMap(:final v) => v['state'] is VStr && (v['state']! as VStr).v != 'connected',
      _ => false,
    };
    final color = switch (s?.sample.q) {
      Quality.uncertain => Colors.orange,
      Quality.bad => Colors.redAccent,
      _ when faulty => Colors.redAccent,
      _ => WyStyle.text,
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
          child: Text(s == null ? widget.name : '${widget.name} : '),
        ),
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
        else
          GestureDetector(
            onTap: widget.meta.isWritable
                ? () => setState(() => _edit = TextEditingController(text: s == null ? '' : text))
                : null,
            child: MouseRegion(
              cursor: widget.meta.isWritable ? SystemMouseCursors.text : MouseCursor.defer,
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
    if (!_open) return row;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row,
      FutureBuilder<NodeMeta>(
        future: _full,
        builder: (context, snap) => snap.hasData
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _props(snap.data!))
            : _StaticRow(name: 'loading', value: '…', inset: WyStyle.treeIndent),
      ),
    ]);
  }
}
