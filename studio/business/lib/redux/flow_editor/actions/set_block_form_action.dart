import 'dart:async';

import '../../../wyrm/mappers/flow_fields.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

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
  final String form;

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
    bool gone(String name) => others.any((f) => f.owns(name));
    final t = flowEditor.types.where((t) => t.type == b.type).firstOrNull;
    var cfg = b.cfg.removeWhere((k, _) => gone(k));
    if (chosen != forms.first) {
      final catalog = {
        for (final p in [...?t?.params]) p.name: p.defaultValue,
      };
      for (final name in chosen.params) {
        final v = catalog[name] ?? chosen.defaults[name];
        if (cfg[name] == null && v != null) {
          cfg = cfg.add(name, v);
        }
      }
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        blocks: d.blocks.add(block, b.copyWith(cfg: cfg)),
        edges: d.edges.removeWhere(
          (e) =>
              (e.to == block &&
                  e.toPort.startsWith('in.') &&
                  gone(e.toPort.substring(3))) ||
              (e.from == block && gone(e.fromPort)),
        ),
      ),
      dirty: true,
    );
  }
}
