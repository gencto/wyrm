import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/studio_error.dart';

import '../failures.dart';
import 'decoded.dart';

/// What a call does with an answer it cannot read: the value, or a typed
/// refusal the app words ([ErrorHint.unreadableAnswer]) with the shape,
/// the field and the reason in the log. Nothing is read out of such an
/// answer, and no state is made of it.
extension OrRefuse<T> on Decoded<T> {
  /// The value, or a [StudioException] for the [call] on [key].
  T orRefuse({required String key, required String call, String? thing}) {
    switch (this) {
      case Valid(:final value):
        return value;
      case Invalid(:final shape, :final field, :final reason):
        decodeLog.warning('$call on $key: $shape.$field: $reason');
        throw StudioException(
          StudioError(
            kind: ErrorKind.broker,
            hint: ErrorHint.unreadableAnswer,
            key: key,
            call: call,
            thing: thing,
            site: siteOf(key),
          ),
        );
    }
  }
}

/// The entries of one list that could not be read, by name: what an
/// action that still shows the others collects, so that the user is told
/// (a toast and a line in Problems) instead of finding them gone.
final class Unread {
  final _names = <String>[];

  /// The value of [read]; an [Invalid] one is logged with [where] and its
  /// [name] is kept for [problem].
  T? take<T>(Decoded<T> read, {required String name, required String where}) {
    final value = read.orWarn(where);
    if (read is Invalid<T>) {
      _names.add(name);
    }
    return value;
  }

  bool get any => _names.isNotEmpty;

  /// The names kept, in the order they were read.
  List<String> get names => List.unmodifiable(_names);

  /// What to tell the user of the entries of the list [key] ([call] read
  /// it) that could not be read: a quiet problem the app words
  /// ([ErrorHint.unreadableRows]), naming them. Null when all were read.
  StudioError? problem({required String key, required String call}) => any
      ? StudioError(
          kind: ErrorKind.broker,
          hint: ErrorHint.unreadableRows,
          key: key,
          call: call,
          thing: _names.join(', '),
          site: siteOf(key),
          quiet: true,
        )
      : null;
}
