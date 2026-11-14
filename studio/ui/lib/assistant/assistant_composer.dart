import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One `@` chip of the composer: the node's full key and what is shown.
typedef ChipVm = (String key, String label);

/// The ask box: the `@` chips and *+ from Explorer*, a field that keeps
/// the draft, and Ask (Cmd+Enter). In the Assistant tab and its drawer.
class AssistantComposer extends StatefulWidget {
  const AssistantComposer({
    required this.draft,
    required this.hint,
    required this.label,
    required this.onDraft,
    required this.onAsk,
    this.reason,
    this.chips = const [],
    this.onChipRemove,
    this.addChipLabel,
    this.addChipReason,
    this.onAddChip,
    this.dense = false,
    super.key,
  });

  final String draft;
  final String hint;
  final String label;
  final String? reason;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;
  final List<ChipVm> chips;
  final ValueChanged<String>? onChipRemove;
  final String? addChipLabel;
  final String? addChipReason;
  final VoidCallback? onAddChip;

  /// The drawer's density: smaller margins.
  final bool dense;

  @override
  State<AssistantComposer> createState() => _AssistantComposerState();
}

class _AssistantComposerState extends State<AssistantComposer> {
  late final _text = TextEditingController(text: widget.draft);

  @override
  void didUpdateWidget(AssistantComposer old) {
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
    final add = widget.addChipLabel;
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
    );
    return Container(
      padding: widget.dense
          ? const EdgeInsets.fromLTRB(14, 10, 14, 12)
          : const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          if (widget.chips.isNotEmpty || add != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: .center,
              children: [
                for (final (key, label) in widget.chips)
                  Tooltip(
                    message: key,
                    child: Container(
                      height: 24,
                      padding: const EdgeInsets.only(left: 8, right: 2),
                      decoration: BoxDecoration(
                        color: c.ground3,
                        border: Border.all(color: c.line2),
                        borderRadius: Radii.chip,
                      ),
                      child: Row(
                        mainAxisSize: .min,
                        children: [
                          Text(
                            '@ $label',
                            style: mono(size: 12, color: c.text1),
                          ),
                          InkWell(
                            onTap: widget.onChipRemove == null
                                ? null
                                : () => widget.onChipRemove!(key),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: AppIcon(
                                'ui_close',
                                size: 12,
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
                    message: widget.addChipReason ?? '',
                    child: InkWell(
                      onTap: widget.addChipReason == null
                          ? widget.onAddChip
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          add,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.addChipReason == null
                                ? c.text2
                                : c.text4,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          box,
        ],
      ),
    );
  }
}
