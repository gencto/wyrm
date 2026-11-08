import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/action_row.dart';
import '../forms/action_form.dart';
import '../forms/param_form.dart';
import '../indicators/key_text.dart';
import '../indicators/status_pill.dart';
import '../theme/extensions/colors.dart';
import 'fact_grid.dart';
import 'section_label.dart';

/// A labelled group of actions.
final class ActionGroupVm extends Equatable {
  const ActionGroupVm({required this.label, required this.actions});

  final String label;
  final List<ActionRowVm> actions;

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
final class DetailInspectorVm extends Equatable {
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
  final List<ActionGroupVm> groups;
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
class DetailInspector extends StatelessWidget {
  const DetailInspector({
    required this.vm,
    required this.onAction,
    this.onSubmit,
    this.onSecondary,
    this.busy = false,
    this.width = 340,
    super.key,
  });

  final DetailInspectorVm vm;
  final ValueChanged<String> onAction;
  final ValueChanged<Map<String, Object?>>? onSubmit;
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
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
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
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (vm.pill case final p?) StatusPill(vm: p, dense: true),
                  ],
                ),
                if (vm.keyName case final k?)
                  KeyText(k, size: 12, color: c.text3),
              ],
            ),
          ),
          if (vm.facts.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: FactGrid(facts: vm.facts, labelWidth: 74),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 8,
              children: [
                for (final g in vm.groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SectionLabel(g.label),
                  ),
                  for (final a in g.actions) ActionRow(vm: a, onTap: onAction),
                ],
                if (vm.form case final f?) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: SectionLabel(f.label),
                  ),
                  ActionForm(
                    key: ValueKey(f.id),
                    fields: f.fields,
                    submit: f.submit,
                    secondary: f.secondary,
                    busy: busy,
                    disabledReason: f.disabledReason,
                    onSubmit: onSubmit ?? (_) {},
                    onSecondary: onSecondary,
                  ),
                  if (f.note case final n?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        n,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: c.text3,
                        ),
                      ),
                    ),
                ],
                if (vm.footer case final n?)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.ground2,
                      border: .all(color: c.line1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      n,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
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
