import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/app_icon.dart';
import '../inputs/switch_row.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// How one parameter is edited (docs/studio.md §6.6).
enum ParamKind {
  /// One line of text.
  text,

  /// Several lines (`editor: textarea`).
  textarea,

  /// A number, with bounds in the hint.
  number,

  /// One of [ParamFieldVm.choices].
  choice,

  /// A switch.
  toggle,

  /// A local file (`editor: file`): picked, never typed.
  file,

  /// A secret: obscured, never prefilled.
  secret,
}

/// One parameter of an action, a link's `cfg` or a plan step, ready to draw.
final class ParamFieldVm extends Equatable {
  const ParamFieldVm({
    required this.id,
    required this.label,
    required this.kind,
    required this.onChanged,
    this.value,
    this.hint,
    this.unit,
    this.choices = const [],
    this.required = false,
    this.error,
    this.enabled = true,
    this.description,
    this.onPickFile,
  });

  /// The parameter name (the `args` key).
  final String id;
  final String label;
  final ParamKind kind;

  /// String for text kinds, num for number, bool for toggle, the file name
  /// for file.
  final Object? value;

  /// The placeholder (`0…255`, `https://…`).
  final String? hint;

  /// A unit shown inside the field (`ms`).
  final String? unit;
  final List<String> choices;
  final bool required;
  final String? error;
  final bool enabled;

  /// One line under the field.
  final String? description;

  /// Behaviour: out of [props].
  final ValueChanged<Object?> onChanged;

  /// Opens the file picker (kind file).
  final VoidCallback? onPickFile;

  @override
  List<Object?> get props => [
    id,
    label,
    kind,
    value,
    hint,
    unit,
    choices,
    required,
    error,
    enabled,
    description,
  ];
}

/// A form built from parameters: label above, the field below (board
/// *Design system* §06 Fields: 36 high, radius 6, ground/3 on line/2).
///
/// Uncontrolled: a field's value seeds it once per [ParamFieldVm.id].
class ParamForm extends StatelessWidget {
  const ParamForm({required this.fields, this.columns = 1, super.key});

  final List<ParamFieldVm> fields;

  /// 2 puts short fields side by side.
  final int columns;

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [for (final f in fields) ParamField(vm: f)],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 14,
          children: [
            for (final f in fields)
              SizedBox(
                width: f.kind == .textarea || f.kind == .file
                    ? box.maxWidth
                    : w,
                child: ParamField(vm: f),
              ),
          ],
        );
      },
    );
  }
}

/// One labelled field of a [ParamForm].
class ParamField extends StatelessWidget {
  const ParamField({required this.vm, super.key});

  final ParamFieldVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (vm.kind == .toggle) {
      return Row(
        children: [
          Expanded(child: _label(c)),
          AppSwitch(
            value: vm.value == true,
            onChanged: vm.enabled ? vm.onChanged : null,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        _label(c),
        _field(context, c),
        if (vm.error case final e?)
          Text(e, style: TextStyle(fontSize: 12, color: c.bad))
        else if (vm.description case final d?)
          Text(d, style: TextStyle(fontSize: 12, color: c.text4)),
      ],
    );
  }

  Widget _label(AppColors c) => Text.rich(
    TextSpan(
      text: vm.label,
      children: [
        if (vm.required)
          TextSpan(
            text: ' *',
            style: TextStyle(color: c.emberSoft),
          ),
      ],
    ),
    style: TextStyle(
      fontSize: 12,
      color: vm.error != null ? c.bad : c.text3,
    ),
  );

  InputDecoration _decoration(AppColors c) => InputDecoration(
    hintText: vm.hint,
    isDense: true,
    filled: true,
    fillColor: c.ground3,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    suffixText: vm.unit,
    suffixStyle: TextStyle(fontSize: 12, color: c.text4),
    hintStyle: TextStyle(fontSize: 13, color: c.text4),
    border: _border(c.line2),
    enabledBorder: _border(vm.error != null ? c.bad : c.line2),
    disabledBorder: _border(c.line1),
    focusedBorder: _border(c.ember),
  );

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: Radii.segment,
    borderSide: BorderSide(color: color),
  );

  Widget _field(BuildContext context, AppColors c) {
    final style = TextStyle(fontSize: 13, color: c.text1);
    switch (vm.kind) {
      case .choice:
        final value = vm.value as String?;
        return DropdownButtonFormField<String>(
          key: ValueKey('${vm.id}/choice'),
          initialValue: vm.choices.contains(value) ? value : null,
          isExpanded: true,
          dropdownColor: c.ground3,
          icon: AppIcon('ui_chevron_down', size: 16, color: c.text3),
          decoration: _decoration(c),
          style: mono(color: c.text1),
          items: [
            for (final ch in vm.choices)
              DropdownMenuItem(value: ch, child: Text(ch)),
          ],
          onChanged: vm.enabled ? vm.onChanged : null,
        );
      case .file:
        final name = vm.value as String?;
        return InkWell(
          onTap: vm.enabled ? vm.onPickFile : null,
          borderRadius: Radii.segment,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: c.ground3,
              borderRadius: Radii.segment,
              border: Border.all(color: c.line2),
            ),
            child: Row(
              spacing: 8,
              children: [
                AppIcon('ui_file', size: 16, color: c.text3),
                Expanded(
                  child: Text(
                    name ?? vm.hint ?? '',
                    overflow: .ellipsis,
                    style: name == null
                        ? TextStyle(fontSize: 13, color: c.text4)
                        : mono(color: c.text1),
                  ),
                ),
              ],
            ),
          ),
        );
      case .text || .textarea || .number || .secret:
        final multi = vm.kind == .textarea;
        return TextFormField(
          key: ValueKey('${vm.id}/${vm.kind.name}'),
          initialValue: vm.kind == .secret ? null : vm.value?.toString(),
          enabled: vm.enabled,
          obscureText: vm.kind == .secret,
          minLines: multi ? 3 : 1,
          maxLines: multi ? 8 : 1,
          keyboardType: vm.kind == .number
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : null,
          style: vm.kind == .number || multi ? mono(color: c.text1) : style,
          decoration: _decoration(c),
          onChanged: (s) {
            if (vm.kind == .number) {
              vm.onChanged(s.isEmpty ? null : (num.tryParse(s) ?? s));
            } else {
              vm.onChanged(s.isEmpty ? null : s);
            }
          },
        );
      case .toggle:
        return const SizedBox.shrink();
    }
  }
}
