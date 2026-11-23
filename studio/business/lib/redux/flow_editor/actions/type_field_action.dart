import 'package:models/field_id.dart';

import '../../../wyrm/mappers/block_cfg.dart';
import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../../wyrm/mappers/flow_fields.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'set_block_param_action.dart';
import 'set_operand_value_action.dart';

/// [text] typed into the field [field] of block [block]: what an inspector
/// row and the value viewer's Save both do (spec §15). The field's kind
/// reads the text (a number, a bool, JSON; `fieldEditOf`, `typedText`); a
/// parameter goes into the config, an operand into `values`, an argument
/// into `args`, a custom block's input into its `defaults`. A field that is
/// not typed (bound, an output) changes nothing. A block's form is picked,
/// not typed (`SetBlockFormAction` with its id).
class TypeFieldAction extends Action {
  TypeFieldAction(this.block, this.field, this.text);

  final String block;
  final FieldId field;
  final String text;

  @override
  AppState? reduce() {
    final base = flowEditor.base;
    final d = base.draft;
    final b = d?.blocks[block];
    if (d == null || b == null) {
      return null;
    }
    final f = base.fields[block]?.where((x) => x.id == field).firstOrNull;
    final edit = f == null ? null : fieldEditOf(b, f, d.edges).edit;
    if (f == null || edit == null) {
      return null;
    }
    final value = typedText(text, edit);
    final empty = text.trim().isEmpty;
    if (b.id == blockInputsId) {
      // The default of a custom block's input.
      final defaults = empty
          ? b.cfgDefaults.remove(f.name)
          : b.cfgDefaults.add(f.name, value);
      dispatchSync(
        SetBlockParamAction(
          b.id,
          BlockCfgKey.defaults.wire,
          JsonMap.fields(defaults),
        ),
      );
    } else if (f.operand) {
      dispatchSync(SetOperandValueAction(b.id, f.inPort!, value));
    } else if (f.kind == FieldKind.arg) {
      // Nothing typed: an argument the action may go without leaves the
      // call; any other is sent as nothing.
      final args = empty && f.argSpec != null && !f.argSpec!.required
          ? b.cfgArgs.remove(f.name)
          : b.cfgArgs.add(f.name, empty ? const JsonNull() : value);
      // An empty map stays a map: the block still names its arguments.
      dispatchSync(
        SetBlockParamAction(b.id, BlockCfgKey.args.wire, JsonMap.fields(args)),
      );
    } else if (f.spec case final p?) {
      dispatchSync(SetBlockParamAction(b.id, p.name, value));
    }
    return null;
  }
}
