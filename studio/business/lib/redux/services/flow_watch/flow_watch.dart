import 'dart:async';
import 'dart:math' as math;

import 'package:models/live_value.dart';
import 'package:models/quality.dart' as m;
import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/services/interface.dart';
import '../../../wyrm/mappers/flow_fields.dart';
import '../../../wyrm/mappers/values.dart';

/// What [FlowWatchService] tells its listener.
abstract class FlowWatchServiceListener {
  /// The port values that changed since the last call (keys of [portKey]:
  /// `in:<node>.<port>`, `out:<node>.<port>`, `param:<node>.<p>`), at most
  /// every [FlowWatchService.flushEvery]. With [reset] the values held
  /// before are dropped first (a snapshot, another flow, the watch ended
  /// for good).
  void onPorts(Map<String, LiveValue> changed, {required bool reset});

  /// The broker refused the watch for good ([status]: `permission_denied`
  /// when the caller cannot read every source of the flow, `not_supported`
  /// or `not_found` when it has no watch). Null: following again.
  void onRefused(Status? status);

  /// The flow was deployed again as [version]; the stream opens again.
  void onRedeployed(int? version);
}

/// The live values of one deployed flow: `dataflows/<id>` ▸ `watch
/// {max_hz}` (ADR 0038 §3), a stream of rows — a snapshot, then changes, a
/// heartbeat when nothing changed — that ends after its `ttl`, on a
/// redeploy or when the caller goes; then it is opened again.
///
/// A broker without the action (`not_supported`, `not_found`), or one that
/// refuses it (`permission_denied`, `invalid_parameter`), ends it for this
/// flow: the editor shows the values of the definition, and says so only
/// when the caller may not read the flow's sources. `busy` (too many
/// watches of others) is tried again like a failure.
/// Other failures open it again after a back-off that doubles up to
/// [retryMax], so a broker that ends every stream at once is never asked in
/// a loop.
class FlowWatchService extends DisposableServiceInterface {
  FlowWatchService({
    required this._listener,
    this.flushEvery = const Duration(milliseconds: 50),
    this.retryFirst = const Duration(seconds: 1),
    this.retryMax = const Duration(seconds: 30),
    this.maxHz = 4,
  });

  final FlowWatchServiceListener _listener;

  /// How often changed values are handed to the listener: values repaint
  /// in batches, never once per sample.
  final Duration flushEvery;
  final Duration retryFirst;
  final Duration retryMax;

  /// Rows per node per second the broker sends at most.
  final int maxHz;

  WyrmApi? _api;
  String? _flow;
  StreamSubscription<Value>? _sub;
  Timer? _retry;
  Timer? _flush;
  var _failures = 0;
  var _refused = false;
  var _reset = false;
  final _pending = <String, LiveValue>{};

  /// The flow followed now (`wy/<site>/dataflows/<id>`), if any.
  String? get flow => _flow;

  /// The broker has no watch for [flow] or refused it; nothing is retried.
  bool get refused => _refused;

  /// Uses [api]; opens the watch of the flow followed, if any.
  void attach(WyrmApi api) {
    _close();
    _api = api;
    if (_flow != null && !_refused) {
      _open();
    }
  }

  /// Follows [flow] (a full `dataflows/<id>` key), or none for null.
  void follow(String? flow) {
    if (flow == _flow) {
      return;
    }
    _close();
    _flow = flow;
    if (_refused) {
      _listener.onRefused(null);
    }
    _refused = false;
    _failures = 0;
    _pending.clear();
    _reset = true;
    _schedule();
    if (flow != null) {
      _open();
    }
  }

  void _open() {
    final api = _api;
    final flow = _flow;
    if (api == null || flow == null) {
      return;
    }
    var rows = 0;
    _sub = api
        .invoke(flow, 'watch', Value.from({'max_hz': maxHz}))
        .listen(
          (r) {
            rows++;
            _onRow(r);
          },
          onError: (Object e) {
            if (e is WyrmException && _final(e.status.known)) {
              logger.fine('watch $flow: ${e.status.name}');
              _refused = true;
              unawaited(_sub?.cancel());
              _sub = null;
              _listener.onRefused(e.status.known);
              return;
            }
            logger.fine('watch $flow: $e');
            _again(rows);
          },
          onDone: () => _again(rows),
          cancelOnError: true,
        );
  }

  static bool _final(Status? s) =>
      s == Status.notSupported ||
      s == Status.notFound ||
      s == Status.invalidParameter ||
      s == Status.permissionDenied;

  /// Opens the stream again: soon after one that carried rows, later and
  /// later after ones that ended empty.
  void _again(int rows) {
    _sub = null;
    if (_flow == null || _refused) {
      return;
    }
    _failures = rows > 0 ? 0 : _failures + 1;
    final wait = Duration(
      milliseconds: math.min(
        retryMax.inMilliseconds,
        retryFirst.inMilliseconds * (1 << math.min(_failures, 16)),
      ),
    );
    _retry?.cancel();
    _retry = Timer(rows > 0 ? retryFirst : wait, () {
      _retry = null;
      if (_sub == null) {
        _open();
      }
    });
  }

  void _onRow(Value r) {
    if (r['redeployed'] case final v?) {
      // The last row of a stream: the values belong to another version.
      _pending.clear();
      _reset = true;
      _schedule();
      _listener.onRedeployed(integer(v));
      return;
    }
    final t = time(r['t']) ?? DateTime.now().toUtc();
    if (boolean(r['snapshot']) ?? false) {
      _pending.clear();
      _reset = true;
    }
    flowRowPorts(r, t, _pending);
    _schedule();
  }

  void _schedule() => _flush ??= Timer(flushEvery, flush);

  /// Hands what changed to the listener now.
  void flush() {
    _flush?.cancel();
    _flush = null;
    if (_pending.isEmpty && !_reset) {
      return;
    }
    final changed = Map.of(_pending);
    final reset = _reset;
    _pending.clear();
    _reset = false;
    _listener.onPorts(changed, reset: reset);
  }

  void _close() {
    unawaited(_sub?.cancel());
    _sub = null;
    _retry?.cancel();
    _retry = null;
  }

  /// Stops the watch and forgets the session; the flow followed is kept.
  void detach() {
    _close();
    _api = null;
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    detach();
    _flush?.cancel();
    _flush = null;
  }
}

/// The port values of one row of `watch` or `preview` (ADR 0038 §3): each
/// node's `in` and `out` samples and its `params`, keyed by [portKey], put
/// into [into].
void flowRowPorts(Value r, DateTime t, Map<String, LiveValue> into) {
  if (r['nodes'] case VMap(:final v)) {
    for (final MapEntry(key: node, value: ports) in v.entries) {
      for (final dir in const ['in', 'out']) {
        if (ports[dir] case VMap(:final v)) {
          for (final MapEntry(key: port, value: s) in v.entries) {
            into[portKey(dir, node, port)] = flowSample(s, t);
          }
        }
      }
      if (ports['params'] case VMap(:final v)) {
        for (final MapEntry(key: p, value: x) in v.entries) {
          into[portKey('param', node, p)] = LiveValue(
            time: t,
            value: toDart(x),
          );
        }
      }
    }
  }
}

/// A sample `[v, q]` of a row, q a quality code or name.
LiveValue flowSample(Value s, DateTime t) {
  final (v, q) = switch (s) {
    VArray(:final v) when v.length >= 2 => (v[0], v[1]),
    VArray(:final v) when v.length == 1 => (v[0], null),
    _ => (s, null),
  };
  final code = integer(q);
  final quality = switch (q) {
    VStr(:final v) => Quality.fromName(v),
    _ => code == null ? null : Quality.fromCode(code),
  };
  return LiveValue(
    time: t,
    value: toDart(v),
    quality: switch (quality) {
      Quality.uncertain => m.Quality.uncertain,
      Quality.bad => m.Quality.bad,
      _ => m.Quality.good,
    },
  );
}
