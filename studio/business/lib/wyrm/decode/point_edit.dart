import 'package:models/action_info.dart';
import 'package:models/modbus_area.dart';
import 'package:models/param_spec.dart';
import 'package:models/point_param.dart';
import 'package:models/point_register.dart';
import 'package:models/word_order.dart';

// A point's `edit` and `cfg` as the inspector and the points table read
// them (docs/modbus.md): the parameter names, the register and the data
// type's word order, read once from the driver's text.

/// One parameter of an `edit`, with the board's name for it (null: one the
/// board does not name).
typedef EditParam = ({ParamSpec spec, PointParam? param});

/// The parameters of [edit], in its order.
List<EditParam> editParamsOf(ActionInfo edit) => [
  for (final p in edit.params) (spec: p, param: PointParam.fromWire(p.name)),
];

/// Where the point of [cfg] is read: `table` and `addr` (a modbus area and
/// offset), else `address`, else nothing known.
PointRegister pointRegisterOf(Map<String, String>? cfg) {
  if (cfg == null) {
    return const PointRegister.none();
  }
  if (cfg['addr'] case final a?) {
    final table = cfg['table'];
    return PointRegister.modbus(
      addr: a,
      area: table == null ? null : ModbusArea.fromWire(table),
      table: table,
    );
  }
  return switch (cfg['address']) {
    final a? => PointRegister.address(a),
    null => const PointRegister.none(),
  };
}

/// The word and byte order the modbus data type [dtype] sets by its suffix
/// (`f32_wswap` → [WordOrder.cdab]); none is [WordOrder.abcd].
WordOrder wordOrderOf(String dtype) => switch (dtype) {
  final d when d.endsWith('_wbswap') => WordOrder.dcba,
  final d when d.endsWith('_wswap') => WordOrder.cdab,
  final d when d.endsWith('_bswap') => WordOrder.badc,
  _ => WordOrder.abcd,
};
