import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// *Probe a range instead* (docs/design/specs/unlock-discover.md §4): the
/// title (13, `text2`), a range and a port in mono 13 (38 high, radius 8)
/// with `Probe` (ember), an error under them when one does not read, and
/// what a probe does (12, `text4`).
class RangeProbe extends StatelessWidget {
  const RangeProbe({
    required this.range,
    required this.port,
    required this.onProbe,
    this.busy = false,
    super.key,
  });

  /// `10.0.7.0/24`; its [FieldVm.error] shows under the row.
  final FieldVm<String?> range;

  /// `8446`; its [FieldVm.error] shows under the row.
  final FieldVm<String?> port;
  final VoidCallback onProbe;

  /// A probe is running: `Probe` does nothing.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final error = range.error ?? port.error;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        Text(
          S.current.probeRangeTitle,
          style: TextStyle(fontSize: 13, color: c.text2),
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: _Small(
                vm: range,
                label: S.current.probeRangeField,
                bad: range.error != null,
                onSubmitted: onProbe,
              ),
            ),
            SizedBox(
              width: 70,
              child: _Small(
                vm: port,
                label: S.current.probePortField,
                bad: port.error != null,
                digits: true,
                onSubmitted: onProbe,
              ),
            ),
            Material(
              color: c.ember,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: InkWell(
                onTap: busy ? null : onProbe,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                child: SizedBox(
                  height: 38,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        S.current.probeButton,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: .w600,
                          color: c.onEmber,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (error != null)
          Text(error, style: TextStyle(fontSize: 12, color: c.badText)),
        Text(
          S.current.probeNote,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            leadingDistribution: .even,
            color: c.text4,
          ),
        ),
      ],
    );
  }
}

/// A small controlled field: mono 13 in a box 38 high, radius 8.
class _Small extends StatefulWidget {
  const _Small({
    required this.vm,
    required this.label,
    required this.onSubmitted,
    this.bad = false,
    this.digits = false,
  });

  final FieldVm<String?> vm;
  final String label;
  final VoidCallback onSubmitted;
  final bool bad;
  final bool digits;

  @override
  State<_Small> createState() => _SmallState();
}

class _SmallState extends State<_Small> {
  late final _text = TextEditingController(text: widget.vm.value ?? '');
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_Small old) {
    super.didUpdateWidget(old);
    final value = widget.vm.value ?? '';
    if (!_focus.hasFocus && value != _text.text) {
      _text.text = value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: widget.label,
      textField: true,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.ground2,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          border: .all(color: widget.bad ? c.badLine : c.line2),
        ),
        alignment: .centerLeft,
        child: TextField(
          controller: _text,
          focusNode: _focus,
          enabled: widget.vm.enabled,
          keyboardType: widget.digits ? .number : .text,
          inputFormatters: [
            if (widget.digits) FilteringTextInputFormatter.digitsOnly,
          ],
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 13,
            height: 1.3,
            color: c.text1,
          ),
          cursorColor: c.ember,
          cursorHeight: 16,
          decoration: const InputDecoration(
            isCollapsed: true,
            filled: false,
            contentPadding: .zero,
            border: .none,
            enabledBorder: .none,
            focusedBorder: .none,
            disabledBorder: .none,
          ),
          onChanged: (v) => widget.vm.onChanged(v.isEmpty ? null : v),
          onSubmitted: (_) => widget.onSubmitted(),
        ),
      ),
    );
  }
}
