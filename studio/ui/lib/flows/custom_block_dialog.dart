import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One port the new block will have: the name the editor proposes for it
/// and what it is wired to outside the selection.
final class BlockPortVm extends Equatable {
  const BlockPortVm({required this.name, this.detail = ''});

  final String name;

  /// `← a.level` for an input, `→ mean.value` for an output.
  final String detail;

  @override
  List<Object?> get props => [name, detail];
}

/// What [CustomBlockDialog] draws.
final class CustomBlockDialogVm extends Equatable {
  const CustomBlockDialogVm({
    required this.title,
    required this.note,
    this.name = '',
    this.inputs = const [],
    this.outputs = const [],
    this.nameLabel = 'Name',
    this.descriptionLabel = 'Description',
    this.inputsLabel = 'Inputs',
    this.outputsLabel = 'Outputs',
    this.defaultHint = 'default',
    this.noPorts = 'none',
    this.createLabel = 'Create',
    this.cancelLabel = 'Cancel',
  });

  /// `Create custom block`.
  final String title;

  /// `3 blocks become one block of this flow.`
  final String note;

  /// The name proposed.
  final String name;
  final List<BlockPortVm> inputs;
  final List<BlockPortVm> outputs;
  final String nameLabel;
  final String descriptionLabel;
  final String inputsLabel;
  final String outputsLabel;
  final String defaultHint;

  /// Said where the selection has no input, or no output.
  final String noPorts;
  final String createLabel;
  final String cancelLabel;

  @override
  List<Object?> get props => [
    title,
    note,
    name,
    inputs,
    outputs,
    nameLabel,
    descriptionLabel,
    inputsLabel,
    outputsLabel,
    defaultHint,
    noPorts,
    createLabel,
    cancelLabel,
  ];
}

/// What the dialog hands back: the block's name and description, each
/// port's name in the order they were shown, and the defaults typed for
/// inputs (as text, by the input's name).
final class CustomBlockResult {
  const CustomBlockResult({
    required this.name,
    required this.description,
    required this.inputs,
    required this.outputs,
    required this.defaults,
  });

  final String name;
  final String description;
  final List<String> inputs;
  final List<String> outputs;
  final Map<String, String> defaults;
}

/// `Create custom block…` (studio/docs/design/specs/flow-editor.md §20):
/// the name and description of the block a selection becomes, and its
/// ports — one input per outside source that feeds the selection, one
/// output per inside field that feeds a block outside — each with a name
/// that can be changed, and a default for an input. [validate] says what is
/// wrong with what is typed; while it does, Create is off.
class CustomBlockDialog extends StatefulWidget {
  const CustomBlockDialog({required this.vm, this.validate, super.key});

  final CustomBlockDialogVm vm;
  final String? Function(CustomBlockResult result)? validate;

  /// Shows it; null when cancelled.
  static Future<CustomBlockResult?> ask(
    BuildContext context, {
    required CustomBlockDialogVm vm,
    String? Function(CustomBlockResult result)? validate,
  }) => showDialog<CustomBlockResult>(
    context: context,
    builder: (_) => CustomBlockDialog(vm: vm, validate: validate),
  );

  @override
  State<CustomBlockDialog> createState() => _CustomBlockDialogState();
}

class _CustomBlockDialogState extends State<CustomBlockDialog> {
  late final _name = TextEditingController(text: widget.vm.name);
  final _description = TextEditingController();
  late final List<TextEditingController> _inputs = [
    for (final p in widget.vm.inputs) TextEditingController(text: p.name),
  ];
  late final List<TextEditingController> _defaults = [
    for (final _ in widget.vm.inputs) TextEditingController(),
  ];
  late final List<TextEditingController> _outputs = [
    for (final p in widget.vm.outputs) TextEditingController(text: p.name),
  ];

  Iterable<TextEditingController> get _all => [
    _name,
    _description,
    ..._inputs,
    ..._defaults,
    ..._outputs,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _all) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  CustomBlockResult get _result => CustomBlockResult(
    name: _name.text.trim(),
    description: _description.text.trim(),
    inputs: [for (final c in _inputs) c.text.trim()],
    outputs: [for (final c in _outputs) c.text.trim()],
    defaults: {
      for (final (i, c) in _defaults.indexed)
        if (c.text.trim().isNotEmpty) _inputs[i].text.trim(): c.text.trim(),
    },
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    final problem = widget.validate?.call(_result);
    Widget label(String text) => Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: .w600,
        letterSpacing: 0.66,
        color: c.text4,
      ),
    );
    Widget field(
      TextEditingController controller, {
      String hint = '',
      bool code = true,
      Key? key,
    }) => Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: .centerLeft,
      decoration: BoxDecoration(
        color: c.ground3,
        border: .all(color: c.line2),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: TextField(
        key: key,
        controller: controller,
        style: code
            ? mono(size: 12, color: c.text1)
            : TextStyle(fontSize: 13, color: c.text1),
        decoration:
            InputDecoration.collapsed(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 12, color: c.text4),
            ).copyWith(
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
      ),
    );
    Widget ports(
      String title,
      List<BlockPortVm> list,
      List<TextEditingController> names, {
      List<TextEditingController>? defaults,
    }) => Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        label(title),
        if (list.isEmpty)
          Text(vm.noPorts, style: TextStyle(fontSize: 12, color: c.text4)),
        for (final (i, p) in list.indexed)
          Row(
            spacing: 8,
            children: [
              Expanded(flex: 5, child: field(names[i])),
              if (defaults != null)
                Expanded(
                  flex: 4,
                  child: field(defaults[i], hint: vm.defaultHint),
                ),
              Expanded(
                flex: 5,
                child: Text(
                  p.detail,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: mono(size: 11, color: c.text4),
                ),
              ),
            ],
          ),
      ],
    );
    return Dialog(
      backgroundColor: c.ground1,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.panel,
        side: BorderSide(color: c.line2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 14,
            children: [
              Column(
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Text(
                    vm.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    vm.note,
                    style: TextStyle(fontSize: 13, color: c.text3),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: .stretch,
                    spacing: 14,
                    children: [
                      Column(
                        crossAxisAlignment: .stretch,
                        spacing: 6,
                        children: [
                          label(vm.nameLabel),
                          field(_name, key: const ValueKey('block-name')),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: .stretch,
                        spacing: 6,
                        children: [
                          label(vm.descriptionLabel),
                          field(_description, code: false),
                        ],
                      ),
                      ports(
                        vm.inputsLabel,
                        vm.inputs,
                        _inputs,
                        defaults: _defaults,
                      ),
                      ports(vm.outputsLabel, vm.outputs, _outputs),
                    ],
                  ),
                ),
              ),
              if (problem != null)
                Text(problem, style: TextStyle(fontSize: 12, color: c.bad)),
              Row(
                mainAxisAlignment: .end,
                spacing: 10,
                children: [
                  Button.quiet(
                    label: vm.cancelLabel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Button.primary(
                    key: const ValueKey('block-create'),
                    label: vm.createLabel,
                    onPressed: problem == null
                        ? () => Navigator.of(context).pop(_result)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for one name (`Rename` of a custom block): a field that starts
/// with [value]; [validate] says what is wrong with what is typed.
class NameDialog extends StatefulWidget {
  const NameDialog({
    required this.title,
    required this.value,
    required this.confirm,
    required this.cancel,
    this.validate,
    super.key,
  });

  final String title;
  final String value;
  final String confirm;
  final String cancel;
  final String? Function(String name)? validate;

  /// Shows it; null when cancelled.
  static Future<String?> ask(
    BuildContext context, {
    required String title,
    required String value,
    required String confirm,
    required String cancel,
    String? Function(String name)? validate,
  }) => showDialog<String>(
    context: context,
    builder: (_) => NameDialog(
      title: title,
      value: value,
      confirm: confirm,
      cancel: cancel,
      validate: validate,
    ),
  );

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final _name = TextEditingController(text: widget.value);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = _name.text.trim();
    final problem = widget.validate?.call(text);
    final ok = problem == null && text.isNotEmpty && text != widget.value;
    return Dialog(
      backgroundColor: c.ground1,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.panel,
        side: BorderSide(color: c.line2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: .centerLeft,
                decoration: BoxDecoration(
                  color: c.ground3,
                  border: .all(color: c.line2),
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                ),
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  onSubmitted: (_) {
                    if (ok) {
                      Navigator.of(context).pop(text);
                    }
                  },
                  style: mono(color: c.text1),
                  decoration: const InputDecoration.collapsed(hintText: '')
                      .copyWith(
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                ),
              ),
              if (problem != null && text != widget.value)
                Text(problem, style: TextStyle(fontSize: 12, color: c.bad)),
              Row(
                mainAxisAlignment: .end,
                spacing: 10,
                children: [
                  Button.quiet(
                    label: widget.cancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Button.primary(
                    label: widget.confirm,
                    onPressed: ok
                        ? () => Navigator.of(context).pop(text)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
