import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// Runs one broker call; a refusal becomes a [UserException] with the
/// broker's own message (docs/studio.md §2 rule 7). [what] names the call for
/// the title ("Cannot list the links").
Future<T> call<T>(String what, Future<T> Function() f) async {
  try {
    return await f();
  } on WyrmException catch (e) {
    throw UserException(what, reason: '${e.status.name}: ${e.message}');
  }
}

/// The rows of one `invoke`, collected; a refusal as in [call].
Future<List<Value>> invokeAll(
  WyrmApi api,
  String key,
  String action, [
  Value? args,
]) => call('$action failed', () => api.invoke(key, action, args).toList());

/// The first row of an action's answer, or `VNull`.
Future<Value> invokeOne(
  WyrmApi api,
  String key,
  String action, [
  Value? args,
]) async {
  final rows = await invokeAll(api, key, action, args);
  return rows.isEmpty ? const VNull() : rows.first;
}

/// `{success, message}` of an install-style answer: throws with the message
/// when success is false.
void requireSuccess(Value answer, String what) {
  if (answer['success'] case VBool(v: false)) {
    final message = switch (answer['message']) {
      VStr(:final v) => v,
      _ => 'the broker said no',
    };
    throw UserException(what, reason: message);
  }
}
