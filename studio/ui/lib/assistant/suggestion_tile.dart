import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/tag_chip.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// What [SuggestionTile] draws: one thing the model offers to ask next.
final class SuggestionTileVm extends Equatable {
  const SuggestionTileVm({
    required this.id,
    required this.label,
    this.detail = '',
    this.tag,
    this.tagTone = Tone.neutral,
    this.note,
    this.disabledReason,
  });

  /// The suggestion's id in its task.
  final String id;

  /// The model's words, shown as plain text.
  final String label;
  final String detail;

  /// `1 change (the assistant's guess)`, `nothing (the assistant's guess)`.
  final String? tag;
  final Tone tagTone;

  /// What picking it does beyond a new ask: `replaces this plan`.
  final String? note;

  /// Why it cannot be picked (rights, an ask in flight); null: it can.
  final String? disabledReason;

  @override
  List<Object?> get props => [
    id,
    label,
    detail,
    tag,
    tagTone,
    note,
    disabledReason,
  ];
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
                        fontSize: 13,
                        fontWeight: .w600,
                        color: can ? c.text1 : c.text3,
                      ),
                    ),
                    if (vm.detail.isNotEmpty)
                      Text(
                        vm.detail,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: c.text3,
                        ),
                      ),
                    if (vm.note case final n?)
                      Text(n, style: TextStyle(fontSize: 12, color: c.ember)),
                  ],
                ),
              ),
              if (vm.tag case final t?)
                TagChip(
                  vm: TagChipVm(label: t, tone: vm.tagTone),
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
