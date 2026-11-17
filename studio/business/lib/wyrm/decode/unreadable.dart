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
