import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../theme/extensions/colors.dart';
import 'param_form.dart';

/// A picked file: its name and bytes (an `editor: file` parameter).
final class PickedFile {
  const PickedFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// What the broker said when it refused a submit as wrong input
/// (docs/design/specs/errors.md §3, *Back to the form*): its words, and
/// the field of the form they are about when it named one.
final class FieldRefusal {
  const FieldRefusal(this.message, {this.field});

  /// The id of the field the refusal names; null when it names none.
  final String? field;

  /// The broker's words, as they came.
  final String message;
}

/// What a form's submit does with the values, by field id. It answers a
/// [FieldRefusal] when the broker refused them as wrong input, so the form
/// can mark the field; null in every other case.
typedef FormSubmit = FutureOr<FieldRefusal?> Function(
  Map<String, Object?> values,
);

/// A [ParamForm] that keeps what is typed and hands it over on submit: the
/// arguments of an action (Approve, Grant, an Explorer action, an install).
///
/// The fields' own `onChanged` are not called; [onSubmit] gets the values by
/// field id (a file field gives a [PickedFile]). Required fields left empty
/// keep the button disabled.
///
/// It is the one place where *Back to the form* lands: when [onSubmit]
/// answers a [FieldRefusal], the values stay as typed, the broker's words go
/// under the field it names and that field takes the focus (it has it when
/// the error dialog over the form is closed). A refusal that names no field
/// of this form is one line above the button. Either is said until the user
/// changes the field (any field, for the line) or submits again.
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
  final FormSubmit onSubmit;

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

  final _nodes = <String, FocusNode>{};

  /// The refused field was changed since: its error is said no longer.
  var _edited = false;

  /// What the broker said of the last submit, until a field changes.
  FieldRefusal? _refused;

  /// Submits in flight: the button waits for the answer.
  var _sending = 0;

  bool _has(String? id) => id != null && widget.fields.any((f) => f.id == id);

  Future<void> _submit() async {
    setState(() {
      _refused = null;
      _sending++;
    });
    FieldRefusal? refused;
    try {
      refused = await widget.onSubmit(Map.of(_values));
    } finally {
      if (mounted) {
        setState(() => _sending--);
      }
    }
    if (!mounted || refused == null) {
      return;
    }
    final named = refused;
    setState(() {
      _refused = named;
      _edited = false;
    });
    if (_has(named.field)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _nodes[named.field]?.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  bool get _complete => widget.fields.every(
    (f) => !f.required || (_values[f.id] != null && _values[f.id] != ''),
  );

  Future<void> _pick(ParamFieldVm f) async {
    final file = await FilePicker.pickFile();
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (mounted) {
      setState(() => _values[f.id] = PickedFile(file.name, bytes));
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
          choiceLabels: f.choiceLabels,
          code: f.code,
          required: f.required,
          error: _refused?.field == f.id && !_edited
              ? _refused?.message
              : f.error,
          focusNode: _nodes[f.id] ??= FocusNode(debugLabel: f.id),
          enabled: f.enabled && !widget.busy,
          description: f.description,
          onChanged: (v) => setState(() {
            _values[f.id] = v;
            if (_refused?.field == f.id) {
              _edited = true;
            } else if (!_has(_refused?.field)) {
              _refused = null;
            }
          }),
          onPickFile: () => _pick(f),
        ),
    ];
    final ready =
        _complete &&
        !widget.busy &&
        _sending == 0 &&
        widget.disabledReason == null;
    final c = context.colors;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        ParamForm(fields: fields, columns: widget.columns),
        if (_refused case final r? when !_has(r.field))
          Semantics(
            liveRegion: true,
            child: Text(
              r.message,
              key: const ValueKey('form-refusal'),
              style: TextStyle(fontSize: 12, height: 1.4, color: c.bad),
            ),
          ),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: Button.primary(
                label: widget.submit,
                expand: true,
                disabledReason: widget.disabledReason,
                onPressed: ready ? () => unawaited(_submit()) : null,
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
