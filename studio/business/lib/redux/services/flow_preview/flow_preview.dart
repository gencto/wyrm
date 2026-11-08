import 'dart:async';
import 'dart:math' as math;

import 'package:models/live_value.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/services/interface.dart';
import '../../../wyrm/mappers/values.dart';
import '../flow_watch/flow_watch.dart';

/// What [FlowPreviewService] tells its listener.
abstract class FlowPreviewServiceListener {
  /// The values that changed since the last call, at most every
  /// [FlowPreviewService.flushEvery]: [ports] keyed as the watch's
  /// (`in:<node>.<port>`, `out:…`, `param:…`), [sinks] by node (what a
  /// `set`, `invoke` or `publish` WOULD write; nothing is written). With
  /// [reset] the values held before are dropped first (a snapshot, another
  /// draft, the preview stopped).
  void onValues(
    Map<String, LiveValue> ports,
    Map<String, LiveValue> sinks, {
    required bool reset,
  });

  /// The broker's compiler refused the draft ([message], from
  /// `invalid_parameter`); null: a draft runs again.
  void onInvalid(String? message);

  /// The broker has no preview (`not_found`, `not_supported`) or refuses it
  /// (`permission_denied`): the editor shows the deployed version's values
  /// instead. Null: asked again (a new session).
  void onOff(Status? status);
}

/// Live values of the draft being edited: `dataflows` ▸ `preview {def,
/// max_hz}`, the same rows as `watch` (ADR 0038 §3) plus `sinks`, for a
/// definition that is compiled and run without writing anything, for at
/// most 10 minutes (`ttl`).
///
/// [show] hands it the draft after each edit; it waits [debounce] for the
/// edits to settle, ends the preview of the definition before and opens
/// one of the new. The same definition again (a block moved) changes
/// nothing. A stream that ends (its ttl) opens again with the definition in
/// use; a failure opens it again after a back-off that doubles up to
/// [retryMax] (`busy`: the broker's 2 previews per subject are in use).
///
/// `invalid_parameter` keeps the definition and waits for the next one;
/// `not_found` / `not_supported` (a broker without the action) and
/// `permission_denied` stop asking until the next [attach].
class FlowPreviewService extends DisposableServiceInterface {
  FlowPreviewService({
    required this._listener,
    this.debounce = const Duration(milliseconds: 300),
    this.flushEvery = const Duration(milliseconds: 50),
    this.retryFirst = const Duration(seconds: 1),
    this.retryMax = const Duration(seconds: 30),
    this.maxHz = 4,
  });

  final FlowPreviewServiceListener _listener;

  /// How long edits must pause before the draft runs.
  final Duration debounce;
  final Duration flushEvery;
  final Duration retryFirst;
  final Duration retryMax;

  /// Rows per node per second the broker sends at most.
  final int maxHz;

  WyrmApi? _api;

  /// `wy/<site>/dataflows` and the definition previewed, or none.
  String? _at;
  Value? _def;
  StreamSubscription<Value>? _sub;
  Timer? _wait;
  Timer? _flush;
  var _failures = 0;
  var _off = false;
  var _invalid = false;
  var _reset = false;
  final _ports = <String, LiveValue>{};
  final _sinks = <String, LiveValue>{};

  /// The broker has no preview or refuses it; nothing is asked.
  bool get off => _off;

  /// The definition previewed, or the one waiting for [debounce].
  Value? get def => _def;

  /// Uses [api]; previews the definition in use, if any.
  void attach(WyrmApi api) {
    _close();
    _api = api;
    if (_off) {
      _off = false;
      _listener.onOff(null);
    }
    _failures = 0;
    _later(Duration.zero);
  }

  /// Previews [def] at [dataflows] (`wy/<site>/dataflows`); null for either
  /// stops. The same definition as before changes nothing.
  void show(String? dataflows, Value? def) {
    final at = def == null ? null : dataflows;
    final run = at == null ? null : def;
    if (at == _at && run == _def) {
      return;
    }
    _close();
    _at = at;
    _def = run;
    _failures = 0;
    if (run == null) {
      // Stopped: its values go. Another draft keeps them until its own
      // first row (a snapshot) replaces them, so an edit does not blank
      // every field.
      _ports.clear();
      _sinks.clear();
      _reset = true;
      _schedule();
      if (_invalid) {
        _invalid = false;
        _listener.onInvalid(null);
      }
      return;
    }
    _later(debounce);
  }

  void _later(Duration d) {
    _wait?.cancel();
    _wait = null;
    if (_at == null || _def == null || _off || _api == null) {
      return;
    }
    _wait = Timer(d, () {
      _wait = null;
      if (_sub == null) {
        _open();
      }
    });
  }

  void _open() {
    final api = _api;
    final at = _at;
    final def = _def;
    if (api == null || at == null || def == null || _off) {
      return;
    }
    var rows = 0;
    _sub = api
        .invoke(
          at,
          'preview',
          Value.from({'def': toDart(def), 'max_hz': maxHz}),
        )
        .listen(
          (r) {
            rows++;
            _onRow(r);
          },
          onError: (Object e) {
            unawaited(_sub?.cancel());
            _sub = null;
            final status = e is WyrmException ? e.status.known : null;
            if (status == Status.notFound ||
                status == Status.notSupported ||
                status == Status.permissionDenied) {
              logger.fine('preview $at: ${status!.name}');
              _off = true;
              _listener.onOff(status);
              return;
            }
            if (e is WyrmException && status == Status.invalidParameter) {
              // Kept until the next definition; the values before stay.
              _invalid = true;
              _listener.onInvalid(
                e.message.isEmpty ? e.status.name : e.message,
              );
              return;
            }
            logger.fine('preview $at: $e');
            _again(rows);
          },
          onDone: () => _again(rows),
          cancelOnError: true,
        );
  }

  /// Opens it again: soon after a stream that carried rows (its ttl), later
  /// and later after ones that ended empty.
  void _again(int rows) {
    _sub = null;
    _failures = rows > 0 ? 0 : _failures + 1;
    _later(
      rows > 0
          ? retryFirst
          : Duration(
              milliseconds: math.min(
                retryMax.inMilliseconds,
                retryFirst.inMilliseconds * (1 << math.min(_failures, 16)),
              ),
            ),
    );
  }

  void _onRow(Value r) {
    if (_invalid) {
      _invalid = false;
      _listener.onInvalid(null);
    }
    final t = time(r['t']) ?? DateTime.now().toUtc();
    if (boolean(r['snapshot']) ?? false) {
      _ports.clear();
      _sinks.clear();
      _reset = true;
    }
    flowRowPorts(r, t, _ports);
    if (r['sinks'] case VArray(:final v)) {
      for (final s in v) {
        if (str(s['node']) case final node?) {
          _sinks[node] = LiveValue(time: t, value: toDart(s['value']));
        }
      }
    }
    _schedule();
  }

  void _schedule() => _flush ??= Timer(flushEvery, flush);

  /// Hands what changed to the listener now.
  void flush() {
    _flush?.cancel();
    _flush = null;
    if (_ports.isEmpty && _sinks.isEmpty && !_reset) {
      return;
    }
    final ports = Map.of(_ports);
    final sinks = Map.of(_sinks);
    final reset = _reset;
    _ports.clear();
    _sinks.clear();
    _reset = false;
    _listener.onValues(ports, sinks, reset: reset);
  }

  void _close() {
    unawaited(_sub?.cancel());
    _sub = null;
    _wait?.cancel();
    _wait = null;
  }

  /// Stops the preview and forgets the session; the definition is kept.
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
