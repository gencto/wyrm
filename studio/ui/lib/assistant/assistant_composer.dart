import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'blocked.dart';
import 'task_badge.dart';

/// What the box hints at, by where the task on screen stands (spec
/// `assistant.md` §4).
enum ComposerHint {
  /// A new task.
  ask,

  /// The task waits for the person's answer.
  answer,
  planning,

  /// A plan that waits and that this person may follow up.
  awaiting,
  running,
  done,

  /// A run that failed, about its node.
  failed,

  /// The drawer: about what is on screen.
  drawer,
}

/// What [AssistantComposer] draws.
final class ComposerVm extends Equatable {
  const ComposerVm({
    required this.draft,
    required this.hint,
    this.node = '',
    this.answering = false,
    this.blocked,
    this.chips = const [],
    this.chipBlocked,
    this.replaces = false,
    this.dense = false,
  });

  final String draft;
  final ComposerHint hint;

  /// The key a failed run was about, for its hint.
  final String node;

  /// The task waits for an answer: the box answers it.
  final bool answering;

  /// Why nothing can be sent; null: it can.
  final Blocked? blocked;

  /// The `@` chips: full node keys.
  final List<String> chips;

  /// Why *+ from Explorer* cannot add one.
  final Blocked? chipBlocked;

  /// Sending replaces the plan that waits: said above the field.
  final bool replaces;

  /// The drawer's density: smaller margins.
  final bool dense;

  String get hintText => switch (hint) {
    ComposerHint.ask => S.current.askHint,
    ComposerHint.answer => S.current.answerHint,
    ComposerHint.planning => S.current.hintPlanning,
    ComposerHint.awaiting => S.current.hintAwaiting,
    ComposerHint.running => S.current.hintRunning,
    ComposerHint.done => S.current.hintDone,
    ComposerHint.failed => S.current.hintFailed(lastSegment(node)),
    ComposerHint.drawer => S.current.drawerHint,
  };

  String get label => answering ? S.current.answerButton : S.current.askButton;
  String? get reason => blocked?.text;

  /// *+ from Explorer*; null while the box answers.
  String? get addChipLabel => answering ? null : S.current.addFromExplorer;
  String? get addChipReason => chipBlocked?.text;
  String? get note => replaces ? S.current.composerReplaces : null;

  @override
  List<Object?> get props => [
    draft,
    hint,
    node,
    answering,
    blocked,
    chips,
    chipBlocked,
    replaces,
    dense,
  ];
}

/// The ask box: the `@` chips and *+ from Explorer*, a field that keeps
/// the draft, and Ask (Cmd+Enter). In the Assistant tab and its drawer.
class AssistantComposer extends StatefulWidget {
  const AssistantComposer({
    required this.vm,
    required this.onDraft,
    required this.onAsk,
    this.onChipRemove,
    this.onAddChip,
    super.key,
  });

  final ComposerVm vm;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;
  final ValueChanged<String>? onChipRemove;
  final VoidCallback? onAddChip;

  @override
  State<AssistantComposer> createState() => _AssistantComposerState();
}

class _AssistantComposerState extends State<AssistantComposer> {
  late final _text = TextEditingController(text: widget.vm.draft);

  @override
  void didUpdateWidget(AssistantComposer old) {
    super.didUpdateWidget(old);
    if (widget.vm.draft != _text.text) {
      _text.text = widget.vm.draft;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _can =>
      widget.vm.reason == null && widget.vm.draft.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    final add = vm.addChipLabel;
    final box = Row(
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
              enabled: vm.reason == null,
              minLines: 1,
              maxLines: 6,
              onChanged: widget.onDraft,
              style: TextStyle(fontSize: FontSizes.lg, color: c.text1),
              decoration: InputDecoration(
                hintText: vm.reason ?? vm.hintText,
                isDense: true,
              ),
            ),
          ),
        ),
        Button.primary(
          label: vm.label,
          disabledReason: vm.reason,
          onPressed: _can ? widget.onAsk : null,
        ),
      ],
    );
    return Container(
      padding: vm.dense
          ? const EdgeInsets.fromLTRB(
              14,
              10,
              14,
              12,
            )
          : const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              12,
              AppSpacing.lg,
              AppSpacing.md,
            ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          if (vm.chips.isNotEmpty || add != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: .center,
              children: [
                for (final key in vm.chips)
                  Tooltip(
                    message: key,
                    child: Container(
                      height: 24,
                      padding: Insets.chip,
                      decoration: BoxDecoration(
                        color: c.ground3,
                        border: Border.all(color: c.line2),
                        borderRadius: Radii.chip,
                      ),
                      child: Row(
                        mainAxisSize: .min,
                        children: [
                          Text(
                            '@ ${shortKey(key)}',
                            style: mono(size: FontSizes.sm, color: c.text1),
                          ),
                          InkWell(
                            onTap: widget.onChipRemove == null
                                ? null
                                : () => widget.onChipRemove!(key),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              child: AppIconView(
                                AppIcon.uiClose,
                                size: IconSizes.xs,
                                color: c.text3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (add != null)
                  Tooltip(
                    message: vm.addChipReason ?? '',
                    child: InkWell(
                      onTap: vm.addChipReason == null ? widget.onAddChip : null,
                      child: Padding(
                        padding: Insets.textLink,
                        child: Text(
                          add,
                          style: TextStyle(
                            fontSize: FontSizes.sm,
                            color: vm.addChipReason == null ? c.text2 : c.text4,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          if (vm.note case final n?)
            Text(
              n,
              style: TextStyle(fontSize: FontSizes.sm, color: c.warn),
            ),
          box,
        ],
      ),
    );
  }
}
