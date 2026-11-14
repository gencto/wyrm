import 'package:freezed_annotation/freezed_annotation.dart';

part 'broker_update_state.freezed.dart';

@freezed
abstract class BrokerUpdateState with _$BrokerUpdateState {
  const factory BrokerUpdateState({
    String? stage,
    @Default('') String confirm,
  }) = _BrokerUpdateState;
}
