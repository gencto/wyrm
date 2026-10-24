// The dataflow editor (ADR 0019): a flow of spec 06 drawn as DSA draws a
// dataflow — blocks with one row per port, S-curve wires, a palette and
// the properties of the selected block — checked as it is edited and
// deployed with a button.

part of 'explorer.dart';

/// `wy/<site>/dataflows/<id>`: a flow.
bool _isFlowKey(String k) => RegExp(r'^wy/[^/]+/dataflows/[^/]+$').hasMatch(k);

/// `wy/<site>/dataflows`: the flows of a site.
bool _isFlowsRoot(String k) => RegExp(r'^wy/[^/]+/dataflows$').hasMatch(k);

abstract final class WyDataflowEditor {
  /// Edit the flow [key] (`…/dataflows/<id>`), or make one under [key]
  /// (`…/dataflows`).
  static void open(BuildContext context, WyrmApi api, String key) {
    final flow = _isFlowKey(key);
    final root = flow ? key.substring(0, key.lastIndexOf('/')) : key;
    final id = flow ? key.substring(key.lastIndexOf('/') + 1) : null;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Positioned(
          left: size.width * 0.03,
          top: 30,
          width: size.width * 0.94,
          height: size.height - 60,
          child: _DataflowWindow(api: api, root: root, id: id, onClose: entry.remove),
        );
      },
    );
    overlay.insert(entry);
  }
}

String _text(Value? v) => switch (v) {
  VStr(:final v) => v,
  _ => '',
};

List<String> _texts(Value? v) => switch (v) {
  VArray(:final v) => [for (final x in v) _text(x)],
  _ => const [],
};

/// A WYRM value as JSON (for map and dynamic params).
Object? _toJson(Value v) => switch (v) {
  VNull() => null,
  VBool(:final v) => v,
  VInt(:final v) => v,
  VFloat(:final v) => v,
  VStr(:final v) => v,
  VBytes(:final v) => v.toList(),
  VArray(:final v) => [for (final x in v) _toJson(x)],
  VMap(:final v) => {for (final e in v.entries) e.key: _toJson(e.value)},
};

Value _fromJson(Object? j) => switch (j) {
  null => const VNull(),
  bool b => VBool(b),
  int i => VInt(i),
  double d => VFloat(d),
  String s => VStr(s),
  List<Object?> l => VArray([for (final x in l) _fromJson(x)]),
  Map<String, Object?> m => VMap({for (final e in m.entries) e.key: _fromJson(e.value)}),
  _ => VStr('$j'),
};

class _ParamInfo {
  final String name, type, description;
  final bool required;
  final List<String> choices;
  final String? defaultValue, editor;
  _ParamInfo(Map<String, Value> m)
    : name = _text(m['name']),
      type = _text(m['type']),
      description = _text(m['description']),
      required = m['required'] == const VBool(true),
      choices = _texts(m['choices']),
      defaultValue = m['default'] == null ? null : _text(m['default']),
      editor = m['editor'] == null ? null : _text(m['editor']);
}

/// Ports named by a parameter (`expression` inputs, `wasm` ports).
class _DynPorts {
  final String param, prefix;
  final List<String> defaults;
  _DynPorts(Map<String, Value> m)
    : param = _text(m['param']),
      prefix = _text(m['prefix']),
      defaults = _texts(m['default']);

  List<String> of(Map<String, Value> cfg) {
    final names = _texts(cfg[param]).where((n) => n.isNotEmpty).toList();
    return [for (final n in names.isEmpty ? defaults : names) '$prefix$n'];
  }
}

class _TypeInfo {
  final String type, category, description;
  final List<String> inputs, outputs;
  final _DynPorts? dynIn, dynOut;
  final List<_ParamInfo> params;
  _TypeInfo(Map<String, Value> m)
    : type = _text(m['type']),
      category = _text(m['category']),
      description = _text(m['description']),
      inputs = _texts(m['inputs']),
      outputs = _texts(m['outputs']),
      dynIn = switch (m['dyn_inputs']) {
        VMap(:final v) => _DynPorts(v),
        _ => null,
      },
      dynOut = switch (m['dyn_outputs']) {
        VMap(:final v) => _DynPorts(v),
        _ => null,
      },
      params = switch (m['params']) {
        VArray(:final v) => [
          for (final p in v)
            if (p is VMap) _ParamInfo(p.v),
        ],
        _ => const [],
      };

  List<String> ins(Map<String, Value> cfg) => dynIn?.of(cfg) ?? inputs;
  List<String> outs(Map<String, Value> cfg) => dynOut?.of(cfg) ?? outputs;
}

class _DfNode {
  String id;
  final String type;
  final Map<String, Value> cfg;
  Offset pos;
  _DfNode(this.id, this.type, this.cfg, this.pos);
}

class _DfEdge {
  String from, fromPort, to, toPort;
  _DfEdge(this.from, this.fromPort, this.to, this.toPort);
}

/// `<node>.<port>` (the port may have dots: `in.a`).
(String, String)? _endpoint(String s) {
  final i = s.indexOf('.');
  return i <= 0 || i == s.length - 1 ? null : (s.substring(0, i), s.substring(i + 1));
}

// Block geometry (canvas units).
const double _blockW = 170, _headH = 24, _rowH = 20, _pinR = 4.5, _canvasSize = 4000;

class _DataflowWindow extends StatefulWidget {
  final WyrmApi api;
  final String root;
  final String? id;
  final VoidCallback onClose;
  const _DataflowWindow({required this.api, required this.root, required this.id, required this.onClose});

  @override
  State<_DataflowWindow> createState() => _DataflowWindowState();
}

class _DataflowWindowState extends State<_DataflowWindow> {
  final _types = <String, _TypeInfo>{};
  final _nodes = <String, _DfNode>{};
  final _edges = <_DfEdge>[];

  /// Fields of the definition the editor does not edit (policy, …), kept.
  final _rest = <String, Value>{};
  late final _idField = TextEditingController(text: widget.id ?? '');
  int _version = 0;
  String? _selected;
  String? _error;
  bool _loading = true;
  bool? _ok;
  String _check = '';
  String _deployed = '';
  bool _dirty = false;
  bool _deploying = false;
  String _state = '';
  StreamSubscription<ValEvent>? _stateSub;
  Timer? _checkTimer;

  // view: canvas offset in the viewport and zoom
  Offset _pan = const Offset(40, 40);
  double _zoom = 1;
  final _canvasKey = GlobalKey();
  final _focus = FocusNode();

  // a wire being drawn from an output pin
  (String, String)? _wireFrom;
  Offset? _wireTo;

  // properties of the selected block: one controller per text param
  final _ctl = <String, TextEditingController>{};

  bool get _isNew => widget.id == null;
  String get _flowId => _idField.text.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _checkTimer?.cancel();
    _focus.dispose();
    _idField.dispose();
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cat = await widget.api.invoke(widget.root, 'node_types').first;
      if (cat is VArray) {
        for (final t in cat.v) {
          if (t is VMap) {
            final info = _TypeInfo(t.v);
            _types[info.type] = info;
          }
        }
      }
      if (widget.id case final id?) {
        final defs = await widget.api.invoke('${widget.root}/$id', 'history').first;
        if (defs is VArray && defs.v.isNotEmpty && defs.v.last is VMap) {
          _fromDef((defs.v.last as VMap).v);
        }
        _stateSub = widget.api.subscribe('${widget.root}/$id').listen((e) {
          if (e is! ValSample || !mounted) return;
          final v = e.sample.v;
          if (v is! VMap) return;
          final st = switch (v.v['state']) {
            VInt(:final v) => ['running', 'stopped', 'error'][v.clamp(0, 2)],
            _ => '?',
          };
          final ver = switch (v.v['version']) {
            VInt(:final v) => ' v$v',
            _ => '',
          };
          setState(() => _state = '$st$ver');
        });
      }
      setState(() => _loading = false);
      _scheduleCheck();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e is WyrmException ? e.message : '$e';
      });
    }
  }

  void _fromDef(Map<String, Value> d) {
    _version = switch (d['version']) {
      VInt(:final v) => v,
      _ => 0,
    };
    final layout = switch (d['layout']) {
      VMap(:final v) => v,
      _ => const <String, Value>{},
    };
    var i = 0;
    if (d['nodes'] case VMap(:final v)) {
      for (final e in v.entries) {
        final cfg = Map<String, Value>.from(e.value is VMap ? (e.value as VMap).v : const {});
        final type = _text(cfg.remove('type'));
        final xy = layout[e.key];
        final pos = switch (xy) {
          VArray(:final v) when v.length == 2 => Offset(_num(v[0]), _num(v[1])),
          _ => Offset(40 + 220.0 * (i % 4), 40 + 160.0 * (i ~/ 4)),
        };
        _nodes[e.key] = _DfNode(e.key, type, cfg, pos);
        i++;
      }
    }
    if (d['edges'] case VArray(:final v)) {
      for (final pair in v) {
        if (pair is VArray && pair.v.length == 2) {
          final a = _endpoint(_text(pair.v[0])), b = _endpoint(_text(pair.v[1]));
          if (a != null && b != null) _edges.add(_DfEdge(a.$1, a.$2, b.$1, b.$2));
        }
      }
    }
    for (final e in d.entries) {
      if (!const ['id', 'version', 'nodes', 'edges', 'layout'].contains(e.key)) _rest[e.key] = e.value;
    }
  }

  static double _num(Value v) => switch (v) {
    VInt(:final v) => v.toDouble(),
    VFloat(:final v) => v,
    _ => 0,
  };

  /// The definition as it is drawn; [version] the one to deploy.
  VMap _toDef(int version) {
    final rest = Map<String, Value>.from(_rest);
    final commands = _nodes.values.any((n) => n.type == 'set' || n.type == 'invoke');
    if (commands && rest['permissions'] == null) {
      rest['permissions'] = const VMap({'maxperm': VStr('write')});
    }
    return VMap({
      ...rest,
      'id': VStr(_flowId),
      'version': VInt(version),
      'nodes': VMap({
        for (final n in _nodes.values) n.id: VMap({'type': VStr(n.type), ...n.cfg}),
      }),
      'edges': VArray([
        for (final e in _edges) VArray([VStr('${e.from}.${e.fromPort}'), VStr('${e.to}.${e.toPort}')]),
      ]),
      'layout': VMap({
        for (final n in _nodes.values) n.id: VArray([VInt(n.pos.dx.round()), VInt(n.pos.dy.round())]),
      }),
    });
  }

  void _changed() {
    setState(() => _dirty = true);
    _scheduleCheck();
  }

  void _scheduleCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer(const Duration(milliseconds: 400), _runCheck);
  }

  Future<void> _runCheck() async {
    if (_flowId.isEmpty) {
      setState(() {
        _ok = false;
        _check = 'name the flow';
      });
      return;
    }
    try {
      final r = await widget.api.invoke(widget.root, 'validate', VMap({'def': _toDef(_version + 1)})).first;
      if (!mounted) return;
      setState(() {
        _ok = r is VMap && r.v['ok'] == const VBool(true);
        _check = _ok! ? 'ok' : (r is VMap ? _text(r.v['error']) : '$r');
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _check = e is WyrmException ? e.message : '$e';
        });
      }
    }
  }

  Future<void> _deploy() async {
    setState(() => _deploying = true);
    try {
      final v = _version + 1;
      await widget.api.invoke(widget.root, 'deploy', VMap({'def': _toDef(v)})).drain<void>();
      if (!mounted) return;
      setState(() {
        _version = v;
        _dirty = false;
        _deployed = 'deployed version $v';
      });
    } catch (e) {
      if (mounted) setState(() => _deployed = e is WyrmException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _deploying = false);
    }
  }

  // ---------- edits ----------

  String _freeId(String base) {
    final stem = base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    for (var i = 1; ; i++) {
      final id = '$stem$i';
      if (!_nodes.containsKey(id)) return id;
    }
  }

  void _add(String type, Offset at) {
    final id = _freeId(type);
    final cfg = <String, Value>{};
    if (type == 'expression') cfg['inputs'] = const VArray([VStr('a')]);
    _nodes[id] = _DfNode(id, type, cfg, at);
    _select(id);
    _changed();
  }

  void _remove(String id) {
    _nodes.remove(id);
    _edges.removeWhere((e) => e.from == id || e.to == id);
    if (_selected == id) _select(null);
    _changed();
  }

  void _rename(String old, String id) {
    if (id == old || id.isEmpty || !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(id) || _nodes.containsKey(id)) return;
    final n = _nodes.remove(old)!..id = id;
    _nodes[id] = n;
    for (final e in _edges) {
      if (e.from == old) e.from = id;
      if (e.to == old) e.to = id;
    }
    _selected = id;
    _changed();
  }

  /// An input takes one link (as DSA binds an input to one source).
  void _link(String from, String fromPort, String to, String toPort) {
    if (from == to) return;
    _edges.removeWhere((e) => e.to == to && e.toPort == toPort);
    _edges.add(_DfEdge(from, fromPort, to, toPort));
    _changed();
  }

  void _unlink(String to, String toPort) {
    _edges.removeWhere((e) => e.to == to && e.toPort == toPort);
    _changed();
  }

  void _select(String? id) {
    for (final c in _ctl.values) {
      c.dispose();
    }
    _ctl.clear();
    setState(() => _selected = id);
  }

  // ---------- geometry ----------

  _TypeInfo? _typeOf(_DfNode n) => _types[n.type];
  List<String> _ins(_DfNode n) => _typeOf(n)?.ins(n.cfg) ?? const [];
  List<String> _outs(_DfNode n) => _typeOf(n)?.outs(n.cfg) ?? const [];

  Offset _pin(_DfNode n, String port, bool out) {
    final ins = _ins(n);
    final i = out ? ins.length + _outs(n).indexOf(port) : ins.indexOf(port);
    // pins sit inside the block's edges (where a pointer can reach them)
    return n.pos + Offset(out ? _blockW - _pinR - 1 : _pinR + 1, _headH + i * _rowH + _rowH / 2);
  }

  /// The input pin near [p] (canvas units).
  (String, String)? _inputAt(Offset p) {
    for (final n in _nodes.values) {
      for (final port in _ins(n)) {
        if ((_pin(n, port, false) - p).distance < 12) return (n.id, port);
      }
    }
    return null;
  }

  Offset _toCanvas(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  // ---------- view ----------

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Container(
      decoration: BoxDecoration(
        color: WyStyle.field,
        border: Border.all(color: WyStyle.line),
        boxShadow: WyStyle.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(
            child:
                _loading
                    ? const Center(child: Text('Loading…', style: WyStyle.formLabel))
                    : _error != null
                    ? Center(child: Text(_error!, style: WyStyle.formLabel.copyWith(color: WyStyle.error)))
                    : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 190, child: _palette()),
                        Container(width: 1, color: WyStyle.line),
                        Expanded(child: _canvas()),
                        Container(width: 1, color: WyStyle.line),
                        SizedBox(width: 290, child: _properties()),
                      ],
                    ),
          ),
        ],
      ),
    ),
  );

  Widget _header() => Container(
    height: 38,
    color: WyStyle.tabBar,
    padding: const EdgeInsets.only(left: 14, right: 6),
    child: Row(
      children: [
        Text('Dataflow: ${widget.root}/', style: WyStyle.tab.copyWith(fontSize: 14)),
        if (_isNew)
          SizedBox(
            width: 160,
            child: _FieldBox(
              child: TextField(
                controller: _idField,
                style: WyStyle.input,
                cursorColor: WyStyle.accent,
                decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: 'name'),
                onChanged: (_) => _scheduleCheck(),
              ),
            ),
          )
        else
          Text(widget.id!, style: WyStyle.tab.copyWith(fontSize: 14, color: Colors.white)),
        const SizedBox(width: 12),
        if (_state.isNotEmpty) Text(_state, style: WyStyle.formLabel),
        const SizedBox(width: 12),
        Expanded(
          child: Tooltip(
            message: _check,
            child: Text(
              _ok == null ? '' : (_ok! ? '✓ checks' : '✗ $_check'),
              overflow: TextOverflow.ellipsis,
              style: WyStyle.formLabel.copyWith(color: _ok == false ? WyStyle.error : WyStyle.accent),
            ),
          ),
        ),
        if (_deployed.isNotEmpty) ...[Text(_deployed, style: WyStyle.formLabel), const SizedBox(width: 10)],
        SizedBox(
          width: 90,
          child: _Button(
            label: _deploying ? 'Deploying…' : (_dirty ? 'Deploy *' : 'Deploy'),
            onTap: _deploying || _ok != true ? null : _deploy,
          ),
        ),
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close, size: 18, color: WyStyle.text),
          onPressed: widget.onClose,
        ),
      ],
    ),
  );

  Widget _palette() {
    final byCat = <String, List<_TypeInfo>>{};
    for (final t in _types.values) {
      byCat.putIfAbsent(t.category, () => []).add(t);
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final e in byCat.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text(e.key, style: WyStyle.formLabel.copyWith(color: WyStyle.placeholder)),
          ),
          for (final t in e.value)
            Draggable<String>(
              data: t.type,
              feedback: Material(
                color: WyStyle.selected,
                child: Padding(padding: const EdgeInsets.all(6), child: Text(t.type, style: WyStyle.label)),
              ),
              child: Tooltip(
                message: t.description,
                waitDuration: const Duration(milliseconds: 500),
                child: InkWell(
                  // a click adds it in the middle of what is shown
                  onTap: () => _add(t.type, (const Offset(300, 200) - _pan) / _zoom),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    child: Text(t.type, style: WyStyle.label),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _canvas() => Focus(
    focusNode: _focus,
    onKeyEvent: (_, e) {
      if (e is KeyDownEvent &&
          (e.logicalKey == LogicalKeyboardKey.delete || e.logicalKey == LogicalKeyboardKey.backspace) &&
          _selected != null) {
        _remove(_selected!);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: DragTarget<String>(
      onAcceptWithDetails: (d) => _add(d.data, _toCanvas(d.offset)),
      builder:
          (context, _, _) => Listener(
            onPointerSignal: (s) {
              if (s is PointerScrollEvent) {
                setState(() => _zoom = (_zoom * (s.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(0.3, 2.5));
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _focus.requestFocus();
                _select(null);
              },
              onPanUpdate: (d) => setState(() => _pan += d.delta),
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: _pan.dx,
                      top: _pan.dy,
                      child: Transform.scale(
                        scale: _zoom,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          key: _canvasKey,
                          width: _canvasSize,
                          height: _canvasSize,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(child: CustomPaint(painter: _WirePainter(this))),
                              for (final n in _nodes.values) _block(n),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_nodes.isEmpty)
                      const Center(
                        child: Text('Drag a block here from the list on the left', style: WyStyle.formLabel),
                      ),
                  ],
                ),
              ),
            ),
          ),
    ),
  );

  Widget _pinDot(bool linked) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: linked ? WyStyle.accent : WyStyle.field,
      border: Border.all(color: WyStyle.accent),
    ),
  );

  Widget _block(_DfNode n) {
    final selected = n.id == _selected;
    final ins = _ins(n), outs = _outs(n);
    return Positioned(
      left: n.pos.dx,
      top: n.pos.dy,
      width: _blockW,
      child: GestureDetector(
        onTap: () {
          _focus.requestFocus();
          _select(n.id);
        },
        child: Container(
          decoration: BoxDecoration(
            color: WyStyle.panel,
            border: Border.all(color: selected ? WyStyle.accent : WyStyle.line, width: selected ? 2 : 1),
            boxShadow: WyStyle.shadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // the header moves the block
              GestureDetector(
                onPanStart: (_) => _select(n.id),
                onPanUpdate: (d) => setState(() => n.pos += d.delta),
                onPanEnd: (_) => _changed(),
                child: Container(
                  height: _headH - (selected ? 2 : 1),
                  color: _typeOf(n) == null ? WyStyle.error.withValues(alpha: 0.4) : WyStyle.selected,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${n.id}  ·  ${n.type}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WyStyle.label.copyWith(color: Colors.white),
                  ),
                ),
              ),
              for (final p in ins)
                SizedBox(
                  height: _rowH,
                  child: Row(
                    children: [
                      GestureDetector(
                        key: ValueKey('in:${n.id}.$p'),
                        // a double click unlinks it (DSA)
                        onDoubleTap: () => _unlink(n.id, p),
                        child: _pinDot(_edges.any((e) => e.to == n.id && e.toPort == p)),
                      ),
                      const SizedBox(width: 5),
                      Text(p, style: WyStyle.label),
                    ],
                  ),
                ),
              for (final p in outs)
                SizedBox(
                  height: _rowH,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(p, style: WyStyle.label),
                      const SizedBox(width: 5),
                      GestureDetector(
                        key: ValueKey('out:${n.id}.$p'),
                        // drag to an input pin to link
                        onPanStart:
                            (d) => setState(() {
                              _wireFrom = (n.id, p);
                              _wireTo = _toCanvas(d.globalPosition);
                            }),
                        onPanUpdate: (d) => setState(() => _wireTo = _toCanvas(d.globalPosition)),
                        onPanEnd: (_) {
                          final to = _wireTo == null ? null : _inputAt(_wireTo!);
                          final from = _wireFrom!;
                          setState(() {
                            _wireFrom = null;
                            _wireTo = null;
                          });
                          if (to != null) _link(from.$1, from.$2, to.$1, to.$2);
                        },
                        child: _pinDot(_edges.any((e) => e.from == n.id && e.fromPort == p)),
                      ),
                    ],
                  ),
                ),
              if (ins.isEmpty && outs.isEmpty) const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- properties ----------

  TextEditingController _controller(String name, String text) =>
      _ctl.putIfAbsent(name, () => TextEditingController(text: text));

  Widget _properties() {
    final n = _selected == null ? null : _nodes[_selected];
    return ListView(padding: const EdgeInsets.all(12), children: n == null ? _flowProps() : _nodeProps(n));
  }

  List<Widget> _flowProps() {
    final desc = _controller('description', _text(_rest['description']));
    return [
      const Text('Flow', style: WyStyle.menu),
      const SizedBox(height: 8),
      _propRow(
        'Description',
        _textField(desc, (t) {
          if (t.isEmpty) {
            _rest.remove('description');
          } else {
            _rest['description'] = VStr(t);
          }
          _changed();
        }),
      ),
      _propRow(
        'Enabled',
        _BoolField(
          value: _rest['enabled'] != const VBool(false),
          onChanged: (on) {
            _rest['enabled'] = VBool(on);
            _changed();
          },
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Drag a block from the list (or click it). Drag from an output pin (right) to an input pin (left) '
        'to link them; double-click an input pin to unlink it. Drag a block by its header; drag the '
        'background to move the view, scroll to zoom. Select a block to edit it; Delete removes it. '
        'Deploy sends the flow as a new version.',
        style: WyStyle.formLabel,
      ),
    ];
  }

  Widget _propRow(String label, Widget field, {String? help}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(message: help ?? '', child: Text(label, style: WyStyle.formLabel)),
        const SizedBox(height: 3),
        field,
      ],
    ),
  );

  Widget _textField(TextEditingController c, ValueChanged<String> onChanged, {bool area = false, String? hint}) =>
      _FieldBox(
        height: area ? 80 : 26,
        child: TextField(
          controller: c,
          style: WyStyle.input,
          cursorColor: WyStyle.accent,
          maxLines: area ? 4 : 1,
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: WyStyle.input.copyWith(color: WyStyle.placeholder),
          ),
          onChanged: (t) => onChanged(t.trim()),
        ),
      );

  List<Widget> _nodeProps(_DfNode n) {
    final t = _typeOf(n);
    final name = _controller('\u0000name', n.id);
    return [
      Text(n.type, style: WyStyle.menu),
      if (t != null)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(t.description, style: WyStyle.formLabel)),
      const SizedBox(height: 10),
      _propRow(
        'Name',
        _FieldBox(
          child: TextField(
            controller: name,
            style: WyStyle.input,
            cursorColor: WyStyle.accent,
            decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
            onSubmitted: (v) => _rename(n.id, v.trim()),
          ),
        ),
        help: 'Letters, digits and _ ; Enter renames it',
      ),
      for (final p in t?.params ?? const <_ParamInfo>[])
        _propRow(p.required ? '${p.name} *' : p.name, _paramField(n, p), help: p.description),
      const SizedBox(height: 12),
      _Button(label: 'Delete Block', onTap: () => _remove(n.id)),
    ];
  }

  void _setCfg(_DfNode n, String name, Value? v) {
    if (v == null) {
      n.cfg.remove(name);
    } else {
      n.cfg[name] = v;
    }
    _changed();
  }

  Widget _paramField(_DfNode n, _ParamInfo p) {
    final cur = n.cfg[p.name];
    if (p.choices.isNotEmpty) {
      return _EnumField(
        value: cur == null ? p.defaultValue : _text(cur),
        options: p.choices,
        onChanged: (v) => _setCfg(n, p.name, VStr(v)),
      );
    }
    if (p.type == 'bool') {
      return _BoolField(value: cur is VBool ? cur.v : null, onChanged: (on) => _setCfg(n, p.name, VBool(on)));
    }
    final text = switch (p.type) {
      'array' => _texts(cur).join(', '),
      'map' || 'dynamic' when cur != null && cur is! VStr => jsonEncode(_toJson(cur)),
      _ => cur == null ? '' : formatValue(cur, null),
    };
    final c = _controller(p.name, cur == null ? '' : text);
    return _textField(
      c,
      (t) {
        if (t.isEmpty) return _setCfg(n, p.name, null);
        switch (p.type) {
          case 'number':
            final i = int.tryParse(t), d = double.tryParse(t);
            if (i != null) return _setCfg(n, p.name, VInt(i));
            if (d != null) return _setCfg(n, p.name, VFloat(d));
          case 'array':
            return _setCfg(n, p.name, VArray([for (final s in t.split(',')) VStr(s.trim())]));
          case 'map' || 'dynamic':
            try {
              return _setCfg(n, p.name, _fromJson(jsonDecode(t)));
            } catch (_) {
              if (p.type == 'dynamic') return _setCfg(n, p.name, VStr(t));
            }
          default:
            return _setCfg(n, p.name, VStr(t));
        }
      },
      area: p.editor == 'textarea',
      hint:
          p.defaultValue ??
          (p.type == 'array'
              ? 'a, b'
              : p.type == 'map'
              ? '{"k": 1}'
              : null),
    );
  }
}

/// Wires: an S-curve from each output pin to the input pin it feeds, and
/// the one being drawn.
class _WirePainter extends CustomPainter {
  final _DataflowWindowState s;
  _WirePainter(this.s);

  Path _curve(Offset a, Offset b) {
    final dx = math.max(40.0, (b.dx - a.dx).abs() / 2);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final wire =
        Paint()
          ..color = WyStyle.accent
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke;
    for (final e in s._edges) {
      final a = s._nodes[e.from], b = s._nodes[e.to];
      if (a == null || b == null) continue;
      canvas.drawPath(_curve(s._pin(a, e.fromPort, true), s._pin(b, e.toPort, false)), wire);
    }
    if (s._wireFrom case (final id, final port)) {
      final a = s._nodes[id];
      if (a != null && s._wireTo != null) {
        canvas.drawPath(_curve(s._pin(a, port, true), s._wireTo!), wire..color = Colors.white70);
      }
    }
  }

  @override
  bool shouldRepaint(_WirePainter old) => true;
}
