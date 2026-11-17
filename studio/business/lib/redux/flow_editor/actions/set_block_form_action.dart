import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../../wyrm/mappers/flow_fields.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Puts block [block] in its form [form] (`scale`: `linear` or `range`,
/// ADR 0032 §7). The parameters of the other forms leave the config, and
/// so do the wires into and out of their fields (their `in.<p>` ports,
/// their echo outputs, the outputs only they send). A form after the
/// first is told by its parameters, so choosing one writes the defaults
/// of those it does not have yet: the definition then says which form the
/// block is in, and the engine maps from the range at once.
class SetBlockFormAction extends Action {
  SetBlockFormAction(this.block, this.form);

  final String block;
  final BlockFormId form;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final b = d?.blocks[block];
    final forms = b == null ? const <BlockForm>[] : formsOf(b.type);
    final chosen = forms.where((f) => f.id == form).firstOrNull;
    if (d == null || b == null || chosen == null) {
      return null;
    }
    final others = [
      for (final f in forms)
        if (f.id != chosen.id) f,
    ];
    // What only the other forms use leaves: their parameters (config, the
    // port that feeds one, its echo) and their outputs.
    final goneParams = {for (final f in others) ...f.params};
    final goneOutputs = {for (final f in others) ...f.outputs};
    final t = flowEditor.allTypes.where((t) => t.type == b.type).firstOrNull;
    var cfg = b.cfg;
    for (final p in goneParams) {
      cfg = cfg.remove(p.wire);
    }
    if (chosen != forms.first) {
      final catalog = {
        for (final p in [...?t?.params]) ?p.key: p.defaultValue,
      };
      for (final key in chosen.params) {
        final v = catalog[key] ?? chosen.defaults[key];
        if (cfg[key.wire] == null && v != null) {
          cfg = cfg.add(key.wire, v);
        }
      }
    }
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        blocks: d.blocks.add(block, b.copyWith(cfg: cfg)),
        edges: d.edges.removeWhere(
          (e) =>
              (e.to == block && goneParams.contains(e.target.paramKey)) ||
              (e.from == block &&
                  (goneOutputs.contains(e.source.known) ||
                      goneParams.contains(e.source.echoKey))),
        ),
      ),
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
