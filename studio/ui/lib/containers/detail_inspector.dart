import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/action_row.dart';
import '../forms/action_form.dart';
import '../forms/param_form.dart';
import '../indicators/key_text.dart';
import '../indicators/status_pill.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'fact_grid.dart';
import 'section_label.dart';

/// A labelled group of actions.
final class ActionGroupVm<T> extends Equatable {
  const ActionGroupVm({required this.label, required this.actions});

  final String label;
  final List<ActionRowVm<T>> actions;

  @override
  List<Object?> get props => [label, actions];
}

/// A form in the inspector: its fields and buttons.
final class InspectorFormVm extends Equatable {
  const InspectorFormVm({
    required this.id,
    required this.label,
    required this.fields,
    required this.submit,
    this.secondary,
    this.note,
    this.disabledReason,
  });

  /// Rebuilds the form (and forgets what was typed) when it changes.
  final String id;
  final String label;
  final List<ParamFieldVm> fields;
  final String submit;
  final String? secondary;

  /// Grey text under the buttons.
  final String? note;
  final String? disabledReason;

  @override
  List<Object?> get props => [
    id,
    label,
    fields,
    submit,
    secondary,
    note,
    disabledReason,
  ];
}

/// What the right panel shows for one selection.
final class DetailInspectorVm<T> extends Equatable {
  const DetailInspectorVm({
    required this.title,
    this.eyebrow,
    this.pill,
    this.keyName,
    this.facts = const [],
    this.groups = const [],
    this.form,
    this.footer,
  });

  final String? eyebrow;
  final String title;
  final StatusPillVm? pill;

  /// The node it is about, in mono under the title.
  final String? keyName;
  final List<FactVm> facts;

  /// Groups of actions, in order.
  final List<ActionGroupVm<T>> groups;
  final InspectorFormVm? form;

  /// A boxed note at the bottom.
  final String? footer;

  @override
  List<Object?> get props => [
    eyebrow,
    title,
    pill,
    keyName,
    facts,
    groups,
    form,
    footer,
  ];
}

/// The inspector of the canvas boards (Links, Sites): header with a status
/// pill, facts, groups of action cards, an optional form.
class DetailInspector<T> extends StatelessWidget {
  /// [onAction] gets the id of the action row tapped.
  DetailInspector({
    required this.vm,
    required ValueChanged<T> onAction,
    this.onSubmit,
    this.onSecondary,
    this.busy = false,
    this.width = 340,
    super.key,
  }) : _rows = [
         for (final g in vm.groups)
           [for (final a in g.actions) ActionRow<T>(vm: a, onTap: onAction)],
       ];

  final DetailInspectorVm<T> vm;

  // The rows of each group, with [onAction] applied to their ids here: a
  // field of type `ValueChanged<T>` would hold `T` against its variance.
  final List<List<ActionRow<T>>> _rows;
  final FormSubmit? onSubmit;
  final VoidCallback? onSecondary;
  final bool busy;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(left: BorderSide(color: c.line1)),
      ),
      child: ListView(
        children: [
          Container(
            padding: Insets.inspectorHead,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line1)),
            ),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 6,
              children: [
                if (vm.eyebrow case final e?) SectionLabel(e),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: .center,
                  children: [
                    Text(
                      vm.title,
                      maxLines: 2,
                      overflow: .ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (vm.pill case final p?) StatusPill(vm: p, dense: true),
                  ],
                ),
                if (vm.keyName case final k?)
                  KeyText(k, size: FontSizes.sm, color: c.text3),
              ],
            ),
          ),
          if (vm.facts.isNotEmpty)
            Container(
              padding: Insets.inspectorFacts,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: FactGrid(facts: vm.facts, labelWidth: 74),
            ),
          Padding(
            padding: Insets.inspectorBody,
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 8,
              children: [
                for (final (i, g) in vm.groups.indexed) ...[
                  Padding(
                    padding: Insets.inspectorGroup,
                    child: SectionLabel(g.label),
                  ),
                  ..._rows[i],
                ],
                if (vm.form case final f?) ...[
                  Padding(
                    padding: Insets.inspectorForm,
                    child: SectionLabel(f.label),
                  ),
                  ActionForm(
                    key: ValueKey(f.id),
                    fields: f.fields,
                    submit: f.submit,
                    secondary: f.secondary,
                    busy: busy,
                    disabledReason: f.disabledReason,
                    onSubmit: onSubmit ?? (_) => null,
                    onSecondary: onSecondary,
                  ),
                  if (f.note case final n?)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        n,
                        style: TextStyle(
                          fontSize: FontSizes.md,
                          height: LineHeights.body,
                          color: c.text3,
                        ),
                      ),
                    ),
                ],
                if (vm.footer case final n?)
                  Container(
                    margin: const EdgeInsets.only(top: AppSpacing.md),
                    padding: Insets.inspectorFooter,
                    decoration: BoxDecoration(
                      color: c.ground2,
                      border: .all(color: c.line1),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    child: Text(
                      n,
                      style: TextStyle(
                        fontSize: FontSizes.md,
                        height: LineHeights.body,
                        color: c.text2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
