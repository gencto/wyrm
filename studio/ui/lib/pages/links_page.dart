import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/detail_inspector.dart';
import '../containers/page_header.dart';
import '../forms/action_form.dart';
import '../inputs/switch_row.dart';
import '../models/value_changed.dart';
import '../tables/row_table.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// A setting shown as a card above the Quarantine table.
final class SettingCardVm extends Equatable {
  const SettingCardVm({
    required this.title,
    required this.description,
    required this.keyName,
    required this.value,
    this.disabledReason,
  });

  final String title;
  final String description;
  final String keyName;
  final FieldVm<bool> value;
  final String? disabledReason;

  @override
  List<Object?> get props => [
    title,
    description,
    keyName,
    value,
    disabledReason,
  ];
}

/// Board *Studio · Links* and its tabs *On other devices* and *Quarantine*:
/// a header with Add a link, three tabs, the table of the tab, and the
/// inspector of the selected row.
class LinksPage extends StatelessWidget {
  const LinksPage({
    required this.title,
    required this.subtitle,
    required this.addLabel,
    required this.tabs,
    required this.tab,
    required this.description,
    required this.columns,
    required this.rows,
    required this.onTab,
    required this.onRow,
    required this.onAction,
    this.onTapLinkInstall,
    this.addReason,
    this.settings = const [],
    this.empty,
    this.inspector,
    this.onSubmit,
    this.onSecondary,
    this.busy = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final String addLabel;

  /// Opens Add a link; null when the user may not install.
  final VoidCallback? onTapLinkInstall;
  final String? addReason;
  final List<TabItemVm> tabs;
  final String tab;
  final String description;
  final List<SettingCardVm> settings;
  final List<ColumnVm> columns;
  final List<RowVm> rows;
  final String? empty;
  final DetailInspectorVm? inspector;
  final ValueChanged<String> onTab;
  final ValueChanged<String> onRow;
  final ValueChanged<String> onAction;
  final FormSubmit? onSubmit;
  final VoidCallback? onSecondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      children: [
        PageHeader(
          title: title,
          subtitle: subtitle,
          trailing: Button.primary(
            label: addLabel,
            icon: 'ui_add',
            disabledReason: addReason,
            onPressed: onTapLinkInstall,
          ),
        ),
        const SizedBox(height: 22),
        SegmentedTabs(tabs: tabs, selected: tab, onSelect: onTab),
        const SizedBox(height: 18),
        Text(description, style: TextStyle(fontSize: 13, color: c.text2)),
        const SizedBox(height: 16),
        if (settings.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, box) {
              final cards = [
                for (final s in settings)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: c.ground1,
                      border: .all(color: c.line1),
                      borderRadius: Radii.card,
                    ),
                    child: SwitchRow(
                      title: s.title,
                      description: s.description,
                      keyName: s.keyName,
                      vm: s.value,
                      disabledReason: s.disabledReason,
                    ),
                  ),
              ];
              return box.maxWidth >= 640
                  ? Row(
                      crossAxisAlignment: .start,
                      spacing: 12,
                      children: [for (final w in cards) Expanded(child: w)],
                    )
                  : Column(spacing: 12, children: cards);
            },
          ),
          const SizedBox(height: 16),
        ],
        RowTable(columns: columns, rows: rows, onTap: onRow, empty: empty),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        final ins = inspector;
        if (ins == null) {
          return body;
        }
        final panel = DetailInspector(
          vm: ins,
          onAction: onAction,
          onSubmit: onSubmit,
          onSecondary: onSecondary,
          busy: busy,
          width: wide ? 340 : box.maxWidth,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: .stretch,
            children: [
              Expanded(child: body),
              panel,
            ],
          );
        }
        return Column(
          children: [
            Expanded(flex: 3, child: body),
            Expanded(flex: 2, child: panel),
          ],
        );
      },
    );
  }
}
