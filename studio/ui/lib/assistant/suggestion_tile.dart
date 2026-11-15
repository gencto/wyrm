import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/tag_chip.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'blocked.dart';
import 'task_badge.dart';

/// What [SuggestionTile] draws: one thing the model offers to ask next.
final class SuggestionTileVm extends Equatable {
  const SuggestionTileVm({
    required this.id,
    required this.label,
    required this.changes,
    this.detail = '',
    this.note,
    this.unattended,
    this.blocked,
  });

  /// The suggestion's id in its task.
  final String id;

  /// The model's words, shown as plain text.
  final String label;
  final String detail;

  /// How many changes the model guesses the follow-up plans (0: none).
  final int changes;

  /// What picking it does beyond a new ask; null: nothing more.
  final TileNote? note;

  /// The agent's mode when it lets a pick's plan write without a person
  /// (`config`, `never`); the note then says so.
  final AgentModeVm? unattended;

  /// Why it cannot be picked (rights, an ask in flight); null: it can.
  final Blocked? blocked;

  /// `1 change · its guess`, `nothing · its guess`.
  String get tag => S.current.changesGuess(changes);
  Tone get tagTone => changes == 0 ? Tone.neutral : Tone.ember;

  /// `replaces this plan`, `a draft to copy · sends nothing`.
  String? get noteText => switch (note) {
    null => null,
    TileNote.fix => unattended?.fixNote ?? S.current.fixReplaces,
    TileNote.followUp => unattended?.caution ?? S.current.followUpTileNote,
    TileNote.draft => S.current.draftTileNote,
  };

  String? get disabledReason => blocked?.text;

  @override
  List<Object?> get props => [
    id,
    label,
    detail,
    changes,
    note,
    unattended,
    blocked,
  ];
}

/// What picking a suggestion does beyond a new ask.
enum TileNote {
  /// A fix on a step: the new plan replaces this one.
  fix,

  /// A follow-up of a task that ended.
  followUp,

  /// The drawer's second tile while the plan waits: a draft to copy.
  draft,
}

/// A way out, a fix or a follow-up the model offers (ADR 0049 amendment):
/// its label and detail as the model wrote them, the tag of its guessed
/// changes, and what a pick does. A tap sends a follow-up ask; the tile
/// itself runs nothing.
class SuggestionTile extends StatelessWidget {
  const SuggestionTile({required this.vm, this.onTap, super.key});

  final SuggestionTileVm vm;

  /// Null, or [SuggestionTileVm.disabledReason] set: the tile is shown and
  /// cannot be picked.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final can = onTap != null && vm.disabledReason == null;
    final tile = Material(
      color: c.ground2,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: vm.note == null ? c.line2 : c.emberLine),
        borderRadius: Radii.control,
      ),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: can ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          child: Row(
            crossAxisAlignment: .start,
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 3,
                  children: [
                    Text(
                      vm.label,
                      style: TextStyle(
                        fontSize: FontSizes.md,
                        fontWeight: .w600,
                        color: can ? c.text1 : c.text3,
                      ),
                    ),
                    if (vm.detail.isNotEmpty)
                      Text(
                        vm.detail,
                        style: TextStyle(
                          fontSize: FontSizes.sm,
                          height: 1.45,
                          color: c.text3,
                        ),
                      ),
                    if (vm.noteText case final n?)
                      Text(
                        n,
                        style: TextStyle(
                          fontSize: FontSizes.sm,
                          color: c.ember,
                        ),
                      ),
                  ],
                ),
              ),
              TagChip(
                vm: TagChipVm(label: vm.tag, tone: vm.tagTone),
              ),
            ],
          ),
        ),
      ),
    );
    return vm.disabledReason == null
        ? tile
        : Tooltip(message: vm.disabledReason, child: tile);
  }
}
