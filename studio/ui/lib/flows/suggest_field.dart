import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What [SuggestField] draws: the [value] typed, and the [choices] its menu
/// offers. Any other text may be typed too (an IANA zone the list does not
/// hold, a range `2026-10/2026-11`).
final class SuggestFieldVm extends Equatable {
  const SuggestFieldVm({
    required this.id,
    required this.value,
    required this.choices,
    this.menuLabel = 'Choose a value',
  });

  final String id;
  final String value;
  final List<String> choices;

  /// The tooltip of the menu button.
  final String menuLabel;

  @override
  List<Object?> get props => [id, value, choices, menuLabel];
}

/// A field of the flow inspector (flow-editor.md §6) whose value is a text
/// the engine reads, with a menu of the usual ones: a time zone (`UTC`, an
/// IANA name, `±HH:MM`), a range text (`today`, `lastWeek`,
/// `current24hours`). 32 high, mono 12; the chevron at its end opens the
/// menu, and a pick writes the choice into the field.
class SuggestField extends StatefulWidget {
  const SuggestField({
    required this.vm,
    required this.decoration,
    required this.onChanged,
    super.key,
  });

  final SuggestFieldVm vm;
  final BoxDecoration decoration;
  final ValueChanged<String> onChanged;

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  late final _controller = TextEditingController(text: widget.vm.value);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(SuggestField old) {
    super.didUpdateWidget(old);
    // It keeps what is typed while it has the focus, else follows the value.
    if (!_focus.hasFocus && _controller.text != widget.vm.value) {
      _controller.text = widget.vm.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _pick(String v) {
    _controller.text = v;
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 32,
      decoration: widget.decoration,
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('suggest-${widget.vm.id}'),
              controller: _controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              autocorrect: false,
              enableSuggestions: false,
              style: mono(size: 12, color: c.text1),
              decoration: const InputDecoration.collapsed(hintText: '')
                  .copyWith(
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
            ),
          ),
          PopupMenuButton<String>(
            key: ValueKey('suggest-menu-${widget.vm.id}'),
            tooltip: widget.vm.menuLabel,
            padding: EdgeInsets.zero,
            color: c.ground3,
            position: .under,
            constraints: const BoxConstraints(maxHeight: 360, minWidth: 200),
            onSelected: _pick,
            itemBuilder: (_) => [
              for (final ch in widget.vm.choices)
                PopupMenuItem(
                  value: ch,
                  height: 32,
                  child: Text(
                    ch,
                    style: mono(
                      size: 12,
                      color: ch == widget.vm.value ? c.ember : c.text1,
                    ),
                  ),
                ),
            ],
            child: SizedBox(
              width: 28,
              height: 32,
              child: Center(
                child: AppIcon('ui_chevron_down', size: 14, color: c.text4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
