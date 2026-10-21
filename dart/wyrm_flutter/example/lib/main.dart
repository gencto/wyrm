// Minimal WYRM tree browser. Connects either through the user gateway
// (HTTP login + WebSocket) or directly to a Zenoh endpoint through the
// wyrm-ffi library (set WYRM_FFI_LIB or bundle libwyrm_ffi with the app).
//
// Platform folders are not checked in: run `flutter create .` here once.

import 'package:flutter/material.dart';
import 'package:wyrm_ffi/wyrm_ffi.dart';
import 'package:wyrm_flutter/wyrm_flutter.dart';

import 'node_page.dart';

void main() => runApp(const MaterialApp(title: 'WYRM', home: ConnectPage()));

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _url = TextEditingController(text: 'http://127.0.0.1:8445');
  final _user = TextEditingController(text: 'admin');
  final _password = TextEditingController(text: 'wyrm-demo-1');
  final _endpoint = TextEditingController(text: 'tcp/127.0.0.1:7447');
  final _root = TextEditingController();

  /// Direct mode: hex seed of a key in `admin_keys` (`wyr keygen`), for
  /// set/invoke. Empty = read only.
  final _seed = TextEditingController();
  final _site = TextEditingController(text: 'local');
  bool _direct = false;

  /// Explorer layout (Data tree, context menu, action flyout, Metrics).
  bool _explorer = true;
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final WyrmApi api;
      // Root: the field, else the connected site (its peer sites are in
      // its sys/upstream and sys/downstream).
      var root = _root.text.trim();
      if (_direct) {
        final seed = _seed.text.trim();
        api = await WyrmFfi.open(_endpoint.text,
            seed: seed.isEmpty ? null : hexDecode(seed), site: seed.isEmpty ? null : _site.text);
        if (root.isEmpty) root = 'wy/${_site.text}';
      } else {
        final gw = await WyrmGateway.login(Uri.parse(_url.text), user: _user.text, password: _password.text);
        final me = await gw.me();
        if (me case VMap(:final v)) {
          if (v['site'] case VStr(v: final site) when root.isEmpty) root = 'wy/$site';
        }
        api = await gw.connect();
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _explorer
            ? ExplorerPage(api: api, rootKey: root)
            : TreePage(api: api, rootKey: root),
      ));
      await api.close();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('WYRM')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SwitchListTile(
            title: const Text('Direct (FFI) instead of the gateway'),
            value: _direct,
            onChanged: (v) => setState(() => _direct = v),
          ),
          if (_direct) ...[
            TextField(controller: _endpoint, decoration: const InputDecoration(labelText: 'Zenoh endpoint')),
            TextField(
                controller: _seed,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Key seed (hex, optional; empty = read only)')),
            TextField(controller: _site, decoration: const InputDecoration(labelText: 'Site')),
          ] else ...[
            TextField(controller: _url, decoration: const InputDecoration(labelText: 'Gateway URL')),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'User')),
            TextField(
                controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          ],
          TextField(
              controller: _root,
              decoration: const InputDecoration(labelText: 'Root key (empty: the connected site)')),
          SwitchListTile(
            title: const Text('Explorer layout'),
            value: _explorer,
            onChanged: (v) => setState(() => _explorer = v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _connect, child: const Text('Connect')),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      );
}

/// The explorer: the Data panel in a 333px left column, a blank stage
/// beside it.
class ExplorerPage extends StatelessWidget {
  final WyrmApi api;
  final String rootKey;
  const ExplorerPage({super.key, required this.api, required this.rootKey});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: WyStyle.panel,
        body: Row(children: [
          SizedBox(width: 333, child: WyExplorer(api: api, rootKey: rootKey)),
          Container(width: 1, color: WyStyle.line),
          Expanded(
            child: Column(children: [
              WyTabBar(
                tabs: [rootKey],
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 16, color: WyStyle.text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const Expanded(child: ColoredBox(color: Color(0xFF2B2B2B))),
            ]),
          ),
        ]),
      );
}

class TreePage extends StatelessWidget {
  final WyrmApi api;
  final String rootKey;
  const TreePage({super.key, required this.api, required this.rootKey});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(rootKey)),
        body: WyrmTree(
          api: api,
          rootKey: rootKey,
          onLeafTap: (key, child) => _write(context, key, child),
          onNodeOpen: (key, _) => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => NodePage(api: api, nodeKey: key)),
          ),
        ),
      );

  Future<void> _write(BuildContext context, String key, Child child) async {
    if (!child.meta.isWritable) return;
    final ctl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set $key'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Set'))],
      ),
    );
    if (text == null) return;
    final n = double.tryParse(text);
    try {
      await api.set(key, n != null ? VFloat(n) : VStr(text));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
