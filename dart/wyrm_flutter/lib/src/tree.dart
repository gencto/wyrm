// A lazy node tree (wiki "Реактивність — як list стає стрімом", Dart/Flutter):
// every expanded node holds its own `list()`; collapsing it cancels that
// stream. A visible leaf holds one `subscribe()` on its exact key.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// A tree of WYRM nodes under [rootKey], with live values on the leaves.
class WyrmTree extends StatelessWidget {
  final WyrmApi api;

  /// Full node key, for example `wy/plant-a/down`.
  final String rootKey;

  /// Called on a tap on a leaf (for example to open a `set` dialog).
  final void Function(String key, Child child)? onLeafTap;

  /// Opens a node (its full `~meta` and actions); adds a button to each row.
  final void Function(String key, Child child)? onNodeOpen;

  const WyrmTree({super.key, required this.api, required this.rootKey, this.onLeafTap, this.onNodeOpen});

  @override
  Widget build(BuildContext context) =>
      SingleChildScrollView(
          child: WyrmChildren(api: api, nodeKey: rootKey, onLeafTap: onLeafTap, onNodeOpen: onNodeOpen));
}

/// The children of one node, kept current by `list()` while this widget lives.
class WyrmChildren extends StatefulWidget {
  final WyrmApi api;
  final String nodeKey;
  final int depth;
  final void Function(String key, Child child)? onLeafTap;

  /// Opens a node (its full `~meta` and actions); adds a button to each row.
  final void Function(String key, Child child)? onNodeOpen;

  const WyrmChildren({
    super.key,
    required this.api,
    required this.nodeKey,
    this.depth = 0,
    this.onLeafTap,
    this.onNodeOpen,
  });

  @override
  State<WyrmChildren> createState() => _WyrmChildrenState();
}

class _WyrmChildrenState extends State<WyrmChildren> {
  StreamSubscription<ListUpdate>? _sub;

  /// Insertion-ordered: the order of `refreshed`, then additions.
  final Map<String, Child> _children = {};
  bool _loaded = false;
  bool _ownerGone = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(WyrmChildren old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api || old.nodeKey != widget.nodeKey) {
      _sub?.cancel();
      _children.clear();
      _loaded = false;
      _listen();
    }
  }

  void _listen() {
    _sub = widget.api.list(widget.nodeKey).listen(
          (u) => setState(() => _apply(u)),
          onError: (Object e) => setState(() => _error = e),
        );
  }

  void _apply(ListUpdate u) {
    switch (u) {
      case ListRefreshed(:final children):
        _children
          ..clear()
          ..addEntries(children.map((c) => MapEntry(c.name, c)));
        _loaded = true;
        _ownerGone = false;
        _error = null;
      case ChildAdded(:final child):
      case ChildChanged(:final child):
        _children[child.name] = child;
      case ChildRemoved(:final name):
        _children.remove(name);
      case ChildDisconnected(name: null):
        _ownerGone = true;
      case ChildDisconnected():
      case ChildConnected():
        break;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.only(left: 16.0 * widget.depth + 16);
    if (_error != null) {
      return Padding(
        padding: pad,
        child: Text('$_error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
    if (!_loaded) {
      return Padding(
        padding: pad,
        child: const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_ownerGone)
          Padding(padding: pad, child: const Text('disconnected', style: TextStyle(fontStyle: FontStyle.italic))),
        for (final c in _children.values)
          WyrmNodeTile(
            key: ValueKey(c.name),
            api: widget.api,
            parentKey: widget.nodeKey,
            child: c,
            depth: widget.depth,
            onLeafTap: widget.onLeafTap,
            onNodeOpen: widget.onNodeOpen,
          ),
      ],
    );
  }
}

/// One node: a container expands into [WyrmChildren]; a leaf shows its value.
class WyrmNodeTile extends StatefulWidget {
  final WyrmApi api;
  final String parentKey;
  final Child child;
  final int depth;
  final void Function(String key, Child child)? onLeafTap;

  /// Opens a node (its full `~meta` and actions); adds a button to each row.
  final void Function(String key, Child child)? onNodeOpen;

  const WyrmNodeTile({
    super.key,
    required this.api,
    required this.parentKey,
    required this.child,
    required this.depth,
    this.onLeafTap,
    this.onNodeOpen,
  });

  String get nodeKey => '$parentKey/${child.name}';

  @override
  State<WyrmNodeTile> createState() => _WyrmNodeTileState();
}

class _WyrmNodeTileState extends State<WyrmNodeTile> {
  bool _expanded = false;

  Widget? _openButton() => widget.onNodeOpen == null
      ? null
      : IconButton(
          icon: const Icon(Icons.tune, size: 18),
          tooltip: 'Details and actions',
          onPressed: () => widget.onNodeOpen!(widget.nodeKey, widget.child),
        );

  @override
  Widget build(BuildContext context) {
    final meta = widget.child.meta;
    final title = meta.displayName ?? widget.child.name;
    final indent = 16.0 * widget.depth;
    if (meta.isContainer) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.only(left: indent + 8, right: 16),
            leading: Icon(_expanded ? Icons.expand_more : Icons.chevron_right),
            title: Text(title),
            trailing: _openButton(),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          // Collapsing removes the widget, which cancels its list().
          if (_expanded)
            WyrmChildren(
              api: widget.api,
              nodeKey: widget.nodeKey,
              depth: widget.depth + 1,
              onLeafTap: widget.onLeafTap,
              onNodeOpen: widget.onNodeOpen,
            ),
        ],
      );
    }
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: indent + 48, right: 16),
      title: Text(title),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        WyrmValue(api: widget.api, nodeKey: widget.nodeKey, meta: meta),
        if (_openButton() case final b?) b,
      ]),
      onTap: widget.onLeafTap == null ? null : () => widget.onLeafTap!(widget.nodeKey, widget.child),
    );
  }
}

/// The live value of one node (one `subscribe()` while visible).
class WyrmValue extends StatefulWidget {
  final WyrmApi api;
  final String nodeKey;

  /// For units, enum labels and precision.
  final NodeMeta? meta;

  const WyrmValue({super.key, required this.api, required this.nodeKey, this.meta});

  @override
  State<WyrmValue> createState() => _WyrmValueState();
}

class _WyrmValueState extends State<WyrmValue> {
  StreamSubscription<ValEvent>? _sub;
  ValSample? _last;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(WyrmValue old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api || old.nodeKey != widget.nodeKey) {
      _sub?.cancel();
      _last = null;
      _listen();
    }
  }

  void _listen() {
    _sub = widget.api.subscribe(widget.nodeKey).listen(
      (e) {
        if (e.key != widget.nodeKey) return;
        setState(() => _last = e is ValSample ? e : null);
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _last;
    if (s == null) return const Text('—');
    final text = formatValue(s.sample.v, widget.meta);
    final q = s.sample.q;
    final color = switch (q) {
      Quality.good => null,
      Quality.uncertain => Colors.orange,
      Quality.bad => Theme.of(context).colorScheme.error,
    };
    return Text(
      q == Quality.good ? text : '$text (${s.qual ?? q.wireName})',
      style: TextStyle(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

/// A value as text: enum labels, `cfg.precision`, the unit.
String formatValue(Value v, NodeMeta? meta) {
  final unit = switch (meta?.unit) { TText(:final text) => ' $text', _ => '' };
  final precision = switch (meta?.cfg?['precision']) { VInt(:final v) => v, _ => 2 };
  final labels = meta?.enumValues;
  return switch (v) {
    VNull() => '—',
    VBool(:final v) => '$v',
    VInt(:final v) when labels != null && v >= 0 && v < labels.length => labels[v],
    VInt(:final v) => '$v$unit',
    VFloat(:final v) => '${v.toStringAsFixed(precision.clamp(0, 10))}$unit',
    VStr(:final v) => v,
    VBytes(:final v) => '${v.length} bytes',
    VArray(:final v) => '[${v.length}]',
    // A status map (driver framework): its state, and the error if any.
    VMap(:final v) when v['state'] is VStr => switch (v['error']) {
        VStr(v: final e) => '${(v['state']! as VStr).v}: $e',
        _ => (v['state']! as VStr).v,
      },
    VMap(:final v) => '{${v.length}}',
  };
}
