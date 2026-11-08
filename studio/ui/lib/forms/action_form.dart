import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../buttons/button.dart';
import 'param_form.dart';

/// A picked file: its name and bytes (an `editor: file` parameter).
final class PickedFile {
  const PickedFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// A [ParamForm] that keeps what is typed and hands it over on submit: the
/// arguments of an action (Approve, Grant, an Explorer action, an install).
///
/// The fields' own `onChanged` are not called; [onSubmit] gets the values by
/// field id (a file field gives a [PickedFile]). Required fields left empty
/// keep the button disabled.
class ActionForm extends StatefulWidget {
  const ActionForm({
    required this.fields,
    required this.submit,
    required this.onSubmit,
    this.secondary,
    this.onSecondary,
    this.busy = false,
    this.columns = 1,
    this.disabledReason,
    super.key,
  });

  final List<ParamFieldVm> fields;

  /// The label of the primary button.
  final String submit;
  final ValueChanged<Map<String, Object?>> onSubmit;

  /// A second, danger button (Reject) and what it does.
  final String? secondary;
  final VoidCallback? onSecondary;
  final bool busy;
  final int columns;

  /// Why the user cannot submit (rule 8).
  final String? disabledReason;

  @override
  State<ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<ActionForm> {
  late final Map<String, Object?> _values = {
    for (final f in widget.fields) f.id: f.value,
  };

  bool get _complete => widget.fields.every(
    (f) => !f.required || (_values[f.id] != null && _values[f.id] != ''),
  );

  Future<void> _pick(ParamFieldVm f) async {
    final r = await FilePicker.pickFiles(withData: true);
    final file = r?.files.single;
    if (file?.bytes case final bytes?) {
      setState(() => _values[f.id] = PickedFile(file!.name, bytes));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = [
      for (final f in widget.fields)
        ParamFieldVm(
          id: f.id,
          label: f.label,
          kind: f.kind,
          value: switch (_values[f.id]) {
            final PickedFile p => p.name,
            final v => v,
          },
          hint: f.hint,
          unit: f.unit,
          choices: f.choices,
          required: f.required,
          error: f.error,
          enabled: f.enabled && !widget.busy,
          description: f.description,
          onChanged: (v) => setState(() => _values[f.id] = v),
          onPickFile: () => _pick(f),
        ),
    ];
    final ready = _complete && !widget.busy && widget.disabledReason == null;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        ParamForm(fields: fields, columns: widget.columns),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: Button.primary(
                label: widget.submit,
                expand: true,
                disabledReason: widget.disabledReason,
                onPressed: ready
                    ? () => widget.onSubmit(Map.of(_values))
                    : null,
              ),
            ),
            if (widget.secondary case final s?)
              Expanded(
                child: Button.danger(
                  label: s,
                  expand: true,
                  disabledReason: widget.disabledReason,
                  onPressed: widget.busy || widget.disabledReason != null
                      ? null
                      : widget.onSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
