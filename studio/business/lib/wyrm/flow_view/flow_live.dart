import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/flow_frame.dart';
import 'package:models/live_value.dart';

import '../mappers/block_cfg.dart';
import '../mappers/flow_blocks.dart';
import '../mappers/flow_fields.dart';
import '../mappers/flow_mapper.dart';

/// A value with no time: what the definition says a field holds.
final typedTime = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);

/// The value a `publish` block of flow [flow] publishes
/// (`dataflows/<flow>/nodes/<node>`), null for any other block.
String? publishedKey(String root, String flow, FlowBlock b) =>
    switch (b.cfgNode) {
      final n? when b.type.known == KnownBlock.publish && flow.isNotEmpty =>
        '$root/dataflows/$flow/nodes/$n',
      _ => null,
    };

/// The keys of the site's live values the blocks of [d] read: the points a
/// block reads or writes, and what the publish blocks of [d] and of the
/// [deployed] version last published. Only these are read from the live
/// values, so a change of any other key changes nothing the blocks show.
List<String> liveKeysOf(
  String root,
  String flow,
  FlowDraft? d,
  FlowDraft? deployed,
) => {
  for (final b in d?.blocks.values ?? const <FlowBlock>[]) ...[
    if (isPoint(b.type))
      if (pointOf(b) case final k?) fullKey(root, k),
    ?publishedKey(root, flow, b),
  ],
  for (final b in deployed?.blocks.values ?? const <FlowBlock>[])
    ?publishedKey(root, flow, b),
}.toList();

/// The live values of the editor's blocks (spec §3, §12): the preview's,
/// the deployed version's watch, the tree's values of the points, and what
/// a field holds when no sample of its own came yet.
final class FlowLive {
  const FlowLive({
    required this.root,
    required this.flow,
    required this.draft,
    required this.deployed,
    required this.frames,
    required this.fields,
    required this.ports,
    required this.previewPorts,
    required this.values,
    required this.previewing,
    required this.differs,
  });

  /// `wy/<site>`.
  final String root;

  /// The flow's id ('' while a new flow has none).
  final String flow;

  /// What the canvas shows: the flow, or the inside of a custom block.
  final FlowDraft? draft;
  final FlowDraft? deployed;
  final IList<FlowFrame> frames;

  /// Every block's fields ([fieldsOf]), by block id.
  final Map<String, List<FlowField>> fields;

  /// The watch's values of the deployed version (keys of [portKey]).
  final IMap<String, LiveValue> ports;

  /// The preview's values.
  final IMap<String, LiveValue> previewPorts;

  /// The site's live values of [liveKeysOf], by key.
  final Map<String, LiveValue?> values;

  /// The draft's values come from its preview (`previewingOf`).
  final bool previewing;

  /// The flow differs from the deployed version.
  final bool differs;

  /// The values the blocks show now: the preview's or the watch's.
  IMap<String, LiveValue> get shown => previewing ? previewPorts : ports;

  /// The values of [b]'s fields, by key of [portKey].
  ///
  /// While the draft runs as a preview ([previewing]) every block reads the
  /// preview's values; else a block the deployed version has unchanged
  /// reads the watch's, and the point a `subscribe` reads or a `set` writes
  /// its tree value.
  ///
  /// The engine records a port only from its first sample after the watch
  /// or the preview opened (ADR 0038 §6), so a slow point or a value sent
  /// once at start shows nothing there. What such a field holds is still
  /// known, and is shown: an input bound by a wire of the draft holds the
  /// value of its source field; a field's echo (a variable's `Value`, a
  /// parameter) what comes into it, else its typed value; an input's echo
  /// what came in.
  LiveValue? Function(String) of(FlowBlock b, {int hops = 0}) {
    final d = draft;
    final inside = frames.isNotEmpty;
    // Inside a custom block the nodes run under an instance: their rows
    // are `<instance>/<inner>`; opened from the palette they do not run.
    final eid = engineIdOf(frames, b.id);
    final dep = inside ? null : deployed?.blocks[b.id];
    final same = inside
        ? !differs
        : dep != null && dep.type == b.type && sameCfg(dep.cfg, b.cfg);
    final ports = eid == null
        ? null
        : (previewing ? previewPorts : (same ? this.ports : null));
    final point = isPoint(b.type) ? pointOf(b) : null;
    final pub = previewing || !same || inside
        ? null
        : publishedKey(root, flow, b);
    final tree = pub != null
        ? values[pub]
        : (point == null ? null : values[fullKey(root, point)]);
    final inPrefix = portKey(PortSide.input, b.id, '');
    final outPrefix = portKey(PortSide.output, b.id, '');
    final instance = d != null && isInstance(b.type);
    LiveValue? look(String k) {
      final at = eid == null ? null : engineKeyOf(d, b, eid, k);
      final v = at == null ? null : ports?[at];
      if (v != null) {
        return v;
      }
      if (tree != null &&
          (k == portKey(PortSide.output, b.id, EnginePort.out.wire) &&
                  b.type.known != KnownBlock.set ||
              k == portKey(PortSide.input, b.id, EnginePort.in_.wire) &&
                  (b.type.known == KnownBlock.set ||
                      b.type.known == KnownBlock.publish))) {
        return tree;
      }
      if (d == null || hops > 6) {
        return null;
      }
      if (k.startsWith(inPrefix)) {
        final port = k.substring(inPrefix.length);
        final wire = d.edges
            .where((e) => e.to == b.id && e.toPort == port)
            .firstOrNull;
        final src = wire == null ? null : d.blocks[wire.from];
        if (wire == null || src == null) {
          // An unbound operand holds its typed constant (ADR 0038 §7).
          final f = fields[b.id]
              ?.where((f) => f.operand && f.inPort == port)
              .firstOrNull;
          // An instance's input holds its own constant, else the block's
          // default.
          final constant = f == null
              ? const JsonNull()
              : (instance
                    ? instanceValueOf(d, b, port)
                    : operandValueOf(b, port));
          return switch (constant) {
            JsonNull() => null,
            final c => LiveValue(time: typedTime, value: c.raw),
          };
        }
        return of(
          src,
          hops: hops + 1,
        )(portKey(PortSide.output, src.id, wire.fromPort));
      }
      if (!k.startsWith(outPrefix)) {
        return null;
      }
      final port = k.substring(outPrefix.length);
      if (!previewing && same) {
        // An output wired straight into a publish block sent what that
        // block last published.
        for (final e in deployed?.edges ?? const IListConst<FlowEdge>([])) {
          final to = deployed?.blocks[e.to];
          final key = to == null ? null : publishedKey(root, flow, to);
          if (e.from == b.id && e.fromPort == port && key != null) {
            if (values[key] case final v?) {
              return v;
            }
          }
        }
      }
      final f = fields[b.id]
          ?.where((f) => f.sends(port) && f.kind != FieldKind.output)
          .firstOrNull;
      if (f == null) {
        return null;
      }
      final inPort = f.inPort;
      if (inPort != null &&
          d.edges.any((e) => e.to == b.id && e.toPort == inPort)) {
        return look(portKey(PortSide.input, b.id, inPort));
      }
      if (f.kind == FieldKind.input) {
        return inPort == null
            ? null
            : look(portKey(PortSide.input, b.id, inPort));
      }
      if (ports?[portKey(PortSide.param, b.id, f.name)] case final v?) {
        return v;
      }
      return switch (b.paramOr(f.name, f.spec?.defaultValue?.raw)) {
        JsonNull() => null,
        final typed => LiveValue(time: typedTime, value: typed.raw),
      };
    }

    return look;
  }
}
