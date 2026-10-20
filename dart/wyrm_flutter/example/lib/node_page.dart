// One node in full: its `~meta` (profile, type, unit, writable, cfg, attr)
// and its actions; an action opens a form built from its params and shows
// what the invoke stream returns.

import 'package:flutter/material.dart';
import 'package:wyrm_flutter/wyrm_flutter.dart';

class NodePage extends StatefulWidget {
  final WyrmApi api;
  final String nodeKey;
  const NodePage({super.key, required this.api, required this.nodeKey});

  @override
  State<NodePage> createState() => _NodePageState();
}

class _NodePageState extends State<NodePage> {
  late Future<NodeMeta> _meta = widget.api.meta(widget.nodeKey);

  void _reload() => setState(() => _meta = widget.api.meta(widget.nodeKey));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.nodeKey, style: const TextStyle(fontSize: 15)),
          actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
        ),
        body: FutureBuilder<NodeMeta>(
          future: _meta,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final m = snap.data;
            if (m == null) return const Center(child: CircularProgressIndicator());
            final actions = (m.actions ?? {}).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (m.ty != null && !m.isContainer)
                Card(
                  child: ListTile(
                    title: const Text('Value'),
                    trailing: WyrmValue(api: widget.api, nodeKey: widget.nodeKey, meta: m),
                  ),
                ),
              _section(context, 'Node', {
                'profile': m.profileName,
                'type': m.ty?.wireName,
                'unit': switch (m.unit) { TText(:final text) => text, null => null, final u => '$u' },
                'writable': m.writable?.wireName,
                'invokable': m.invokable?.wireName,
                'display': m.displayName,
                'children': m.childrenCount?.toString() ?? m.children?.length.toString(),
                'rev': m.rev?.toString(),
                'enum': m.enumValues?.join(', '),
              }),
              if (m.cfg?.isNotEmpty ?? false)
                _section(context, 'cfg', {for (final e in m.cfg!.entries) e.key: formatValue(e.value, null)}),
              if (m.attr?.isNotEmpty ?? false)
                _section(context, 'attr', {for (final e in m.attr!.entries) e.key: formatValue(e.value, null)}),
              const SizedBox(height: 8),
              Text('Actions', style: Theme.of(context).textTheme.titleMedium),
              if (actions.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('none')),
              for (final a in actions)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.play_arrow),
                    title: Text(a.key),
                    subtitle: Text([
                      if (a.value.level != null) 'level ${a.value.level!.wireName}',
                      if (a.value.params.isNotEmpty) 'params: ${a.value.params.keys.join(', ')}',
                    ].join(' · ')),
                    onTap: () => _run(context, a.key, a.value),
                  ),
                ),
            ]);
          },
        ),
      );

  Widget _section(BuildContext context, String title, Map<String, String?> rows) {
    final shown = rows.entries.where((e) => e.value != null).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final e in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 120, child: Text(e.key, style: const TextStyle(color: Colors.grey))),
                Expanded(child: SelectableText(e.value!)),
              ]),
            ),
        ]),
      ),
    );
  }

  Future<void> _run(BuildContext context, String name, ActionMeta a) async {
    final args = a.params.isEmpty ? <String, Value>{} : await _form(context, name, a);
    if (args == null || !context.mounted) return;
    final out = <String>[];
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        if (out.isEmpty && error == null) {
          widget.api.invoke(widget.nodeKey, name, VMap(args)).listen(
                (v) => setD(() => out.add(_show(v))),
                onError: (Object e) => setD(() => error = '$e'),
                onDone: () => setD(() => out.isEmpty && error == null ? out.add('done') : null),
              );
        }
        return AlertDialog(
          title: Text('$name — result'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (error != null) Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                for (final o in out) SelectableText(o),
                if (out.isEmpty && error == null) const LinearProgressIndicator(),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        );
      }),
    );
    _reload();
  }

  /// A value as readable text, maps and arrays indented.
  String _show(Value v, [String pad = '']) => switch (v) {
        VMap(:final v) => v.entries.map((e) => '$pad${e.key}: ${_nested(e.value, pad)}').join('\n'),
        VArray(:final v) => v.map((e) => '$pad- ${_nested(e, pad)}').join('\n'),
        _ => formatValue(v, null),
      };

  String _nested(Value v, String pad) =>
      v is VMap || v is VArray ? '\n${_show(v, '$pad  ')}' : formatValue(v, null);

  /// The action's params as a form; `null` when cancelled.
  Future<Map<String, Value>?> _form(BuildContext context, String name, ActionMeta a) {
    final ctl = <String, TextEditingController>{};
    final bools = <String, bool>{};
    final enums = <String, String?>{};
    for (final e in a.params.entries) {
      final p = e.value;
      final d = p.defaultValue;
      if (p.ty == TypeCode.bool_) {
        bools[e.key] = d is VBool ? d.v : false;
      } else if (p.enumValues != null) {
        enums[e.key] = d is VStr ? d.v : p.enumValues!.first;
      } else {
        ctl[e.key] = TextEditingController(text: d == null || d is VNull ? '' : formatValue(d, null));
      }
    }
    return showDialog<Map<String, Value>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(name),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final e in a.params.entries)
                  if (bools.containsKey(e.key))
                    SwitchListTile(
                      title: Text(e.key),
                      value: bools[e.key]!,
                      onChanged: (v) => setD(() => bools[e.key] = v),
                    )
                  else if (enums.containsKey(e.key))
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(labelText: e.key),
                      initialValue: enums[e.key],
                      items: [for (final o in e.value.enumValues!) DropdownMenuItem(value: o, child: Text(o))],
                      onChanged: (v) => setD(() => enums[e.key] = v),
                    )
                  else
                    TextField(
                      controller: ctl[e.key],
                      decoration: InputDecoration(
                        labelText: '${e.key}${e.value.required == true ? ' *' : ''}',
                        helperText: e.value.ty?.wireName,
                      ),
                    ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final out = <String, Value>{};
                for (final e in a.params.entries) {
                  final k = e.key;
                  if (bools.containsKey(k)) {
                    out[k] = VBool(bools[k]!);
                  } else if (enums.containsKey(k)) {
                    if (enums[k] != null) out[k] = VStr(enums[k]!);
                  } else {
                    final t = ctl[k]!.text.trim();
                    if (t.isEmpty) continue;
                    out[k] = e.value.ty == TypeCode.number
                        ? (int.tryParse(t) != null ? VInt(int.parse(t)) : VFloat(double.tryParse(t) ?? 0))
                        : VStr(t);
                  }
                }
                Navigator.pop(ctx, out);
              },
              child: const Text('Run'),
            ),
          ],
        ),
      ),
    );
  }
}
