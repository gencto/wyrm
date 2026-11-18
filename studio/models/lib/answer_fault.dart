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
  /// was [got] where [expected] belongs.
  const factory AnswerFault.wrongShape({
    required String path,
    required String expected,
    required String got,
  }) = AnswerFaultWrongShape;

  /// The TLS certificate is not one this computer trusts.
  const factory AnswerFault.untrusted() = AnswerFaultUntrusted;

  /// The connection was refused, [ms] milliseconds after it was tried.
  const factory AnswerFault.refusedAfter(int ms) = AnswerFaultRefusedAfter;

  /// No route to the host.
  const factory AnswerFault.noRoute() = AnswerFaultNoRoute;

  /// An HTTP status that is not 200.
  const factory AnswerFault.http(int code) = AnswerFaultHttp;

  /// The system's own words.
  const factory AnswerFault.said(String text) = AnswerFaultSaid;
}
