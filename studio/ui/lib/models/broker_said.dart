import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

/// What a broker said of a call: its own words ([message]), after the
/// status of its refusal by its wire name ([status]) when it refused
/// instead of answering, after the [key] the call was made on when the
/// screen names it. Status, key and words are data; the line is put
/// together here.
final class BrokerSaidVm extends Equatable {
  const BrokerSaidVm({this.status, this.message, this.key});

  final String? status;
  final String? message;
  final String? key;

  /// `timeout: the device did not answer`, the status alone, or the
  /// words; with the key before it when there is one.
  String get text {
    final said = switch ((status, message)) {
      (final st?, final m?) when m.isNotEmpty => S.current.errStatusLine(st, m),
      (final st?, _) => st,
      (null, final m) => m ?? '',
    };
    return switch (key) {
      final k? => S.current.errStatusLine(k, said),
      null => said,
    };
  }

  @override
  List<Object?> get props => [status, message, key];
}
