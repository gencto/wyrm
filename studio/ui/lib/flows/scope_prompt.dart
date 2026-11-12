import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What [ScopePrompt] draws.
final class ScopePromptVm extends Equatable {
  const ScopePromptVm({
    required this.block,
    required this.row,
    required this.title,
    required this.value,
    this.note = '',
    this.suggestions = const [],
    this.saveLabel = 'Save',
    this.cancelLabel = 'Cancel',
  });

  /// The block whose key is bound, and the row the prompt points at.
  final String block;
  final String row;

  /// `This block may read keys under`.
  final String title;

  /// The scope the field starts with: the block's own, else a suggestion.
  final String value;

  /// Said under the field while the scope is right: what a scope is for.
  final String note;

  /// Scopes offered as chips: the key's parent, the site's sections.
  final List<String> suggestions;
  final String saveLabel;
  final String cancelLabel;

  @override
  List<Object?> get props => [
    block,
    row,
    title,
    value,
    note,
    suggestions,
    saveLabel,
    cancelLabel,
  ];
}

/// The small card that asks for the scope of a key that just got a wire
/// (studio/docs/design/specs/flow-editor.md §17): what the block may read
/// when its key comes from another block. The field starts with a
/// suggestion; a chip fills it; a scope that the engine would refuse says
/// why and cannot be saved. Enter saves, Esc cancels. The canvas places it
/// on the field.
class ScopePrompt extends StatefulWidget {
  const ScopePrompt({
    required this.vm,
    required this.onSave,
    required this.onCancel,
    this.validate,
    super.key,
  });

  final ScopePromptVm vm;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;

  /// What is wrong with a scope; null: it can be saved.
  final String? Function(String scope)? validate;

  static const width = 320.0;

  @override
  State<ScopePrompt> createState() => _ScopePromptState();
}

class _ScopePromptState extends State<ScopePrompt> {
  late final _text = TextEditingController(text: widget.vm.value);
  final _focus = FocusNode(debugLabel: 'ScopePrompt');

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? get _problem => widget.validate?.call(_text.text);

  void _save() {
    if (_problem == null) {
      widget.onSave(_text.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    final problem = _problem;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: ScopePrompt.width,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.ground2,
            border: .all(color: c.emberLine),
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000),
                offset: Offset(0, 12),
                blurRadius: 28,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 8,
            children: [
              Text(
                vm.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: .w600,
                  color: c.text2,
                ),
              ),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: .centerLeft,
                decoration: BoxDecoration(
                  color: c.ground3,
                  border: .all(color: problem == null ? c.line2 : c.badLine),
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                ),
                child: TextField(
                  key: const ValueKey('scope-field'),
                  controller: _text,
                  focusNode: _focus,
                  // Enter saves; a refused scope keeps the cursor here.
                  onEditingComplete: _save,
                  style: mono(size: 12, color: c.text1),
                  decoration: const InputDecoration.collapsed(hintText: '')
                      .copyWith(
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                ),
              ),
              if (vm.suggestions.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in vm.suggestions)
                      InkWell(
                        onTap: () => _text.text = s,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(4),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: c.ground4,
                            border: .all(
                              color: s == _text.text.trim()
                                  ? c.emberLine
                                  : c.line2,
                            ),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(4),
                            ),
                          ),
                          child: Text(s, style: mono(size: 11, color: c.text2)),
                        ),
                      ),
                  ],
                ),
              Text(
                problem ?? vm.note,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: problem == null ? c.text4 : c.bad,
                ),
              ),
              Row(
                mainAxisAlignment: .end,
                spacing: 8,
                children: [
                  Button.quiet(
                    label: vm.cancelLabel,
                    size: ButtonSize.small,
                    onPressed: widget.onCancel,
                  ),
                  Button.primary(
                    key: const ValueKey('scope-save'),
                    label: vm.saveLabel,
                    size: ButtonSize.small,
                    onPressed: problem == null ? _save : null,
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
