import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart' show StatusCode;

import 'error_kind.dart';
import 'fault_report.dart';

part 'studio_error.freezed.dart';

/// One failure, as data (docs/design/specs/errors.md §1). The broker's
/// status stays a [StatusCode], never text to parse; the dialog, the toast
/// and the Problems drawer are three drawings of this one object.
@freezed
abstract class StudioError with _$StudioError {
  const factory StudioError({
    required ErrorKind kind,

    /// Given when the error is thrown; the Problems list finds it by this.
    @Default(0) int id,

    /// What did not happen, with its object: `You can’t deploy
    /// pump-control`. Composed from [kind], [call], [thing] and [site].
    @Default('') String title,

    /// The broker's words, as they came; empty when it sent none (a
    /// timeout). For a fault in Studio: what happened, in Studio's words.
    @Default('') String message,

    /// The status of the refusal; null for Studio's own faults and for a
    /// `{success: false}` answer.
    StatusCode? status,

    /// The full key the call was made on.
    String? key,

    /// The call: `deploy`, `set`, `subscribe`, `history`, `list`, …
    String? call,

    /// The name of what the call was about (`pump-control`, `modbus
    /// 0.4.2`), for the title; the last segment of [key] when null.
    String? thing,

    /// The site the call went to.
    String? site,

    /// When it failed, local time.
    DateTime? at,

    /// Nobody was waiting for this call: a toast and a line in Problems, no
    /// dialog.
    @Default(false) bool quiet,

    /// The call changes something on the broker (`set`, `deploy`, an
    /// action): a timeout then warns that it may have been applied.
    @Default(false) bool write,

    /// Builds the action to dispatch again (*Try again*); null when the
    /// call cannot be repeated as it was.
    Object Function()? retry,

    /// Builds the load action of the screen it came from (*Refresh*).
    Object Function()? reload,

    /// The parameter an `invalid_parameter` names, when the broker named
    /// one.
    String? field,

    /// Studio faults only.
    FaultReport? report,

    /// Opened as a dialog (the drawer says so).
    @Default(false) bool shown,

    /// A live stream of this site went down: its toast stays until the
    /// stream is open again.
    String? stream,

    /// The seconds *Try again* waits for (`busy`), when the broker gave a
    /// hint; null for the default.
    int? wait,
  }) = _StudioError;

  const StudioError._();

  /// `wy/plant/dataflows/pump-control › deploy`, or the part there is.
  String get where => [
    if (key case final k? when k.isNotEmpty) k,
    if (call case final c? when c.isNotEmpty) c,
  ].join(' › ');
}
