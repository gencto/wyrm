import 'package:equatable/equatable.dart';
import 'package:models/field_id.dart';

import '../mappers/flow_blocks.dart';
import '../mappers/flow_canvas.dart';
import 'flow_view.dart';
import 'menu_view.dart';
import 'prompt_view.dart';

/// What the page asks while the user acts, answered from what the editor
/// shows: the context menu where it opened, why a wire would not bind,
/// what is wrong with a name, a scope or a text typed in the viewer.
///
/// Each answer is made only of the values held here, and the equality is
/// theirs: [base] (the flow, its types and fields, by identity: it is
/// made again whenever one of them changes), whether there is something
/// to undo or redo, and the field the viewer shows. Two equal questions
/// give the same answers.
final class FlowQuestions extends Equatable {
  const FlowQuestions(
    this.base, {
    required this.canUndo,
    required this.canRedo,
    this.viewed,
  });

  final FlowBase base;
  final bool canUndo;
  final bool canRedo;

  /// The field the viewer shows.
  final FieldAt? viewed;

  /// The field that stands at place [row] among block [block]'s rows on
  /// the canvas (its pinned fields, as drawn); null when there is none.
  FieldId? rowAt(String block, int row) {
    final rows = base.rows[block];
    return rows == null || row < 0 || row >= rows.length ? null : rows[row].id;
  }

  /// The context menu [ask] opens (spec §13).
  FlowMenuView menu(MenuAsk ask) => flowMenuOf(
    ask,
    base.draft,
    base.fields,
    customBlocks: base.caps.blocks,
    canUndo: canUndo,
    canRedo: canRedo,
  );

  /// Why the wire [ask] would not bind; null: it binds.
  WireRefusal? refusal(WireAsk ask) =>
      wireRefusalOf(ask, base.draft, base.types, base.fields);

  /// What is wrong with [name] for `Rename` of a custom block.
  BlockNameProblem? blockName(String name) =>
      blockNameProblemOf(base.defs, name);

  /// What is wrong with the block the create dialog would make.
  BlockNameProblem? customBlock(CustomBlockSpec spec) => switch (base.draft) {
    final d? => customBlockProblem(d, spec),
    null => null,
  };

  /// What is wrong with a scope typed for a key of this site.
  ScopeProblem? scope(String scope) => scopeProblemAt(base.root, scope);

  /// What is wrong with [text] typed in the viewer's Edit mode; null: it
  /// saves (or no typed field is viewed).
  FieldEditError? viewerText(String text) {
    final at = viewed;
    final d = base.draft;
    final b = at == null ? null : d?.blocks[at.block];
    if (at == null || b == null || d == null) {
      return null;
    }
    return viewerTextErrorOf(b, at.row, base.fields[b.id]!, d, text);
  }

  // [base] compares by identity: a memo makes it again when the flow, its
  // types, frames, the catalogue, the site or the nodes' `~meta` change.
  @override
  List<Object?> get props => [base, canUndo, canRedo, viewed];
}
