import 'dart:async';
import 'dart:typed_data';

import 'package:models/step_up_line.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'session.dart';

/// Meets a `confirm_required` refusal (ADR 0050 §1.3): shows the step-up
/// for [lines] (what the refused request does) and answers whether the
/// session was confirmed. Concurrent refusals share one dialog.
typedef StepUpGate = Future<bool> Function(
  WyrmException refusal,
  List<StepUpLine> lines,
);

/// Whether [e] is the gateway asking for a fresh confirmation.
bool isConfirmRequired(Object e) =>
    e is WyrmException && e.code == 'confirm_required';

/// How often one request may meet the step-up: a confirm that the gateway
/// does not take (another process, a restart) does not ask forever.
const _rounds = 2;

/// Runs [call]; a `confirm_required` goes to [gate] with [lines], and after
/// a confirm the same call goes again. A cancelled step-up rethrows the
/// refusal.
Future<T> withStepUp<T>(
  StepUpGate gate,
  List<StepUpLine> Function() lines,
  Future<T> Function() call,
) async {
  for (var round = 0; ; round++) {
    try {
      return await call();
    } on WyrmException catch (e) {
      if (!isConfirmRequired(e) ||
          round >= _rounds ||
          !await gate(e, lines())) {
        rethrow;
      }
    }
  }
}

/// A [WyrmApi] whose writes meet the step-up: a `set` or an `invoke` the
/// gateway refused with `confirm_required` is sent again once the session
/// is confirmed. Reads go straight through.
final class StepUpApi implements WyrmApi {
  StepUpApi(this._inner, this._gate);

  final WyrmApi _inner;
  final StepUpGate _gate;

  @override
  Future<void> set(String key, Value value) => withStepUp(
    _gate,
    () => [StepUpLine(level: 'config', text: 'set ${_last(key)}', key: key)],
    () => _inner.set(key, value),
  );

  @override
  Stream<Value> invoke(String key, String action, [Value? args]) async* {
    for (var round = 0; ; round++) {
      var sent = false;
      try {
        await for (final v in _inner.invoke(key, action, args)) {
          sent = true;
          yield v;
        }
        return;
      } on WyrmException catch (e) {
        // A refusal comes before any answer; one after an answer is the
        // action's own failure.
        if (sent ||
            !isConfirmRequired(e) ||
            round >= _rounds ||
            !await _gate(e, [
              StepUpLine(level: 'config', text: action, key: key),
            ])) {
          rethrow;
        }
      }
    }
  }

  @override
  Stream<ListUpdate> list(String key) => _inner.list(key);

  @override
  Stream<ValEvent> subscribe(String pattern) => _inner.subscribe(pattern);

  @override
  Future<NodeMeta> meta(String key) => _inner.meta(key);

  @override
  Future<List<Child>> children(String key) => _inner.children(key);

  @override
  Future<List<HistRow>> history(
    String key, {
    required String from,
    String to = '',
    String? agg,
    String? window,
    int? limit,
  }) => _inner.history(
    key,
    from: from,
    to: to,
    agg: agg,
    window: window,
    limit: limit,
  );

  @override
  Future<Value> doc(String key, String suffix) => _inner.doc(key, suffix);

  @override
  Future<void> close() => _inner.close();

  static String _last(String key) => key.split('/').last;
}

/// A [WyrmSession] whose broker calls and user changes meet the step-up
/// (user management is config level, ADR 0050 decision 9).
final class StepUpSession implements WyrmSession {
  StepUpSession(this.inner, StepUpGate gate)
    : _gate = gate,
      api = StepUpApi(inner.api, gate);

  /// The session as the gateway gave it.
  final WyrmSession inner;
  final StepUpGate _gate;

  @override
  final WyrmApi api;

  Future<T> _guard<T>(String text, String key, Future<T> Function() call) =>
      withStepUp(
        _gate,
        () => [StepUpLine(level: 'config', text: text, key: key)],
        call,
      );

  @override
  Stream<bool> get connection => inner.connection;

  @override
  Uri get base => inner.base;

  @override
  Future<WhoAmI> me() => inner.me();

  @override
  Future<List<GatewayUser>> users() => inner.users();

  @override
  Future<void> addUser(String name, String password, List<String> roles) =>
      _guard(
        'add user $name',
        'user:$name',
        () => inner.addUser(name, password, roles),
      );

  @override
  Future<void> removeUser(String name) =>
      _guard('remove user $name', 'user:$name', () => inner.removeUser(name));

  @override
  Future<void> setUserRoles(String name, List<String> roles) => _guard(
    'set roles of $name',
    'user:$name',
    () => inner.setUserRoles(name, roles),
  );

  @override
  Future<void> setUserPassword(String name, String password) => _guard(
    'set password of $name',
    'user:$name',
    () => inner.setUserPassword(name, password),
  );

  @override
  Future<void> setUserDisabled(String name, {required bool disabled}) => _guard(
    '${disabled ? 'disable' : 'enable'} user $name',
    'user:$name',
    () => inner.setUserDisabled(name, disabled: disabled),
  );

  @override
  Future<String> registerDevice({
    required String site,
    required String user,
    required String name,
    required String platform,
    required String alg,
    required Uint8List publicKey,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => inner.registerDevice(
    site: site,
    user: user,
    name: name,
    platform: platform,
    alg: alg,
    publicKey: publicKey,
    sign: sign,
  );

  @override
  Future<void> unlock({
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => inner.unlock(site: site, user: user, device: device, sign: sign);

  @override
  Future<void> confirmWithDevice({
    required WyrmException e,
    required String site,
    required String user,
    required String device,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) => inner.confirmWithDevice(
    e: e,
    site: site,
    user: user,
    device: device,
    sign: sign,
  );

  @override
  Future<void> confirmWithPassword(String password) =>
      inner.confirmWithPassword(password);

  @override
  Future<List<GatewayDevice>> devices() => inner.devices();

  @override
  Future<List<GatewayDevice>> userDevices(String name) =>
      inner.userDevices(name);

  @override
  Future<void> removeDevice(String id) =>
      _guard('remove device', 'device:$id', () => inner.removeDevice(id));

  @override
  Future<void> signOutEverywhere() => inner.signOutEverywhere();

  @override
  Future<void> close() => inner.close();
}
