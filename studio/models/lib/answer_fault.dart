import 'package:freezed_annotation/freezed_annotation.dart';

part 'answer_fault.freezed.dart';

/// Why a gateway gave nothing Studio can use (its `/api/info`, the probe
/// before a log-in), beside the kind of the failure: named by `business`,
/// said by `ui`. Words that are not Studio's (the system's, a TLS
/// library's) are `said`, as they came.
@freezed
sealed class AnswerFault with _$AnswerFault {
  /// No answer in time.
  const factory AnswerFault.timedOut() = AnswerFaultTimedOut;

  /// An answer that is not CBOR: not a WYRM gateway.
  const factory AnswerFault.notGateway() = AnswerFaultNotGateway;

  /// CBOR of another shape (ADR 0050 decision 10): the field at [path]
  /// is not what belongs there. What was expected and what came is the
  /// decoder's and goes to the log.
  const factory AnswerFault.wrongShape(String path) = AnswerFaultWrongShape;

  /// The TLS certificate is not one this computer trusts.
  const factory AnswerFault.untrusted() = AnswerFaultUntrusted;

  /// The connection was refused, [ms] milliseconds after it was tried.
  const factory AnswerFault.refusedAfter(int ms) = AnswerFaultRefusedAfter;

  /// No route to the host.
  const factory AnswerFault.noRoute() = AnswerFaultNoRoute;

  /// An HTTP status that is not 200.
  const factory AnswerFault.http(int code) = AnswerFaultHttp;

  /// Anything else that was thrown, by the name of its [type] only: what
  /// it says of itself may hold the address it was asked on, and stays in
  /// the log.
  const factory AnswerFault.failed(String type) = AnswerFaultFailed;

  /// The system's own words.
  const factory AnswerFault.said(String text) = AnswerFaultSaid;
}
