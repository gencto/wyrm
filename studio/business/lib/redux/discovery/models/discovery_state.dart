import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/ca_pin.dart';
import 'package:models/found_gateway.dart';

part 'discovery_state.freezed.dart';

@freezed
abstract class DiscoveryState with _$DiscoveryState {
  const factory DiscoveryState({
    @Default(false) bool open,
    @Default(false) bool scanning,
    @Default(false) bool ended,
    @Default(0) int scan,
    @Default(IMapConst({})) IMap<String, FoundGateway> found,
    @Default(IMapConst({})) IMap<String, CaPin> pins,
    String? trustPending,
    String? trustRefused,
    String? picked,
    String? network,
    String? subnet,
    String? range,
    String? rangePort,
    @Default(false) bool probing,
  }) = _DiscoveryState;
}
