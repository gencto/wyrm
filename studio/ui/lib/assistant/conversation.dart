import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'task_badge.dart';

/// What one entry of the conversation is.
enum ConversationKind {
  /// What the person asked, or answered in words (a bubble on the right).
  ask,

  /// The options the person picked on the card (a bubble on the right).
  answer,

  /// A line from the model (a spark and the text).
  text,

  /// What the agent read: [ConversationEventVm.reads] as chips.
  read,

  /// A state the task reached (a mark and the word).
  state,

  /// A line of the record that says what was done (a ring and the text).
  note,

  /// An error from the agent or the broker.
  error,

  /// The agent has no tasks yet.
  noTasks,
}

/// One entry of the conversation.
final class ConversationEventVm extends Equatable {
  const ConversationEventVm({
    required this.kind,
    this.text = '',
    this.reads = const [],
    this.badge,
  });

  /// One read-only tool the model called.
  ConversationEventVm.read(String tool)
    : this(kind: ConversationKind.read, reads: [tool]);

  final ConversationKind kind;

  /// The words: the person's, the model's, the record's.
  final String text;

  /// The tools of a [ConversationKind.read] (`tree modbus/tcp-line2`).
  final List<String> reads;

  /// The state of a [ConversationKind.state].
  final TaskBadge? badge;

  /// What the entry says.
  String get shown => switch (kind) {
    ConversationKind.answer => S.current.choicesFromCard(text),
    ConversationKind.state => badge?.label ?? text,
    ConversationKind.noTasks => S.current.noTasks,
    _ => text,
  };

  /// The tone of a [ConversationKind.state].
  Tone get tone => badge?.tone ?? Tone.neutral;

  @override
  List<Object?> get props => [kind, text, reads, badge];
}

/// [events] with each run of reads in one row of chips.
List<ConversationEventVm> _rows(List<ConversationEventVm> events) {
  final out = <ConversationEventVm>[];
  for (final e in events) {
    if (e.kind == ConversationKind.read &&
        out.lastOrNull?.kind == ConversationKind.read) {
      out.last = ConversationEventVm(
        kind: ConversationKind.read,
        reads: [...out.last.reads, ...e.reads],
      );
    } else {
      out.add(e);
    }
  }
  return out;
}

/// Board *Assistant*: the ask on the right, the model's lines with a spark,
/// what it read as chips, the states it reached; [trailing] (the plan or
/// the task's card) closes it.
class Conversation extends StatelessWidget {
  const Conversation({
    required this.events,
    this.trailing,
    this.dense = false,
    super.key,
  });

  final List<ConversationEventVm> events;
  final Widget? trailing;

  /// The drawer's density: smaller margins.
  final bool dense;

  @override
  Widget build(BuildContext context) => ListView(
    padding: dense ? Insets.conversationDense : Insets.conversation,
    children: [
      for (final e in _rows(events))
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _Event(vm: e),
        ),
      ?trailing,
    ],
  );
}

/// The model's line as spans: `**strong**` in weight 600 and `` `code` ``
/// in [code], the marks left out. A mark with no partner stays as text;
/// nothing else of Markdown is read (the model writes prose, not documents).
List<InlineSpan> modelSpans(String text, {required TextStyle code}) {
  final spans = <InlineSpan>[];
  final plain = StringBuffer();
  void flush() {
    if (plain.isNotEmpty) {
      spans.add(TextSpan(text: plain.toString()));
      plain.clear();
    }
  }

  var i = 0;
  while (i < text.length) {
    final mark = text.startsWith('**', i)
        ? '**'
        : text[i] == '`'
        ? '`'
        : null;
    if (mark != null) {
      final from = i + mark.length;
      final end = text.indexOf(mark, from);
      final inner = end > from ? text.substring(from, end) : '';
      if (inner.trim().isNotEmpty && !inner.contains('\n')) {
        flush();
        spans.add(
          TextSpan(
            text: mark == '`' ? inner.trim() : inner,
            style: mark == '`'
                ? code
                : const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
        i = end + mark.length;
        continue;
      }
    }
    plain.write(text[i]);
    i++;
  }
  flush();
  return spans;
}

class _Event extends StatelessWidget {
  const _Event({required this.vm});

  final ConversationEventVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    switch (vm.kind) {
      case .ask || .answer:
        return Align(
          alignment: .centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Container(
              padding: Insets.askBubble,
              decoration: BoxDecoration(
                color: c.ground3,
                borderRadius: Radii.card,
              ),
              child: SelectableText(
                vm.shown,
                style: TextStyle(
                  fontSize: FontSizes.lg,
                  height: LineHeights.body,
                  color: c.text1,
                ),
              ),
            ),
          ),
        );
      case .text || .noTasks:
        return Row(
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.emberTint,
                borderRadius: Radii.control,
              ),
              child: Center(
                child: AppIconView(
                  AppIcon.wsAssistant,
                  size: IconSizes.md,
                  color: c.ember,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: Insets.answerText,
                child: SelectableText.rich(
                  TextSpan(
                    children: modelSpans(
                      vm.shown,
                      code: mono(color: c.text1),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: FontSizes.lg,
                    height: LineHeights.prose,
                    color: c.text1,
                  ),
                ),
              ),
            ),
          ],
        );
      case .read:
        return Padding(
          padding: Insets.assistantIndent,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in vm.reads)
                Container(
                  padding: Insets.readChip,
                  decoration: BoxDecoration(
                    border: Border.all(color: c.line2),
                    borderRadius: Radii.chip,
                  ),
                  child: Text(
                    'read · $r',
                    style: mono(size: FontSizes.sm, color: c.text3),
                  ),
                ),
            ],
          ),
        );
      case .state || .note:
        return Padding(
          padding: Insets.assistantIndent,
          child: Row(
            spacing: 8,
            children: [
              StateMark(
                mark: vm.tone == .neutral ? Mark.ring : Mark.dot,
                color: vm.tone == .neutral ? c.text3 : toneColor(c, vm.tone),
              ),
              Text(
                vm.shown,
                style: TextStyle(fontSize: FontSizes.md, color: c.text3),
              ),
            ],
          ),
        );
      case .error:
        return Padding(
          padding: Insets.assistantIndent,
          child: Container(
            padding: Insets.innerBox,
            decoration: BoxDecoration(
              color: c.badTint,
              border: Border.all(color: c.badLine),
              borderRadius: Radii.control,
            ),
            child: SelectableText(
              vm.text,
              style: mono(size: FontSizes.sm, color: c.badText),
            ),
          ),
        );
    }
  }
}
