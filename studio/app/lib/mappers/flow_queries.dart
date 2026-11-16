import 'package:business/wyrm/flow_view/menu_view.dart';
import 'package:business/wyrm/flow_view/prompt_view.dart';
import 'package:business/wyrm/flow_view/questions_view.dart';
import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:models/field_id.dart';
import 'package:ui/flows/bind_refusal.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/flow_intents.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/scope_prompt.dart';
import 'package:ui/models/query.dart';
import 'package:ui/overlays/value_viewer.dart';

import 'flow_editor_mappers.dart';
import 'flow_inspector_mappers.dart';

// The questions the flow editor's widgets ask while the user acts, each
// answered from the business view's `FlowQuestions` alone: the key of
// every query is the values its answers are made of, so a view-model that
// holds one compares what it depends on.

/// A field of [block] pinned to it ([on]) or taken off, from the menu.
final class PinPicked extends Equatable {
  const PinPicked(this.block, this.field, {required this.on});

  final String block;
  final FieldId field;
  final bool on;

  @override
  List<Object?> get props => [block, field, on];
}

/// The canvas's context menu where it opened.
final class FlowMenuQuery extends QueryVm<FlowMenuAsk, FlowMenuVm> {
  const FlowMenuQuery(this.questions, {required this.onPin});

  final FlowQuestions questions;

  /// A pin of the menu's `Fields ▸` or its `Unpin` (behaviour: not in
  /// [key]).
  final ValueChanged<PinPicked> onPin;

  @override
  Object? get key => questions;

  @override
  FlowMenuVm ask(FlowMenuAsk question) {
    final block = question.block;
    final row = question.row;
    return questions
        .menu(
          MenuAsk(
            question.ids.lock,
            block: block,
            row: block == null || row == null
                ? null
                : questions.rowAt(block, row),
          ),
        )
        .vm(
          (field) => (on) {
            if (block != null) {
              onPin(PinPicked(block, field, on: on));
            }
          },
        );
  }
}

/// Why a wire let go on a row would not bind; null: it binds.
final class WireRefusalQuery extends QueryVm<BindAsk, BindRefusalVm?> {
  const WireRefusalQuery(this.questions);

  final FlowQuestions questions;

  @override
  Object? get key => questions;

  @override
  BindRefusalVm? ask(BindAsk question) =>
      switch (questions.rowAt(question.to.block, question.to.row)) {
        final row? =>
          questions
              .refusal(
                WireAsk(
                  question.from.end,
                  question.to.block,
                  row,
                  replacing: question.replacing?.end,
                ),
              )
              ?.vm,
        null => null,
      };
}

/// Why a new name of a custom block (Rename) is refused; null: it is free.
final class BlockNameQuery extends QueryVm<String, CustomBlockProblemVm?> {
  const BlockNameQuery(this.questions);

  final FlowQuestions questions;

  @override
  Object? get key => questions;

  @override
  CustomBlockProblemVm? ask(String question) =>
      questions.blockName(question)?.vm;
}

/// Why the block the create dialog would make is refused; null: it is
/// made.
final class CustomBlockQuery
    extends QueryVm<CustomBlockResult, CustomBlockProblemVm?> {
  const CustomBlockQuery(this.questions);

  final FlowQuestions questions;

  @override
  Object? get key => questions;

  @override
  CustomBlockProblemVm? ask(CustomBlockResult question) =>
      questions.customBlock(question.spec)?.vm;
}

/// Why a scope typed for a key of this site is refused: made of the site
/// alone.
final class ScopeQuery extends QueryVm<String, ScopeProblemVm?> {
  const ScopeQuery(this.questions);

  final FlowQuestions questions;

  @override
  Object? get key => questions.base.root;

  @override
  ScopeProblemVm? ask(String question) => questions.scope(question)?.vm;
}

/// Why a text typed in the viewer's Edit mode is refused; null: it saves.
final class ViewerTextQuery extends QueryVm<String, ViewerTextProblemVm?> {
  const ViewerTextQuery(this.questions);

  final FlowQuestions questions;

  @override
  Object? get key => questions;

  @override
  ViewerTextProblemVm? ask(String question) =>
      questions.viewerText(question)?.vm;
}
