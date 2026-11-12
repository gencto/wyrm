import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What one entry of the conversation is.
enum ConversationKind {
  /// What the person asked (a bubble on the right).
  ask,

  /// A line from the model (a spark and the text).
  text,

  /// What the agent read: [ConversationEventVm.reads] as chips.
  reads,

  /// A state the task reached (a mark and the word).
  state,

  /// An error from the agent or the broker.
  error,
}

/// One entry of the conversation.
final class ConversationEventVm extends Equatable {
  const ConversationEventVm({
    required this.kind,
    this.text = '',
    this.reads = const [],
    this.tone = Tone.neutral,
  });

  final ConversationKind kind;
  final String text;

  /// `read · tree modbus/tcp-line2` chips of a [ConversationKind.reads].
  final List<String> reads;

  /// The tone of a [ConversationKind.state].
  final Tone tone;

  @override
  List<Object?> get props => [kind, text, reads, tone];
}

/// Board *Assistant*: the ask on the right, the model's lines with a spark,
/// what it read as chips, the states it reached; [trailing] (the plan or
/// the task's card) closes it.
class Conversation extends StatelessWidget {
  const Conversation({required this.events, this.trailing, super.key});

  final List<ConversationEventVm> events;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
    children: [
      for (final e in events)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _Event(vm: e),
        ),
      ?trailing,
    ],
  );
}

class _Event extends StatelessWidget {
  const _Event({required this.vm});

  final ConversationEventVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    switch (vm.kind) {
      case .ask:
        return Align(
          alignment: .centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.ground3,
                borderRadius: Radii.card,
              ),
              child: SelectableText(
                vm.text,
                style: TextStyle(fontSize: 14, height: 1.5, color: c.text1),
              ),
            ),
          ),
        );
      case .text:
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
                child: AppIcon('ws_assistant', size: 16, color: c.ember),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: SelectableText(
                  vm.text,
                  style: TextStyle(fontSize: 14, height: 1.55, color: c.text1),
                ),
              ),
            ),
          ],
        );
      case .reads:
        return Padding(
          padding: const EdgeInsets.only(left: 42),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in vm.reads)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.line2),
                    borderRadius: Radii.chip,
                  ),
                  child: Text(r, style: mono(size: 12, color: c.text3)),
                ),
            ],
          ),
        );
      case .state:
        return Padding(
          padding: const EdgeInsets.only(left: 42),
          child: Row(
            spacing: 8,
            children: [
              StateMark(
                mark: vm.tone == .neutral ? Mark.ring : Mark.dot,
                color: vm.tone == .neutral ? c.text3 : toneColor(c, vm.tone),
              ),
              Text(vm.text, style: TextStyle(fontSize: 13, color: c.text3)),
            ],
          ),
        );
      case .error:
        return Padding(
          padding: const EdgeInsets.only(left: 42),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.badTint,
              border: Border.all(color: c.badLine),
              borderRadius: Radii.control,
            ),
            child: SelectableText(
              vm.text,
              style: mono(size: 12, color: c.badText),
            ),
          ),
        );
    }
  }
}
