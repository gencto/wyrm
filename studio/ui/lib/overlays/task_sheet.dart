import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/fact_grid.dart';
import '../indicators/app_icon.dart';
import '../indicators/arc_spinner.dart';
import '../indicators/quality_mark.dart';
import '../inputs/check_row.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
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
final class SheetOption extends SheetBlock {
  const SheetOption({
    required this.id,
    required this.label,
    required this.value,
    this.enabled = true,
    this.reason,
  });

  final String id;
  final String label;
  final bool value;
  final bool enabled;
  final String? reason;

  @override
  List<Object?> get props => [id, label, value, enabled, reason];
}

/// A chip of a [SheetSection]: one of a range, or one of a set.
final class SheetChip extends Equatable {
  const SheetChip({required this.id, required this.label, this.on = false});

  final String id;
  final String label;
  final bool on;

  @override
  List<Object?> get props => [id, label, on];
}

/// A section of a backup as a card: a checkbox, its name, a tag, its size,
/// what it holds, and chips under it (a range to pick one of, or links to
/// tick). Dimmed when off; the checkbox is fixed when [locked].
final class SheetSection extends SheetBlock {
  const SheetSection({
    required this.id,
    required this.name,
    required this.on,
    this.detail,
    this.locked = false,
    this.reason,
    this.tag,
    this.tagTone = Tone.neutral,
    this.size,
    this.chips = const [],
    this.chipGroup,
    this.multi = false,
  });

  final String id;
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

  /// The id the chips report under ([TaskSheet.onPick]).
  final String? chipGroup;

  /// The chips are ticked one by one; else one of them is chosen.
  final bool multi;

  @override
  List<Object?> get props => [
    id,
    name,
    on,
    detail,
    locked,
    reason,
    tag,
    tagTone,
    size,
    chips,
    chipGroup,
    multi,
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
/// on the right that reports [action] ([TaskSheet.onAction]).
final class SheetRow extends SheetBlock {
  const SheetRow({
    required this.text,
    this.sign,
    this.tone = Tone.neutral,
    this.note,
    this.mono = true,
    this.action,
    this.actionLabel,
    this.divider = false,
  });

  final String text;
  final String? sign;
  final Tone tone;
  final String? note;
  final bool mono;
  final String? action;
  final String? actionLabel;

  /// A line above the row (a list of restore points).
  final bool divider;

  @override
  List<Object?> get props => [
    text,
    sign,
    tone,
    note,
    mono,
    action,
    actionLabel,
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
/// is typed stays in the field and is reported by [TaskSheet.onText].
final class SheetField extends SheetBlock {
  const SheetField({
    required this.id,
    required this.label,
    this.value,
    this.hint,
    this.note,
    this.error,
    this.secret = false,
    this.enabled = true,
  });

  final String id;
  final String label;
  final String? value;
  final String? hint;
  final String? note;
  final String? error;
  final bool secret;
  final bool enabled;

  @override
  List<Object?> get props => [
    id,
    label,
    value,
    hint,
    note,
    error,
    secret,
    enabled,
  ];
}

/// One of a few: segments in a row, or radio lines when [lines]. An option
/// with a reason is shown and cannot be chosen.
final class SheetChoice extends SheetBlock {
  const SheetChoice({
    required this.id,
    required this.options,
    required this.selected,
    this.label,
    this.note,
    this.lines = false,
    this.reasons = const {},
  });

  final String id;
  final String? label;

  /// `(value, label)`.
  final List<(String, String)> options;
  final String selected;
  final String? note;
  final bool lines;
  final Map<String, String> reasons;

  @override
  List<Object?> get props => [
    id,
    label,
    options,
    selected,
    note,
    lines,
    reasons,
  ];
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
    this.onToggle,
    this.onPick,
    this.onText,
    this.onAction,
    this.onClose,
    super.key,
  });

  final TaskSheetVm vm;
  final bool dialog;
  final double width;
  final double maxHeight;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;

  /// A checkbox of a [SheetOption] or a [SheetSection] by its id.
  final void Function(String id, {required bool value})? onToggle;

  /// A chip (`group`, `chip id`) or an option of a [SheetChoice]
  /// (`choice id`, `value`).
  final void Function(String group, String value)? onPick;

  /// The text of a [SheetField] by its id.
  final void Function(String id, String text)? onText;

  /// The link of a [SheetRow].
  final ValueChanged<String>? onAction;

  /// Closes the sheet from its head (a drawer has no barrier to tap).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final surface = dialog ? c.ground2 : c.ground1;
    final card = dialog ? c.ground1 : c.ground2;
    final pad = dialog ? 24.0 : 20.0;
    final head = Padding(
      padding: EdgeInsets.fromLTRB(pad, dialog ? 22 : 18, pad, 12),
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
                    fontSize: dialog ? 20 : 18,
                    fontWeight: .w600,
                    color: c.text1,
                  ),
                ),
              ),
              if (vm.pill case final p?)
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: .center,
                  decoration: BoxDecoration(
                    color: toneTint(c, vm.pillTone),
                    borderRadius: Radii.pill,
                  ),
                  child: Text(
                    p,
                    style: TextStyle(
                      fontSize: 11,
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
                    padding: const EdgeInsets.all(4),
                    child: AppIcon('ui_close', size: 16, color: c.text3),
                  ),
                ),
            ],
          ),
          if (vm.sub case final s? when s.isNotEmpty)
            Text(
              s,
              style: TextStyle(fontSize: 13, height: 1.5, color: c.text3),
            ),
        ],
      ),
    );
    final body = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, dialog ? 8 : 16, pad, 16),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final (i, b) in vm.blocks.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : _gap(vm.blocks, i)),
              child: _block(context, b, card),
            ),
        ],
      ),
    );
    final foot = Container(
      padding: EdgeInsets.fromLTRB(pad, 14, pad, dialog ? 20 : 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              vm.note ?? '',
              style: TextStyle(fontSize: 12, color: c.text4),
            ),
          ),
          if (vm.secondary case final s?)
            Button.secondary(label: s, onPressed: onSecondary),
          if (vm.primary case final p?)
            if (vm.busy)
              Button.primary(label: p, icon: 'ui_spinner', onPressed: null)
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
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
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
            fontSize: 12,
            fontWeight: .w600,
            letterSpacing: 0.72,
            color: c.text4,
          ),
        );
      case SheetText(:final text, :final small, :final tone):
        return Text(
          text,
          style: TextStyle(
            fontSize: small ? 12 : 13,
            height: 1.5,
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
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: c.ember,
                        shape: .circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                margin: const EdgeInsets.only(top: 6),
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
                      style: TextStyle(fontSize: 13, color: c.text1),
                    ),
                    if (detail != null && detail.isNotEmpty)
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
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
            enabled: b.enabled && onToggle != null,
            onChanged: (v) => onToggle?.call(b.id, value: v),
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: .start,
                  spacing: 12,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
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
                              fontSize: 13,
                              color: s.state == .todo ? c.text4 : c.text1,
                            ),
                          ),
                          if (s.detail case final d? when d.isNotEmpty)
                            Text(d, style: mono(size: 11, color: c.text4)),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  margin: const EdgeInsets.only(top: 5),
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
                          fontSize: 14,
                          fontWeight: .w600,
                          color: c.text1,
                        ),
                      ),
                      if (text != null && text.isNotEmpty)
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                          size: 20,
                          color: t.tone == .neutral
                              ? c.text1
                              : toneColor(c, t.tone),
                        ),
                      ),
                      Text(
                        t.label,
                        style: TextStyle(fontSize: 12, color: c.text4),
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
          key: ValueKey('field-${b.id}'),
          field: b,
          ground: card,
          onText: onText,
        );
      case SheetChoice():
        return _choice(context, b);
      case SheetCode(:final text):
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.ground0,
            borderRadius: Radii.control,
            border: .all(color: c.line1),
          ),
          child: SelectableText(text, style: mono(size: 12, color: c.text2)),
        );
      case SheetBar(:final percent, :final text):
        return Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            ClipRRect(
              borderRadius: Radii.chip,
              child: SizedBox(
                height: 8,
                child: LinearProgressIndicator(
                  value: percent.clamp(0, 100) / 100,
                  backgroundColor: c.ground4,
                  color: c.ember,
                ),
              ),
            ),
            if (text != null && text.isNotEmpty)
              Text(text, style: TextStyle(fontSize: 13, color: c.text2)),
          ],
        );
      case SheetSpinner(:final title, :final text):
        return Container(
          padding: const EdgeInsets.all(16),
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
                        fontSize: 14,
                        fontWeight: .w600,
                        color: c.text1,
                      ),
                    ),
                    if (text != null && text.isNotEmpty)
                      Text(
                        text,
                        style: TextStyle(fontSize: 13, color: c.text3),
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
    final link = b.action;
    final row = Row(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        if (b.sign case final s?)
          SizedBox(
            width: 14,
            child: Text(
              s,
              style: TextStyle(fontSize: 12, color: toneColor(c, b.tone)),
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
                    ? mono(size: 12, color: c.text2)
                    : TextStyle(fontSize: 13, color: c.text2),
              ),
              if (b.divider && (b.note ?? '').isNotEmpty)
                Text(
                  b.note!,
                  style: TextStyle(fontSize: 12, color: c.text4),
                ),
            ],
          ),
        ),
        if (b.note case final n? when n.isNotEmpty && !b.divider)
          Flexible(
            child: Text(
              n,
              textAlign: .end,
              style: TextStyle(fontSize: 12, color: c.text4),
            ),
          ),
        if (link != null && b.actionLabel != null)
          InkWell(
            onTap: onAction == null ? null : () => onAction!(link),
            borderRadius: Radii.chip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                b.actionLabel!,
                style: TextStyle(
                  fontSize: 12,
                  color: onAction == null ? c.muted : c.emberSoft,
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: row,
    );
  }

  Widget _section(BuildContext context, SheetSection b, Color card) {
    final c = context.colors;
    final can = !b.locked && onToggle != null;
    final head = InkWell(
      onTap: can ? () => onToggle!(b.id, value: !b.on) : null,
      borderRadius: Radii.chip,
      child: Row(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
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
                                fontSize: 14,
                                fontWeight: .w600,
                                color: c.text1,
                              ),
                            ),
                          ),
                          if (b.tag case final t?)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: toneTint(c, b.tagTone),
                                borderRadius: Radii.chip,
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 11,
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
                      Text(s, style: mono(size: 12, color: c.text3)),
                  ],
                ),
                if (b.detail case final d? when d.isNotEmpty)
                  Text(
                    d,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: c.text4,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final group = b.chipGroup ?? b.id;
    final body = Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        if (b.reason == null) head else Tooltip(message: b.reason, child: head),
        if (b.on && b.chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in b.chips)
                  _Chip(
                    chip: chip,
                    multi: b.multi,
                    onTap: onPick == null
                        ? null
                        : () => onPick!(group, chip.id),
                  ),
              ],
            ),
          ),
      ],
    );
    return Opacity(
      opacity: b.on ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    void pick(String v) {
      if (!b.reasons.containsKey(v)) {
        onPick?.call(b.id, v);
      }
    }

    Widget wrap(String v, Widget w) => switch (b.reasons[v]) {
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
          for (final (v, label) in b.options)
            wrap(
              v,
              InkWell(
                onTap: () => pick(v),
                borderRadius: Radii.chip,
                child: Row(
                  crossAxisAlignment: .start,
                  spacing: 10,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        shape: .circle,
                        border: .all(
                          color: v == b.selected ? c.ember : c.line3,
                          width: v == b.selected ? 4 : 1,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
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
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.ground3,
          borderRadius: Radii.control,
        ),
        child: Row(
          spacing: 4,
          children: [
            for (final (v, label) in b.options)
              Expanded(
                child: wrap(
                  v,
                  Material(
                    color: v == b.selected ? c.ground4 : Colors.transparent,
                    borderRadius: Radii.segment,
                    child: InkWell(
                      onTap: () => pick(v),
                      borderRadius: Radii.segment,
                      child: SizedBox(
                        height: 34,
                        child: Center(
                          child: Text(
                            label,
                            overflow: .ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: v == b.selected ? c.text1 : c.text3,
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
          Text(l, style: TextStyle(fontSize: 13, color: c.text2)),
        options,
        if (b.note case final n?)
          Text(n, style: TextStyle(fontSize: 12, color: c.text4)),
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
        borderRadius: const BorderRadius.all(Radius.circular(3)),
        border: on ? null : .all(color: c.line3),
      ),
      child: on ? AppIcon('ui_check', size: 12, color: c.onEmber) : null,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      borderRadius: const BorderRadius.all(Radius.circular(3)),
                      border: on ? null : .all(color: c.line3),
                    ),
                    child: on
                        ? AppIcon('ui_check', size: 10, color: c.onEmber)
                        : null,
                  ),
                Text(
                  chip.label,
                  style: TextStyle(
                    fontSize: 12,
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
    this.onText,
    super.key,
  });

  final SheetField field;
  final Color ground;
  final void Function(String id, String text)? onText;

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
        Text(f.label, style: TextStyle(fontSize: 13, color: c.text2)),
        SizedBox(
          height: 40,
          child: TextField(
            controller: _text,
            enabled: f.enabled,
            obscureText: f.secret,
            enableSuggestions: !f.secret,
            autocorrect: false,
            onChanged: (v) => widget.onText?.call(f.id, v),
            style: TextStyle(fontSize: 14, color: c.text1),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: widget.ground,
              hintText: f.hint,
              hintStyle: TextStyle(fontSize: 14, color: c.muted),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: border(c.line2),
              enabledBorder: border(f.error == null ? c.line2 : c.bad),
              disabledBorder: border(c.line1),
              focusedBorder: border(f.error == null ? c.ember : c.bad),
            ),
          ),
        ),
        if (f.error case final e?)
          Text(e, style: TextStyle(fontSize: 12, color: c.badText))
        else if (f.note case final n?)
          Text(
            n,
            style: TextStyle(fontSize: 12, height: 1.45, color: c.text4),
          ),
      ],
    );
  }
}
