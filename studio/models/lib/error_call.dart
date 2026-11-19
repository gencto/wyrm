import 'package:freezed_annotation/freezed_annotation.dart';

import 'call_verb.dart';
import 'known_call.dart';

part 'error_call.freezed.dart';

/// The call an error is about (docs/design/specs/errors.md §1): one Studio
/// knows by name, or anything else by the name it has. Typed where the
/// error is made; a wire name that arrives as data (the action of an
/// `invoke`) is read once, by [ErrorCall.ofWire].
// No copyWith: a model that holds it under the name `call` would get a
// nested `copyWith.call` getter over its own `copyWith(...)`.
@Freezed(copyWith: false)
sealed class ErrorCall with _$ErrorCall {
  /// A call Studio names.
  const factory ErrorCall.known(KnownCall call) = ErrorCallKnown;

  /// Any other action of a link, or a step of Studio itself (a fault's
  /// action, a panel), by its [name].
  const factory ErrorCall.named(String name) = ErrorCallNamed;

  const ErrorCall._();

  /// The call of the wire name [wire]: the one Studio knows, else the
  /// action as it is named.
  factory ErrorCall.ofWire(String wire) => switch (KnownCall.fromWire(wire)) {
    final c? => ErrorCall.known(c),
    null => ErrorCall.named(wire),
  };

  /// The name shown in *key › call* and in a title.
  String get name => switch (this) {
    ErrorCallKnown(:final call) => call.wire,
    ErrorCallNamed(:final name) => name,
  };

  /// What it does, for the title's words.
  CallVerb get verb => switch (this) {
    ErrorCallKnown(:final call) => call.verb,
    ErrorCallNamed() => CallVerb.run,
  };

  /// The call Studio knows it as, or null.
  KnownCall? get known => switch (this) {
    ErrorCallKnown(:final call) => call,
    ErrorCallNamed() => null,
  };
}
