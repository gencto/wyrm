import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/fact_grid.dart';
import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../indicators/arc_spinner.dart';
import '../indicators/quality_mark.dart';
import '../inputs/check_row.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// Where a step of a [SheetSteps] block is.
enum SheetStepState { done, now, todo }

/// One block of a [TaskSheet], top to bottom.
sealed class SheetBlock extends Equatable {
  const SheetBlock();
}

/// A section label (12, upper case).
final class SheetLabel extends SheetBlock {
  const SheetLabel(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// A paragraph: body text, or a caption when [small]; [tone] colours it.
final class SheetText extends SheetBlock {
  const SheetText(this.text, {this.small = false, this.tone = Tone.neutral});

  final String text;
  final bool small;
  final Tone tone;

  @override
  List<Object?> get props => [text, small, tone];
}

/// Lines with an ember dot (release notes, a numbered plan when [numbered]).
final class SheetBullets extends SheetBlock {
  const SheetBullets(this.lines, {this.numbered = false});

  final List<String> lines;
  final bool numbered;

  @override
  List<Object?> get props => [lines, numbered];
}

/// A card with a state dot, a title and a detail: one thing that was checked
/// or that changes. A `warn` card has a warn border.
final class SheetCard extends SheetBlock {
  const SheetCard({required this.title, this.detail, this.tone = Tone.good});

  final String title;
  final String? detail;
  final Tone tone;

  @override
  List<Object?> get props => [title, detail, tone];
}

/// A checkbox with its sentence. Locked with [reason] when not [enabled].
/// A change is reported by its own [onChanged].
final class SheetOption extends SheetBlock {
  const SheetOption({
    required this.label,
    required this.value,
    this.enabled = true,
    this.reason,
    this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final String? reason;

  /// The new state of the checkbox; null: it cannot be changed.
  final ValueChanged<bool>? onChanged;

  @override
  List<Object?> get props => [label, value, enabled, reason, onChanged != null];
}

/// A chip of a [SheetSection]: one of a range, or one of a set. A tap is
/// reported by its own [onTap]: the sheet that builds the chip knows what
/// it stands for.
final class SheetChip extends Equatable {
  const SheetChip({required this.label, this.on = false, this.onTap});

  final String label;
  final bool on;

  /// Null: the chip is shown and cannot be picked.
  final VoidCallback? onTap;

  @override
  List<Object?> get props => [label, on, onTap != null];
}

/// A section of a backup as a card: a checkbox, its name, a tag, its size,
/// what it holds, and chips under it (a range to pick one of, or links to
/// tick). Dimmed when off; the checkbox is fixed when [locked]. A tick is
/// reported by its own [onChanged].
final class SheetSection extends SheetBlock {
  const SheetSection({
    required this.name,
    required this.on,
    this.detail,
    this.locked = false,
    this.reason,
    this.tag,
    this.tagTone = Tone.neutral,
    this.size,
    this.chips = const [],
    this.multi = false,
    this.onChanged,
  });

  final String name;
  final bool on;
  final String? detail;
  final bool locked;

  /// Why the checkbox is fixed, as its tooltip.
  final String? reason;
  final String? tag;
  final Tone tagTone;
  final String? size;
  final List<SheetChip> chips;

  /// The chips are ticked one by one; else one of them is chosen.
  final bool multi;

  /// The new state of the checkbox; null: it cannot be changed.
  final ValueChanged<bool>? onChanged;

  @override
  List<Object?> get props => [
    name,
    on,
    detail,
    locked,
    reason,
    tag,
    tagTone,
    size,
    chips,
    multi,
    onChanged != null,
  ];
}

/// One step of a [SheetSteps] block.
final class SheetStep extends Equatable {
  const SheetStep(this.title, this.state, {this.detail});

  final String title;
  final SheetStepState state;
  final String? detail;

  @override
  List<Object?> get props => [title, state, detail];
}

/// Steps with their marks: done (good ring), now (ember spinner), to do.
final class SheetSteps extends SheetBlock {
  const SheetSteps(this.steps);

  final List<SheetStep> steps;

  @override
  List<Object?> get props => [steps];
}

/// The result banner: a title and what happened, in [tone].
final class SheetBanner extends SheetBlock {
  const SheetBanner({required this.title, this.text, this.tone = Tone.good});

  final String title;
  final String? text;
  final Tone tone;

  @override
  List<Object?> get props => [title, text, tone];
}

/// One tile of a [SheetTiles] block: a number and its label.
final class SheetTile extends Equatable {
  const SheetTile(this.number, this.label, {this.tone = Tone.neutral});

  final String number;
  final String label;
  final Tone tone;

  @override
  List<Object?> get props => [number, label, tone];
}

/// Tiles side by side (kept, new, gone).
final class SheetTiles extends SheetBlock {
  const SheetTiles(this.tiles);

  final List<SheetTile> tiles;

  @override
  List<Object?> get props => [tiles];
}

/// A line of a list: a sign, a text (mono when [mono]), a note, and a link
/// on the right ([actionLabel]) that reports through [onAction].
final class SheetRow extends SheetBlock {
  const SheetRow({
    required this.text,
    this.sign,
    this.tone = Tone.neutral,
    this.note,
    this.mono = true,
    this.actionLabel,
    this.onAction,
    this.divider = false,
  });

  final String text;
  final String? sign;
  final Tone tone;
  final String? note;
  final bool mono;

  /// The words of the link; null: the row has none.
  final String? actionLabel;

  /// A tap on the link; null: the link is shown and cannot be used.
  final VoidCallback? onAction;

  /// A line above the row (a list of restore points).
  final bool divider;

  @override
  List<Object?> get props => [
    text,
    sign,
    tone,
    note,
    mono,
    actionLabel,
    onAction != null,
    divider,
  ];
}

/// Label and value pairs.
final class SheetFacts extends SheetBlock {
  const SheetFacts(this.facts);

  final List<FactVm> facts;

  @override
  List<Object?> get props => [facts];
}

/// A text field. A [secret] one is obscured and never shows a value: what
/// is typed stays in the field and is reported by its own [onChanged].
/// The field keeps what is typed while a field of its [slot] stays in the
/// sheet.
final class SheetField extends SheetBlock {
  const SheetField({
    required this.slot,
    required this.label,
    this.value,
    this.hint,
    this.note,
    this.error,
    this.secret = false,
    this.enabled = true,
    this.onChanged,
  });

  /// Which field of its sheet this is: a value of the sheet's own enum.
  /// It is the field's identity across rebuilds (never its label, which
  /// changes with the language).
  final Enum slot;
  final String label;
  final String? value;
  final String? hint;
  final String? note;
  final String? error;
  final bool secret;
  final bool enabled;

  /// The text as it is typed; null: nobody listens.
  final ValueChanged<String>? onChanged;

  @override
  List<Object?> get props => [
    slot,
    label,
    value,
    hint,
    note,
    error,
    secret,
    enabled,
    onChanged != null,
  ];
}

/// One option of a [SheetChoice]. With a [reason] it is shown and cannot
/// be chosen.
final class SheetChoiceOption extends Equatable {
  const SheetChoiceOption({
    required this.label,
    this.selected = false,
    this.reason,
    this.onPick,
  });

  final String label;
  final bool selected;

  /// Why it cannot be chosen, as its tooltip.
  final String? reason;

  /// The option was chosen.
  final VoidCallback? onPick;

  @override
  List<Object?> get props => [label, selected, reason, onPick != null];
}

/// One of a few: segments in a row, or radio lines when [lines]. Each
/// option reports its own choice.
final class SheetChoice extends SheetBlock {
  const SheetChoice({
    required this.options,
    this.label,
    this.note,
    this.lines = false,
  });

  final String? label;
  final List<SheetChoiceOption> options;
  final String? note;
  final bool lines;

  @override
  List<Object?> get props => [label, options, note, lines];
}

/// Commands or a file's text, mono in a well.
final class SheetCode extends SheetBlock {
  const SheetCode(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// A progress bar with a line under it.
final class SheetBar extends SheetBlock {
  const SheetBar({required this.percent, this.text});

  final int percent;
  final String? text;

  @override
  List<Object?> get props => [percent, text];
}

/// A spinner card: something goes on outside this screen (a restart).
final class SheetSpinner extends SheetBlock {
  const SheetSpinner({required this.title, this.text});

  final String title;
  final String? text;

  @override
  List<Object?> get props => [title, text];
}

/// What [TaskSheet] draws: a head, the blocks, a foot with a note and two
/// buttons.
final class TaskSheetVm extends Equatable {
  const TaskSheetVm({
    required this.title,
    required this.blocks,
    this.sub,
    this.pill,
    this.pillTone = Tone.neutral,
    this.note,
    this.secondary,
    this.primary,
    this.primaryEnabled = true,
    this.primaryReason,
    this.primaryQuiet = false,
    this.busy = false,
  });

  final String title;
  final String? sub;
  final String? pill;
  final Tone pillTone;
  final List<SheetBlock> blocks;

  /// The foot's note (the rights it needs, the audit names).
  final String? note;
  final String? secondary;
  final String? primary;
  final bool primaryEnabled;
  final String? primaryReason;

  /// The primary is a neutral button (a rollback offered after a success).
  final bool primaryQuiet;

  /// A call is in flight: the primary shows a spinner and is off.
  final bool busy;

  @override
  List<Object?> get props => [
    title,
    sub,
    pill,
    pillTone,
    blocks,
    note,
    secondary,
    primary,
    primaryEnabled,
    primaryReason,
    primaryQuiet,
    busy,
  ];
}

/// The boards `LinkUpdate*` (a drawer, 460), `Backup*`, `LinkBackup` and
/// `BrokerUpdate*` (dialogs, 680 and 640): one task with its review, its
/// progress and its result, made of [SheetBlock]s.
///
/// A drawer fills its height and stands on `ground1` with cards on
/// `ground2`; a dialog is a panel on `ground2` with cards on `ground1`
/// ([dialog]). The blocks scroll between the head and the foot.
class TaskSheet extends StatelessWidget {
  const TaskSheet({
    required this.vm,
    this.dialog = false,
    this.width = 460,
    this.maxHeight = 860,
    this.onPrimary,
    this.onSecondary,
    this.onClose,
    super.key,
  });

  final TaskSheetVm vm;
  final bool dialog;
  final double width;
  final double maxHeight;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;

  /// Closes the sheet from its head (a drawer has no barrier to tap).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final surface = dialog ? c.ground2 : c.ground1;
    final card = dialog ? c.ground1 : c.ground2;
    final pad = dialog ? 24.0 : 20.0;
    final head = Padding(
      padding: dialog ? Insets.sheetHeadDialog : Insets.sheetHead,
      child: Column(
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: Text(
                  vm.title,
                  style: TextStyle(
                    fontSize: dialog
                        ? FontSizes.panelTitle
                        : FontSizes.sheetTitle,
                    fontWeight: .w600,
                    color: c.text1,
                  ),
                ),
              ),
              if (vm.pill case final p?)
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  alignment: .center,
                  decoration: BoxDecoration(
                    color: toneTint(c, vm.pillTone),
                    borderRadius: Radii.pill,
                  ),
                  child: Text(
                    p,
                    style: TextStyle(
                      fontSize: FontSizes.xs,
                      color: vm.pillTone == .neutral
                          ? c.text3
                          : toneColor(c, vm.pillTone),
                    ),
                  ),
                ),
              if (onClose != null)
                InkWell(
                  onTap: onClose,
                  borderRadius: Radii.chip,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: AppIconView(
                      AppIcon.uiClose,
                      size: IconSizes.md,
                      color: c.text3,
                    ),
                  ),
                ),
            ],
          ),
          if (vm.sub case final s? when s.isNotEmpty)
            Text(
              s,
              style: TextStyle(
                fontSize: FontSizes.md,
                height: LineHeights.body,
                color: c.text3,
              ),
            ),
        ],
      ),
    );
    final body = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        pad,
        dialog ? AppSpacing.sm : AppSpacing.md,
        pad,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final (i, b) in vm.blocks.indexed)
            Padding(
              // A field is found again by its slot when the blocks before it
              // change (a check adds cards above the passphrase), so what
              // was typed stays in it.
              key: b is SheetField ? ValueKey(('block', b.slot)) : null,
              padding: i == 0
                  ? EdgeInsets.zero
                  : EdgeInsets.only(top: _gap(vm.blocks, i)),
              child: _block(context, b, card),
            ),
        ],
      ),
    );
    final foot = Container(
      padding: dialog ? Insets.sheetFootDialog : Insets.sheetFoot,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              vm.note ?? '',
              style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
            ),
          ),
          if (vm.secondary case final s?)
            Button.secondary(label: s, onPressed: onSecondary),
          if (vm.primary case final p?)
            if (vm.busy)
              Button.primary(label: p, icon: AppIcon.uiSpinner, onPressed: null)
            else if (vm.primaryQuiet)
              Button.secondary(
                label: p,
                onPressed: vm.primaryEnabled ? onPrimary : null,
                disabledReason: vm.primaryReason,
              )
            else
              Button.primary(
                label: p,
                onPressed: vm.primaryEnabled ? onPrimary : null,
                disabledReason: vm.primaryReason,
              ),
        ],
      ),
    );
    final column = Column(
      mainAxisSize: dialog ? .min : .max,
      crossAxisAlignment: .stretch,
      children: [
        head,
        if (!dialog) Divider(height: 1, thickness: 1, color: c.line1),
        if (dialog) Flexible(child: body) else Expanded(child: body),
        foot,
      ],
    );
    if (dialog) {
      return Dialog(
        backgroundColor: surface,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadii.dialog),
          ),
          side: BorderSide(color: c.line2),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
          child: column,
        ),
      );
    }
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: surface,
        border: Border(left: BorderSide(color: c.line1)),
      ),
      child: Material(type: .transparency, child: column),
    );
  }

  /// The space above block [i]: a label opens a section, the lines of one
  /// list sit close.
  static double _gap(List<SheetBlock> blocks, int i) {
    final b = blocks[i];
    final before = blocks[i - 1];
    if (b is SheetLabel) {
      return 18;
    }
    if (before is SheetLabel) {
      return 8;
    }
    if (b is SheetRow && before is SheetRow) {
      return b.divider ? 0 : 6;
    }
    if (b is SheetCard && before is SheetCard ||
        b is SheetSection && before is SheetSection) {
      return 6;
    }
    if (b is SheetOption && before is SheetOption) {
      return 10;
    }
    return 12;
  }

  Widget _block(BuildContext context, SheetBlock b, Color card) {
    final c = context.colors;
    switch (b) {
      case SheetLabel(:final text):
        return Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: FontSizes.sm,
            fontWeight: .w600,
            letterSpacing: Trackings.label,
            color: c.text4,
          ),
        );
      case SheetText(:final text, :final small, :final tone):
        return Text(
          text,
          style: TextStyle(
            fontSize: small ? FontSizes.sm : FontSizes.md,
            height: LineHeights.body,
            color: tone == .neutral
                ? (small ? c.text4 : c.text2)
                : toneColor(c, tone),
          ),
        );
      case SheetBullets(:final lines, :final numbered):
        return Column(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            for (final (i, line) in lines.indexed)
              Row(
                crossAxisAlignment: .start,
                spacing: 10,
                children: [
                  if (numbered)
                    Text(
                      '${i + 1}',
                      style: mono(color: c.emberSoft),
                    )
                  else
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: c.ember,
                        shape: .circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: FontSizes.md,
                        height: LineHeights.body,
                        color: c.text2,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );
      case SheetCard(:final title, :final detail, :final tone):
        return Container(
          padding: Insets.innerBox,
          decoration: BoxDecoration(
            color: card,
            borderRadius: Radii.control,
            border: .all(
              color: tone == .warn || tone == .bad
                  ? toneLine(c, tone)
                  : c.line1,
            ),
          ),
          child: Row(
            crossAxisAlignment: .start,
            spacing: 10,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: Insets.sheetCardDot,
                decoration: BoxDecoration(
                  color: toneColor(c, tone),
                  shape: .circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: FontSizes.md, color: c.text1),
                    ),
                    if (detail != null && detail.isNotEmpty)
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: FontSizes.sm,
                          height: LineHeights.row,
                          color: c.text4,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      case SheetOption():
        final row = CheckRow(
          label: b.label,
          vm: FieldVm(
            value: b.value,
            enabled: b.enabled && b.onChanged != null,
            onChanged: (v) => b.onChanged?.call(v),
          ),
        );
        final shown = b.enabled ? row : Opacity(opacity: 0.55, child: row);
        return b.reason == null
            ? shown
            : Tooltip(message: b.reason, child: shown);
      case SheetSection():
        return _section(context, b, card);
      case SheetSteps(:final steps):
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            for (final s in steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: .start,
                  spacing: 12,
                  children: [
                    SizedBox.square(
                      dimension: AppSizes.stepMark,
                      child: switch (s.state) {
                        .now => ArcSpinner(color: c.ember, size: 20),
                        .done => DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.goodTint,
                            shape: .circle,
                            border: .all(color: c.good, width: 2),
                          ),
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: c.good,
                                shape: .circle,
                              ),
                            ),
                          ),
                        ),
                        .todo => DecoratedBox(
                          decoration: BoxDecoration(
                            shape: .circle,
                            border: .all(color: c.line3, width: 2),
                          ),
                        ),
                      },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        spacing: 2,
                        children: [
                          Text(
                            s.title,
                            style: TextStyle(
                              fontSize: FontSizes.md,
                              color: s.state == .todo ? c.text4 : c.text1,
                            ),
                          ),
                          if (s.detail case final d? when d.isNotEmpty)
                            Text(
                              d,
                              style: mono(size: FontSizes.xs, color: c.text4),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case SheetBanner(:final title, :final text, :final tone):
        return Semantics(
          liveRegion: true,
          child: Container(
            padding: Insets.notice,
            decoration: BoxDecoration(
              color: toneTint(c, tone),
              borderRadius: Radii.card,
              border: .all(color: toneLine(c, tone)),
            ),
            child: Row(
              crossAxisAlignment: .start,
              spacing: 12,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: Insets.rowDot,
                  decoration: BoxDecoration(
                    color: toneColor(c, tone),
                    shape: .circle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 4,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: FontSizes.lg,
                          fontWeight: .w600,
                          color: c.text1,
                        ),
                      ),
                      if (text != null && text.isNotEmpty)
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: FontSizes.md,
                            height: LineHeights.body,
                            color: c.text2,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case SheetTiles(:final tiles):
        return Row(
          spacing: 8,
          children: [
            for (final t in tiles)
              Expanded(
                child: Container(
                  padding: Insets.innerBox,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: Radii.control,
                    border: .all(color: c.line1),
                  ),
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      Text(
                        t.number,
                        style: mono(
                          size: FontSizes.value,
                          color: t.tone == .neutral
                              ? c.text1
                              : toneColor(c, t.tone),
                        ),
                      ),
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: FontSizes.sm,
                          color: c.text4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      case SheetRow():
        return _row(context, b);
      case SheetFacts(:final facts):
        return FactGrid(facts: facts, labelWidth: 140);
      case SheetField():
        return _SheetInput(
          key: ValueKey(b.slot),
          field: b,
          ground: card,
        );
      case SheetChoice():
        return _choice(context, b);
      case SheetCode(:final text):
        return Container(
          padding: Insets.box,
          decoration: BoxDecoration(
            color: c.ground0,
            borderRadius: Radii.control,
            border: .all(color: c.line1),
          ),
          child: SelectableText(
            text,
            style: mono(size: FontSizes.sm, color: c.text2),
          ),
        );
      case SheetBar(:final percent, :final text):
        return Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            ClipRRect(
              borderRadius: Radii.chip,
              child: SizedBox(
                height: AppSizes.progressBar,
                child: LinearProgressIndicator(
                  value: percent.clamp(0, 100) / 100,
                  backgroundColor: c.ground4,
                  color: c.ember,
                ),
              ),
            ),
            if (text != null && text.isNotEmpty)
              Text(
                text,
                style: TextStyle(fontSize: FontSizes.md, color: c.text2),
              ),
          ],
        );
      case SheetSpinner(:final title, :final text):
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.emberFill,
            borderRadius: Radii.card,
            border: .all(color: c.emberLine),
          ),
          child: Row(
            spacing: 14,
            children: [
              ArcSpinner(color: c.ember, size: 28, strokeWidth: 3),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: FontSizes.lg,
                        fontWeight: .w600,
                        color: c.text1,
                      ),
                    ),
                    if (text != null && text.isNotEmpty)
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: FontSizes.md,
                          color: c.text3,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _row(BuildContext context, SheetRow b) {
    final c = context.colors;
    final tap = b.onAction;
    final row = Row(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        if (b.sign case final s?)
          SizedBox(
            width: AppSizes.changeSign,
            child: Text(
              s,
              style: TextStyle(
                fontSize: FontSizes.sm,
                color: toneColor(c, b.tone),
              ),
            ),
          ),
        Expanded(
          // A row of a list with a line above it (a restore point) keeps
          // its note under the text; a plain line has it at the right.
          child: Column(
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Text(
                b.text,
                style: b.mono
                    ? mono(size: FontSizes.sm, color: c.text2)
                    : TextStyle(fontSize: FontSizes.md, color: c.text2),
              ),
              if (b.divider && (b.note ?? '').isNotEmpty)
                Text(
                  b.note!,
                  style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
                ),
            ],
          ),
        ),
        if (b.note case final n? when n.isNotEmpty && !b.divider)
          Flexible(
            child: Text(
              n,
              textAlign: .end,
              style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
            ),
          ),
        if (b.actionLabel != null)
          InkWell(
            onTap: tap,
            borderRadius: Radii.chip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(
                b.actionLabel!,
                style: TextStyle(
                  fontSize: FontSizes.sm,
                  color: tap == null ? c.muted : c.emberSoft,
                ),
              ),
            ),
          ),
      ],
    );
    if (!b.divider) {
      return row;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: row,
    );
  }

  Widget _section(BuildContext context, SheetSection b, Color card) {
    final c = context.colors;
    final toggle = b.locked ? null : b.onChanged;
    final head = InkWell(
      onTap: toggle == null ? null : () => toggle(!b.on),
      borderRadius: Radii.chip,
      child: Row(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          Padding(
            padding: Insets.iconInBody,
            child: _Box(on: b.on, dim: b.locked),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Row(
                  crossAxisAlignment: .baseline,
                  textBaseline: .alphabetic,
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: .baseline,
                        textBaseline: .alphabetic,
                        spacing: 8,
                        children: [
                          Flexible(
                            child: Text(
                              b.name,
                              style: TextStyle(
                                fontSize: FontSizes.lg,
                                fontWeight: .w600,
                                color: c.text1,
                              ),
                            ),
                          ),
                          if (b.tag case final t?)
                            Container(
                              padding: Insets.sheetTag,
                              decoration: BoxDecoration(
                                color: toneTint(c, b.tagTone),
                                borderRadius: Radii.chip,
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: FontSizes.xs,
                                  color: b.tagTone == .neutral
                                      ? c.text3
                                      : toneColor(c, b.tagTone),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (b.size case final s?)
                      Text(
                        s,
                        style: mono(size: FontSizes.sm, color: c.text3),
                      ),
                  ],
                ),
                if (b.detail case final d? when d.isNotEmpty)
                  Text(
                    d,
                    style: TextStyle(
                      fontSize: FontSizes.sm,
                      height: LineHeights.row,
                      color: c.text4,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final body = Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        if (b.reason == null) head else Tooltip(message: b.reason, child: head),
        if (b.on && b.chips.isNotEmpty)
          Padding(
            padding: Insets.sheetChips,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in b.chips)
                  _Chip(chip: chip, multi: b.multi, onTap: chip.onTap),
              ],
            ),
          ),
      ],
    );
    return Opacity(
      opacity: b.on ? 1 : 0.55,
      child: Container(
        padding: Insets.innerBox,
        decoration: BoxDecoration(
          color: card,
          borderRadius: Radii.control,
          border: .all(color: b.on ? c.line2 : c.line1),
        ),
        child: body,
      ),
    );
  }

  Widget _choice(BuildContext context, SheetChoice b) {
    final c = context.colors;
    void pick(SheetChoiceOption o) {
      if (o.reason == null) {
        o.onPick?.call();
      }
    }

    Widget wrap(SheetChoiceOption o, Widget w) => switch (o.reason) {
      final r? => Tooltip(
        message: r,
        child: Opacity(opacity: 0.55, child: w),
      ),
      null => w,
    };

    final Widget options;
    if (b.lines) {
      options = Column(
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          for (final o in b.options)
            wrap(
              o,
              InkWell(
                onTap: () => pick(o),
                borderRadius: Radii.chip,
                child: Row(
                  crossAxisAlignment: .start,
                  spacing: 10,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      margin: Insets.radioMark,
                      decoration: BoxDecoration(
                        shape: .circle,
                        border: .all(
                          color: o.selected ? c.ember : c.line3,
                          width: o.selected ? 4 : 1,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        o.label,
                        style: TextStyle(
                          fontSize: FontSizes.md,
                          height: LineHeights.body,
                          color: c.text2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    } else {
      options = Container(
        padding: Insets.segmentTrack,
        decoration: BoxDecoration(
          color: c.ground3,
          borderRadius: Radii.control,
        ),
        child: Row(
          spacing: 4,
          children: [
            for (final o in b.options)
              Expanded(
                child: wrap(
                  o,
                  Material(
                    color: o.selected ? c.ground4 : Colors.transparent,
                    borderRadius: Radii.segment,
                    child: InkWell(
                      onTap: () => pick(o),
                      borderRadius: Radii.segment,
                      child: SizedBox(
                        height: AppSizes.sheetSegment,
                        child: Center(
                          child: Text(
                            o.label,
                            overflow: .ellipsis,
                            style: TextStyle(
                              fontSize: FontSizes.md,
                              color: o.selected ? c.text1 : c.text3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        if (b.label case final l?)
          Text(
            l,
            style: TextStyle(fontSize: FontSizes.md, color: c.text2),
          ),
        options,
        if (b.note case final n?)
          Text(
            n,
            style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
          ),
      ],
    );
  }
}

/// The 16 px box of a section card.
class _Box extends StatelessWidget {
  const _Box({required this.on, required this.dim});

  final bool on;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: on ? (dim ? c.emberLine : c.ember) : c.ground2,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mark)),
        border: on ? null : .all(color: c.line3),
      ),
      child: on
          ? AppIconView(AppIcon.uiCheck, size: IconSizes.xs, color: c.onEmber)
          : null,
    );
  }
}

/// A chip under a section: a range to choose or a link to tick.
class _Chip extends StatelessWidget {
  const _Chip({required this.chip, required this.multi, this.onTap});

  final SheetChip chip;
  final bool multi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = chip.on;
    final picked = on && !multi;
    return Semantics(
      checked: on,
      button: true,
      child: Material(
        color: picked ? c.emberTint : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: picked ? c.emberLine : c.line2),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: Insets.sheetPill,
            child: Row(
              mainAxisSize: .min,
              spacing: 6,
              children: [
                if (multi)
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: on ? c.ember : Colors.transparent,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadii.mark),
                      ),
                      border: on ? null : .all(color: c.line3),
                    ),
                    child: on
                        ? AppIconView(
                            AppIcon.uiCheck,
                            size: IconSizes.tick,
                            color: c.onEmber,
                          )
                        : null,
                  ),
                Text(
                  chip.label,
                  style: TextStyle(
                    fontSize: FontSizes.sm,
                    color: picked ? c.emberSoft : (multi ? c.text2 : c.text3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The input of a [SheetField]. It owns its text: a secret is never handed
/// back by the view-model.
class _SheetInput extends StatefulWidget {
  const _SheetInput({
    required this.field,
    required this.ground,
    super.key,
  });

  final SheetField field;
  final Color ground;

  @override
  State<_SheetInput> createState() => _SheetInputState();
}

class _SheetInputState extends State<_SheetInput> {
  late final _text = TextEditingController(
    text: widget.field.secret ? '' : widget.field.value ?? '',
  );

  @override
  void didUpdateWidget(_SheetInput old) {
    super.didUpdateWidget(old);
    final f = widget.field;
    if (!f.secret && f.value != null && f.value != _text.text) {
      _text.text = f.value!;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = widget.field;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: Radii.input,
      borderSide: BorderSide(color: color),
    );
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Text(
          f.label,
          style: TextStyle(fontSize: FontSizes.md, color: c.text2),
        ),
        SizedBox(
          height: AppSizes.sheetField,
          child: TextField(
            controller: _text,
            enabled: f.enabled,
            obscureText: f.secret,
            enableSuggestions: !f.secret,
            autocorrect: false,
            onChanged: f.onChanged,
            style: TextStyle(fontSize: FontSizes.lg, color: c.text1),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: widget.ground,
              hintText: f.hint,
              hintStyle: TextStyle(fontSize: FontSizes.lg, color: c.muted),
              contentPadding: Insets.sheetField,
              border: border(c.line2),
              enabledBorder: border(f.error == null ? c.line2 : c.bad),
              disabledBorder: border(c.line1),
              focusedBorder: border(f.error == null ? c.ember : c.bad),
            ),
          ),
        ),
        if (f.error case final e?)
          Text(
            e,
            style: TextStyle(fontSize: FontSizes.sm, color: c.badText),
          )
        else if (f.note case final n?)
          Text(
            n,
            style: TextStyle(
              fontSize: FontSizes.sm,
              height: LineHeights.row,
              color: c.text4,
            ),
          ),
      ],
    );
  }
}
