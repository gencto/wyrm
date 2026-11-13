import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/detail_inspector.dart';
import '../containers/page_header.dart';
import '../forms/action_form.dart';
import '../inputs/switch_row.dart';
import '../models/value_changed.dart';
import '../overlays/task_sheet.dart';
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
    this.secondLabel,
    this.onSecond,
    this.secondReason,
    this.sheet,
    this.onSheetPrimary,
    this.onSheetSecondary,
    this.onSheetToggle,
    this.onSheetAction,
    this.onSheetClose,
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

  /// A second button of the header (`Update all official…`); not shown
  /// when null.
  final String? secondLabel;
  final VoidCallback? onSecond;
  final String? secondReason;

  /// The update of a package as a drawer (boards `LinkUpdate*`); it stands
  /// where the inspector does.
  final TaskSheetVm? sheet;
  final VoidCallback? onSheetPrimary;
  final VoidCallback? onSheetSecondary;
  final void Function(String id, {required bool value})? onSheetToggle;
  final ValueChanged<String>? onSheetAction;
  final VoidCallback? onSheetClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      children: [
        PageHeader(
          title: title,
          subtitle: subtitle,
          trailing: Row(
            mainAxisSize: .min,
            spacing: 10,
            children: [
              if (secondLabel case final label?)
                Button.secondary(
                  label: label,
                  disabledReason: secondReason,
                  onPressed: secondReason == null ? onSecond : null,
                ),
              Button.primary(
                label: addLabel,
                icon: 'ui_add',
                disabledReason: addReason,
                onPressed: onTapLinkInstall,
              ),
            ],
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
        final task = sheet;
        if (ins == null && task == null) {
          return body;
        }
        final Widget panel = task != null
            ? TaskSheet(
                vm: task,
                width: wide ? 460 : box.maxWidth,
                onPrimary: onSheetPrimary,
                onSecondary: onSheetSecondary,
                onToggle: onSheetToggle,
                onAction: onSheetAction,
                onClose: onSheetClose,
              )
            : DetailInspector(
                vm: ins!,
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
