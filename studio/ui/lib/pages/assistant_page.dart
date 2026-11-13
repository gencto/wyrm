import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../assistant/conversation.dart';
import '../assistant/task_list.dart';
import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/fact_grid.dart';
import '../containers/section_label.dart';
import '../indicators/status_pill.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// A button under the selected task (Approve, Reject, Cancel).
final class TaskButtonVm extends Equatable {
  const TaskButtonVm({
    required this.id,
    required this.label,
    this.primary = false,
    this.danger = false,
    this.disabledReason,
  });

  final String id;
  final String label;
  final bool primary;
  final bool danger;
  final String? disabledReason;

  @override
  List<Object?> get props => [id, label, primary, danger, disabledReason];
}

/// The card that closes the conversation: what the task waits for, a
/// note (why the plan is not shown yet), and its buttons.
final class TaskCardVm extends Equatable {
  const TaskCardVm({
    required this.title,
    required this.note,
    this.caution = false,
    this.buttons = const [],
  });

  final String title;
  final String note;

  /// The note asks for attention (a plan that waits, a task that failed):
  /// it is drawn on the warning tint. Else it is plain grey text.
  final bool caution;
  final List<TaskButtonVm> buttons;

  @override
  List<Object?> get props => [title, note, caution, buttons];
}

/// One `kind  key` row of WHAT IT READ.
typedef ReadRow = (String kind, String key);

/// Board *Assistant*: tasks on the left, the selected task's conversation
/// with its card and the ask box in the middle, *This task* and *What it
/// may do* on the right. With [empty] set (no agent link on the site) the
/// middle shows it and [emptyAction] instead.
class AssistantPage extends StatelessWidget {
  const AssistantPage({
    required this.newLabel,
    required this.listNote,
    required this.sections,
    required this.onNew,
    required this.onTask,
    required this.events,
    required this.draft,
    required this.askHint,
    required this.askLabel,
    required this.onDraft,
    required this.onAsk,
    required this.panels,
    required this.panel,
    required this.onPanel,
    required this.facts,
    required this.readsLabel,
    required this.reads,
    required this.panelNote,
    required this.onButton,
    this.title,
    this.status,
    this.taskKey,
    this.card,
    this.askReason,
    this.empty,
    this.emptyAction,
    this.onEmptyAction,
    super.key,
  });

  final String newLabel;
  final String listNote;
  final List<TaskSectionVm> sections;
  final VoidCallback onNew;
  final ValueChanged<String> onTask;

  final String? title;
  final StatusPillVm? status;

  /// `tasks/t-0142`.
  final String? taskKey;
  final List<ConversationEventVm> events;
  final TaskCardVm? card;
  final ValueChanged<String> onButton;

  final String draft;
  final String askHint;
  final String askLabel;

  /// Why asking is not possible (no write on the agent, no agent).
  final String? askReason;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;

  final List<TabItemVm> panels;
  final String panel;
  final ValueChanged<String> onPanel;
  final List<FactVm> facts;
  final String readsLabel;
  final List<ReadRow> reads;
  final String panelNote;

  final String? empty;
  final String? emptyAction;
  final VoidCallback? onEmptyAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final left = Container(
      width: 240,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(right: BorderSide(color: c.line1)),
      ),
      child: TaskList(
        newLabel: newLabel,
        note: listNote,
        sections: sections,
        onNew: onNew,
        onTask: onTask,
        newReason: empty,
      ),
    );
    final Widget middle;
    if (empty case final e?) {
      middle = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: .min,
            spacing: 16,
            children: [
              Text(
                e,
                textAlign: .center,
                style: TextStyle(fontSize: 14, height: 1.5, color: c.text2),
              ),
              if (emptyAction case final a?)
                Button.primary(
                  label: a,
                  icon: 'ui_add',
                  onPressed: onEmptyAction,
                ),
            ],
          ),
        ),
      );
    } else {
      middle = Column(
        crossAxisAlignment: .stretch,
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line1)),
            ),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Text(
                    title ?? '',
                    overflow: .ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                ),
                if (status case final s?) StatusPill(vm: s, dense: true),
                if (taskKey case final k?)
                  Text(k, style: mono(size: 12, color: c.text3)),
              ],
            ),
          ),
          Expanded(
            child: Conversation(
              events: events,
              trailing: card == null
                  ? null
                  : _Card(vm: card!, onButton: onButton),
            ),
          ),
          _Composer(
            draft: draft,
            hint: askHint,
            label: askLabel,
            reason: askReason,
            onDraft: onDraft,
            onAsk: onAsk,
          ),
        ],
      );
    }
    final right = Container(
      width: 300,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(left: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          SegmentedTabs(tabs: panels, selected: panel, onSelect: onPanel),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                FactGrid(facts: facts, labelWidth: 96),
                if (reads.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SectionLabel(readsLabel),
                  const SizedBox(height: 8),
                  for (final (kind, key) in reads)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: .start,
                        spacing: 8,
                        children: [
                          Text(kind, style: mono(size: 12, color: c.good)),
                          Expanded(
                            child: Text(
                              key,
                              style: mono(size: 12, color: c.text2),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (panelNote.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    panelNote,
                    style: TextStyle(fontSize: 12, height: 1.5, color: c.text3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return ColoredBox(
      color: c.ground0,
      child: Row(
        crossAxisAlignment: .stretch,
        children: [
          left,
          Expanded(child: middle),
          right,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.vm, required this.onButton});

  final TaskCardVm vm;
  final ValueChanged<String> onButton;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(left: 42),
      // the note's band ends at the card's rounded corners
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border.all(color: c.line2),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: SectionLabel(vm.title),
          ),
          Container(
            color: vm.caution ? c.warnTint : null,
            padding: vm.caution
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                : const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
              vm.note,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: vm.caution ? c.warn : c.text3,
              ),
            ),
          ),
          if (vm.buttons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: .end,
                children: [
                  for (final b in vm.buttons)
                    if (b.primary)
                      Button.primary(
                        label: b.label,
                        disabledReason: b.disabledReason,
                        onPressed: b.disabledReason == null
                            ? () => onButton(b.id)
                            : null,
                      )
                    else if (b.danger)
                      Button.danger(
                        label: b.label,
                        disabledReason: b.disabledReason,
                        onPressed: b.disabledReason == null
                            ? () => onButton(b.id)
                            : null,
                      )
                    else
                      Button.secondary(
                        label: b.label,
                        disabledReason: b.disabledReason,
                        onPressed: b.disabledReason == null
                            ? () => onButton(b.id)
                            : null,
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The ask box: a field that keeps the draft, and Ask (Cmd+Enter).
class _Composer extends StatefulWidget {
  const _Composer({
    required this.draft,
    required this.hint,
    required this.label,
    required this.onDraft,
    required this.onAsk,
    this.reason,
  });

  final String draft;
  final String hint;
  final String label;
  final String? reason;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late final _text = TextEditingController(text: widget.draft);

  @override
  void didUpdateWidget(_Composer old) {
    super.didUpdateWidget(old);
    if (widget.draft != _text.text) {
      _text.text = widget.draft;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _can => widget.reason == null && widget.draft.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Row(
        crossAxisAlignment: .end,
        spacing: 10,
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(.enter, meta: true): () {
                  if (_can) {
                    widget.onAsk();
                  }
                },
              },
              child: TextField(
                controller: _text,
                enabled: widget.reason == null,
                minLines: 1,
                maxLines: 6,
                onChanged: widget.onDraft,
                style: TextStyle(fontSize: 14, color: c.text1),
                decoration: InputDecoration(
                  hintText: widget.reason ?? widget.hint,
                  isDense: true,
                ),
              ),
            ),
          ),
          Button.primary(
            label: widget.label,
            disabledReason: widget.reason,
            onPressed: _can ? widget.onAsk : null,
          ),
        ],
      ),
    );
  }
}
