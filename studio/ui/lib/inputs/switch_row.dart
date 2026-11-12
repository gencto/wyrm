import 'package:material_ui/material_ui.dart';

import '../indicators/key_text.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';

/// A setting: title, one line of what it does, the key it writes, a switch.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    required this.title,
    required this.vm,
    this.description,
    this.keyName,
    this.disabledReason,
    super.key,
  });

  final String title;
  final String? description;

  /// `sys/allow_all_links`, shown in mono.
  final String? keyName;
  final FieldVm<bool> vm;

  /// Why it cannot be changed (shown instead of the description).
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        spacing: 16,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: .w500,
                    color: vm.enabled ? c.text1 : c.text3,
                  ),
                ),
                if (disabledReason ?? description case final d?)
                  Text(d, style: TextStyle(fontSize: 12, color: c.text3)),
                if (keyName case final k?) KeyText(k, size: 12, color: c.text4),
              ],
            ),
          ),
          AppSwitch(
            value: vm.value,
            onChanged: vm.enabled ? vm.onChanged : null,
          ),
        ],
      ),
    );
    return disabledReason == null
        ? row
        : Tooltip(message: disabledReason, child: row);
  }
}

/// Board *Design system* §06 toggle: 44×26, ember when on, ground/4 with a
/// line/3 border when off.
class AppSwitch extends StatelessWidget {
  const AppSwitch({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(2),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value ? (enabled ? c.ember : c.muted) : c.ground4,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: value ? Colors.transparent : c.line3),
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: .circle,
              color: value ? c.ground0 : c.text4,
            ),
          ),
        ),
      ),
    );
  }
}
