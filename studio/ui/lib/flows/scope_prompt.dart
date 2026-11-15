import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/shades.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// What [ScopePrompt] draws.
final class ScopePromptVm extends Equatable {
  const ScopePromptVm({
    required this.block,
    required this.row,
    required this.value,
    this.suggestions = const [],
  });

  /// The block whose key is bound, and the row the prompt points at.
  final String block;
  final String row;

  /// The scope the field starts with: the block's own, else a suggestion.
  final String value;

  /// Scopes offered as chips: the key's parent, the site's sections.
  final List<String> suggestions;

  @override
  List<Object?> get props => [block, row, value, suggestions];
}

/// Why a scope typed for a key of this site is refused (ADR 0040).
enum ScopeProblemVm {
  empty,
  section,
  otherSite,
  segment;

  String get label => switch (this) {
    empty => S.current.scopeEmpty,
    section => S.current.scopeSection,
    otherSite => S.current.scopeOtherSite,
    segment => S.current.scopeSegment,
  };
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
  final Validate<String>? validate;

  static const double width = AppSizes.flowScopePrompt;

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
          padding: Insets.flowScopePrompt,
          decoration: BoxDecoration(
            color: c.ground2,
            border: .all(color: c.emberLine),
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadii.card),
            ),
            boxShadow: const [
              BoxShadow(
                color: Shades.popupShadow,
                offset: Offset(0, 12),
                blurRadius: 28,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: AppSpacing.sm,
            children: [
              Text(
                S.current.scopeTitle,
                style: TextStyle(
                  fontSize: FontSizes.sm,
                  fontWeight: .w600,
                  color: c.text2,
                ),
              ),
              Container(
                height: AppSizes.flowField,
                padding: Insets.control,
                alignment: .centerLeft,
                decoration: BoxDecoration(
                  color: c.ground3,
                  border: .all(color: problem == null ? c.line2 : c.badLine),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppRadii.segment),
                  ),
                ),
                child: TextField(
                  key: const ValueKey('scope-field'),
                  controller: _text,
                  focusNode: _focus,
                  // Enter saves; a refused scope keeps the cursor here.
                  onEditingComplete: _save,
                  style: mono(size: FontSizes.sm, color: c.text1),
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
                  spacing: AppSpacing.flowChips,
                  runSpacing: AppSpacing.flowChips,
                  children: [
                    for (final s in vm.suggestions)
                      InkWell(
                        onTap: () => _text.text = s,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppRadii.chip),
                        ),
                        child: Container(
                          padding: Insets.flowScopeChip,
                          decoration: BoxDecoration(
                            color: c.ground4,
                            border: .all(
                              color: s == _text.text.trim()
                                  ? c.emberLine
                                  : c.line2,
                            ),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(AppRadii.chip),
                            ),
                          ),
                          child: Text(
                            s,
                            style: mono(size: FontSizes.xs, color: c.text2),
                          ),
                        ),
                      ),
                  ],
                ),
              Text(
                problem ?? S.current.scopeNote,
                style: TextStyle(
                  fontSize: FontSizes.xs,
                  height: 1.4,
                  color: problem == null ? c.text4 : c.bad,
                ),
              ),
              Row(
                mainAxisAlignment: .end,
                spacing: AppSpacing.sm,
                children: [
                  Button.quiet(
                    label: S.current.cancel,
                    size: ButtonSize.small,
                    onPressed: widget.onCancel,
                  ),
                  Button.primary(
                    key: const ValueKey('scope-save'),
                    label: S.current.viewerSave,
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
