import 'package:freezed_annotation/freezed_annotation.dart';

import 'modbus_area.dart';

part 'point_register.freezed.dart';

/// Where a point is read on its device: a modbus area and offset as the
/// driver takes them (`addr`, 0-based; docs/modbus.md), another driver's
/// `cfg.address`, or nothing known.
@freezed
sealed class PointRegister with _$PointRegister {
  /// `cfg.table` and `cfg.addr`: [area] when the table is one this client
  /// knows, else the [table] as the driver names it.
  const factory PointRegister.modbus({
    required String addr,
    ModbusArea? area,
    String? table,
  }) = ModbusRegister;

  /// `cfg.address`.
  const factory PointRegister.address(String text) = AddressRegister;

  const factory PointRegister.none() = NoRegister;
}
