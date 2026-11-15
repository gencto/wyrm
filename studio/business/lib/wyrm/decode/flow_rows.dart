import 'package:models/live_value.dart';
import 'package:models/port_side.dart';
import 'package:models/quality.dart' as m;
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';
import 'decoded.dart';

/// The key of a live value of [node] in `flowEditor.ports` and
/// `flowEditor.previewPorts`: `<side>:<node>.<port>` (`in:avg.in`,
/// `out:avg.out`, `param:avg.size_s`).
String portKey(PortSide side, String node, String port) =>
    '${side.prefix}:$node.$port';

/// The side and the port of [key] ([portKey]) of [node]; null when it is
/// no key of that node.
(PortSide, String)? sideOfKey(String key, String node) {
  for (final side in PortSide.values) {
    final prefix = portKey(side, node, '');
    if (key.startsWith(prefix)) {
      return (side, key.substring(prefix.length));
    }
  }
  return null;
}

/// One row of `dataflows/<id>` ▸ `watch` or `dataflows` ▸ `preview` (ADR
/// 0038 §3, spec 06): a snapshot or the changes since the row before, a
/// heartbeat, or the last row of a stream ended by a redeploy.
final class FlowRow {
  const FlowRow({
    required this.t,
    this.snapshot = false,
    this.redeployed = false,
    this.version,
    this.ports = const {},
    this.sinks = const {},
  });

  /// When the engine made it.
  final DateTime t;

  /// Every value of the flow, not only the changed ones: the values held
  /// before go.
  final bool snapshot;

  /// The flow was deployed again ([version]): the values belong to
  /// another version.
  final bool redeployed;
  final int? version;

  /// Each node's `in` and `out` samples and its `params`, by [portKey].
  final Map<String, LiveValue> ports;

  /// What a sink of a preview WOULD write, by node (`sinks`).
  final Map<String, LiveValue> sinks;
}

const _shape = 'flow row';

/// A row of `watch` or `preview`; [now] stands for a row with no `t`.
/// [Invalid] when the row is no map, or `nodes`/`sinks` are not a map and
/// an array. A node whose ports are of another shape is left out with a
/// warning.
Decoded<FlowRow> flowRowOf(Value r, {required DateTime now}) {
  if (r is! VMap) {
    return const Invalid(_shape, '', 'not a map');
  }
  if (r['redeployed'] case final v? when v is! VNull) {
    return Valid(FlowRow(t: now, redeployed: true, version: integer(v)));
  }
  final t = time(r['t']) ?? now;
  final ports = <String, LiveValue>{};
  switch (r['nodes']) {
    case null || VNull():
      break;
    case VMap(:final v):
      for (final MapEntry(key: node, value: p) in v.entries) {
        if (p is! VMap) {
          decodeLog.warning('$_shape: nodes.$node: not a map');
          continue;
        }
        for (final side in const [PortSide.input, PortSide.output]) {
          if (p[side.prefix] case VMap(:final v)) {
            for (final MapEntry(key: port, value: s) in v.entries) {
              ports[portKey(side, node, port)] = flowSample(s, t);
            }
          }
        }
        if (p['params'] case VMap(:final v)) {
          for (final MapEntry(key: name, value: x) in v.entries) {
            ports[portKey(PortSide.param, node, name)] = LiveValue(
              time: t,
              value: toDart(x),
            );
          }
        }
      }
    default:
      return const Invalid(_shape, 'nodes', 'not a map');
  }
  final sinks = <String, LiveValue>{};
  switch (r['sinks']) {
    case null || VNull():
      break;
    case VArray(:final v):
      for (final (i, s) in v.indexed) {
        switch (s['node']) {
          case VStr(:final v):
            sinks[v] = LiveValue(time: t, value: toDart(s['value']));
          default:
            decodeLog.warning('$_shape: sinks[$i].node: missing');
        }
      }
    default:
      return const Invalid(_shape, 'sinks', 'not an array');
  }
  return Valid(
    FlowRow(
      t: t,
      snapshot: boolean(r['snapshot']) ?? false,
      ports: ports,
      sinks: sinks,
    ),
  );
}

/// A sample `[v, q]` of a row, q a quality code or name; a bare value is
/// good.
LiveValue flowSample(Value s, DateTime t) {
  final (v, q) = switch (s) {
    VArray(:final v) when v.length >= 2 => (v[0], v[1]),
    VArray(:final v) when v.length == 1 => (v[0], null),
    _ => (s, null),
  };
  return LiveValue(
    time: t,
    value: toDart(v),
    quality: switch (Quality.fromValue(q)) {
      Quality.uncertain => m.Quality.uncertain,
      Quality.bad => m.Quality.bad,
      _ => m.Quality.good,
    },
  );
}

/// The arguments of `watch {max_hz}`.
Value watchArgs(int maxHz) => VMap({'max_hz': VInt(maxHz)});

/// What an event output (`sent`, `ok`, `error`, ADR 0040 §2) last sent:
/// `{event, id, code?, message?}`.
final class FlowEvent {
  const FlowEvent({this.code, this.message});

  /// An error's code (`busy`, a status name or number), as it came.
  final Object? code;

  /// An error's message; null when it sent none.
  final String? message;
}

/// The event a live value of an event output holds; null when it holds
/// none (no map, or neither `event` nor `code`).
FlowEvent? flowEventOf(Object? value) => switch (value) {
  final Map<String, Object?> m when m['event'] != null || m['code'] != null =>
    FlowEvent(
      code: m['code'],
      message: switch (m['message']) {
        final String s when s.isNotEmpty => s,
        _ => null,
      },
    ),
  _ => null,
};
