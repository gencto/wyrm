import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../inputs/switch_row.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
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

/// What a field of a [ParamForm] holds. The code that builds the field
/// decides the case once, from the parameter's declared type and editor; an
/// editor reads its own case and shows nothing for another.
sealed class ParamValue extends Equatable {
  const ParamValue();

  /// [s] as a text; none for null.
  factory ParamValue.text(String? s) =>
      s == null ? const NoValue() : TextValue(s);

  /// What a typed field shows for it; null for none.
  String? get shown => switch (this) {
    NoValue() => null,
    TextValue(:final text) => text,
    NumberValue(:final value) => '$value',
    FlagValue(:final on) => '$on',
    FileValue(:final name) => name,
  };

  /// The value as an action's argument: a text, a number, a flag, a file's
  /// name; null for none.
  Object? get plain => switch (this) {
    NoValue() => null,
    TextValue(:final text) => text,
    NumberValue(:final value) => value,
    FlagValue(:final on) => on,
    FileValue(:final name) => name,
  };
}

/// Nothing: an empty field.
final class NoValue extends ParamValue {
  const NoValue();

  @override
  List<Object?> get props => const [];
}

/// A text (the text kinds, a choice, a number typed so far that is none).
final class TextValue extends ParamValue {
  const TextValue(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// A number.
final class NumberValue extends ParamValue {
  const NumberValue(this.value);

  final num value;

  @override
  List<Object?> get props => [value];
}

/// A switch.
final class FlagValue extends ParamValue {
  const FlagValue({required this.on});

  final bool on;

  @override
  List<Object?> get props => [on];
}

/// A file, by its name.
final class FileValue extends ParamValue {
  const FileValue(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// One parameter of an action, a link's `cfg` or a plan step, ready to draw.
final class ParamFieldVm extends Equatable {
  const ParamFieldVm({
    required this.id,
    required this.label,
    required this.kind,
    required this.onChanged,
    this.value = const NoValue(),
    this.hint,
    this.unit,
    this.choices = const [],
    this.choiceLabels = const {},
    this.code,
    this.required = false,
    this.error,
    this.enabled = true,
    this.description,
    this.onPickFile,
    this.focusNode,
  });

  /// The parameter name (the `args` key).
  final String id;
  final String label;
  final ParamKind kind;

  /// What the field holds: a [TextValue] for the text kinds and a choice,
  /// a [NumberValue] for number, a [FlagValue] for toggle, a [FileValue]
  /// for file.
  final ParamValue value;

  /// The placeholder (`0…255`, `https://…`).
  final String? hint;

  /// A unit shown inside the field (`ms`).
  final String? unit;
  final List<String> choices;

  /// What a choice reads where it differs from the value sent
  /// (`read_back` → `Read back`).
  final Map<String, String> choiceLabels;

  /// The parameter's own name, in the label's tooltip when the label says
  /// it in other words; [id] when null.
  final String? code;
  final bool required;
  final String? error;
  final bool enabled;

  /// One line under the field.
  final String? description;

  /// Behaviour: out of [props].
  final ValueChanged<ParamValue> onChanged;

  /// Opens the file picker (kind file).
  final VoidCallback? onPickFile;

  /// The focus of a typed field, when the form moves it (to the field a
  /// refusal names). The form keeps one node per field, so it compares equal
  /// from build to build.
  final FocusNode? focusNode;

  @override
  List<Object?> get props => [
    id,
    label,
    kind,
    value,
    hint,
    unit,
    choices,
    choiceLabels,
    code,
    required,
    error,
    enabled,
    description,
    focusNode,
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
            value: vm.value == const FlagValue(on: true),
            onChanged: vm.enabled
                ? (on) => vm.onChanged(FlagValue(on: on))
                : null,
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
          Text(
            e,
            style: TextStyle(fontSize: FontSizes.sm, color: c.bad),
          )
        else if (vm.description case final d?)
          Text(
            d,
            style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
          ),
      ],
    );
  }

  /// The label; its tooltip holds the parameter's own name when the label
  /// is a different word (owner 2026-11-11: the raw name stays reachable).
  Widget _label(AppColors c) {
    final text = _labelText(c);
    final code = vm.code ?? vm.id;
    return vm.label == code || vm.label.isEmpty
        ? text
        : Tooltip(
            message: code,
            waitDuration: const Duration(milliseconds: 600),
            child: text,
          );
  }

  Widget _labelText(AppColors c) => Text.rich(
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
      fontSize: FontSizes.sm,
      color: vm.error != null ? c.bad : c.text3,
    ),
  );

  InputDecoration _decoration(AppColors c) => InputDecoration(
    hintText: vm.hint,
    isDense: true,
    filled: true,
    fillColor: c.ground3,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 10,
    ),
    suffixText: vm.unit,
    suffixStyle: TextStyle(fontSize: FontSizes.sm, color: c.text4),
    hintStyle: TextStyle(fontSize: FontSizes.md, color: c.text4),
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
    final style = TextStyle(fontSize: FontSizes.md, color: c.text1);
    switch (vm.kind) {
      case .choice:
        return DropdownButtonFormField<String>(
          key: ValueKey('${vm.id}/choice'),
          // the choice the value names; none for any other value
          initialValue: switch (vm.value) {
            TextValue(:final text) when vm.choices.contains(text) => text,
            _ => null,
          },
          focusNode: vm.focusNode,
          isExpanded: true,
          dropdownColor: c.ground3,
          icon: AppIconView(
            AppIcon.uiChevronDown,
            size: IconSizes.md,
            color: c.text3,
          ),
          decoration: _decoration(c),
          style: mono(color: c.text1),
          items: [
            for (final ch in vm.choices)
              DropdownMenuItem(
                value: ch,
                child: Text(vm.choiceLabels[ch] ?? ch),
              ),
          ],
          onChanged: vm.enabled
              ? (ch) => vm.onChanged(ParamValue.text(ch))
              : null,
        );
      case .file:
        final name = switch (vm.value) {
          FileValue(:final name) => name,
          _ => null,
        };
        return InkWell(
          onTap: vm.enabled ? vm.onPickFile : null,
          borderRadius: Radii.segment,
          child: Container(
            height: 36,
            padding: Insets.control,
            decoration: BoxDecoration(
              color: c.ground3,
              borderRadius: Radii.segment,
              border: Border.all(color: c.line2),
            ),
            child: Row(
              spacing: 8,
              children: [
                AppIconView(AppIcon.uiFile, size: IconSizes.md, color: c.text3),
                Expanded(
                  child: Text(
                    name ?? vm.hint ?? '',
                    overflow: .ellipsis,
                    style: name == null
                        ? TextStyle(fontSize: FontSizes.md, color: c.text4)
                        : mono(color: c.text1),
                  ),
                ),
              ],
            ),
          ),
        );
      case .text || .textarea || .number || .secret:
        // A text of several lines keeps them (owner's finding 2026-11-11):
        // a one-line field shows the first only and drops the rest at the
        // next key.
        final multi =
            vm.kind == .textarea ||
            vm.kind == .text && (vm.value.shown ?? '').contains('\n');
        return TextFormField(
          key: ValueKey('${vm.id}/${vm.kind.name}'),
          initialValue: vm.kind == .secret ? null : vm.value.shown,
          focusNode: vm.focusNode,
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
            if (s.isEmpty) {
              vm.onChanged(const NoValue());
            } else if (vm.kind == .number) {
              // what is typed so far and is no number yet stays as typed
              vm.onChanged(switch (num.tryParse(s)) {
                final n? => NumberValue(n),
                null => TextValue(s),
              });
            } else {
              vm.onChanged(TextValue(s));
            }
          },
        );
      case .toggle:
        return const SizedBox.shrink();
    }
  }
}
