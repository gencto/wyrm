import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../buttons/pill_tabs.dart';
import '../buttons/theme_switcher.dart';
import '../charts/trend.dart';
import '../inputs/switch_row.dart';
import '../models/value_changed.dart';
import '../shell/window_bar.dart';
import '../theme/common.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import '../views/view_checks.dart';
import '../views/view_project_shell.dart';
import '../views/view_style.dart';
import '../views/view_surface.dart';

/// The views lab (docs/design/specs/genui-views.md §4): a sample or pasted
/// A2UI document on the left, its surface in the middle at the width of a
/// desktop, a 10" panel or a phone, and what Studio found on the right
/// (checks, the messages as sent, the data model). An experiment page: it
/// answers whether genui can draw WYRM views, it is not the final screen.
class ViewsLabPage extends StatelessWidget {
  const ViewsLabPage({
    required this.onBack,
    required this.theme,
    required this.samples,
    required this.sample,
    required this.onRefine,
    required this.project,
    required this.draft,
    required this.onShowDraft,
    required this.result,
    required this.width,
    required this.density,
    required this.surfaceId,
    required this.messages,
    required this.data,
    required this.format,
    required this.onAction,
    required this.shell,
    required this.onItem,
    required this.onCrumb,
    required this.onPageBack,
    required this.tab,
    required this.checks,
    required this.problems,
    this.window = const WindowBarVm(),
    super.key,
  });

  /// The frame of a 10" panel and of a phone, in logical pixels.
  static const double panelWidth = 1024;
  static const double phoneWidth = 390;

  final VoidCallback onBack;

  /// The frameless window's side of the top bar.
  final WindowBarVm window;
  final FieldVm<ThemeMode> theme;

  /// The samples to pick from: id and label.
  final List<PillTabVm> samples;
  final FieldVm<String> sample;

  /// Applies the sample's refine turn; null when it has none or it is
  /// applied.
  final VoidCallback? onRefine;

  /// The *Project* switch; disabled for a sample without a manifest.
  final FieldVm<bool> project;

  /// The JSONL being pasted, and *Show* for it.
  final FieldVm<String?> draft;
  final VoidCallback? onShowDraft;

  /// What the last action did (`Wrote 22.5 to …`).
  final String result;

  /// `desktop`, `panel` or `phone`.
  final FieldVm<String> width;

  /// A density name, or empty for the one the width gives.
  final FieldVm<String> density;

  final String surfaceId;
  final List<String> messages;
  final Map<String, Object?> data;
  final TrendFormat format;
  final ValueChanged<ViewActionVm> onAction;

  /// The project around the page; null with the switch off.
  final ViewProjectVm? shell;
  final ValueChanged<String> onItem;
  final ValueChanged<int> onCrumb;
  final VoidCallback? onPageBack;

  /// `checks`, `a2ui` or `data`.
  final FieldVm<String> tab;
  final List<ViewCheckVm> checks;

  /// How many checks are not passed: the dot on the Checks tab.
  final int problems;

  ViewDensity _density(double frame) => switch (density.value) {
    'desktop' => .desktop,
    'panel' => .panel,
    'phone' => .phone,
    'kiosk' => .kiosk,
    _ => .forWidth(frame),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = S.current;
    return Scaffold(
      backgroundColor: c.ground0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: c.ground1,
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              // The window's title bar, as on every page of its own: the
              // room for the window buttons, and the drag area.
              child: WindowBar(
                vm: window,
                padding: 16,
                child: Row(
                  spacing: 12,
                  children: [
                    SizedBox(
                      height: 32,
                      child: Button.quiet(
                        label: s.viewsBack,
                        onPressed: onBack,
                        size: .small,
                        fontSize: 13,
                        inset: 12,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.viewsLab,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ThemeSwitcher(vm: theme),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: .stretch,
                children: [
                  SizedBox(width: 260, child: _source(context)),
                  Expanded(child: _stage(context)),
                  SizedBox(width: 340, child: _findings(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _source(BuildContext context) {
    final c = context.colors;
    final s = S.current;
    final theme = Theme.of(context);
    Widget label(String text) => Text(
      text.toUpperCase(),
      style: boardText(size: 11, weight: .w600, color: c.text4, tracking: 0.66),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(right: BorderSide(color: c.line1)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          label(s.viewsSample),
          const SizedBox(height: 8),
          PillTabs(
            tabs: samples,
            selected: sample.value,
            onSelect: sample.onChanged,
            equal: true,
          ),
          const SizedBox(height: 12),
          Button.secondary(
            label: s.viewsRefine,
            onPressed: onRefine,
            expand: true,
            size: .compact,
            fontSize: 13,
          ),
          const SizedBox(height: 4),
          SwitchRow(title: s.viewsProject, vm: project),
          const SizedBox(height: 12),
          label(s.viewsPaste),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: draft.value,
            minLines: 6,
            maxLines: 10,
            style: mono(size: 12, color: c.text1),
            decoration: const InputDecoration().applyDefaults(
              inputDecorationThemeFrom(
                theme.inputDecorationTheme,
                theme.colorScheme,
              ),
            ),
            onChanged: (v) => draft.onChanged(v.isEmpty ? null : v),
          ),
          const SizedBox(height: 8),
          Button.secondary(
            label: s.viewsShow,
            onPressed: onShowDraft,
            expand: true,
            size: .compact,
            fontSize: 13,
          ),
          if (result.isNotEmpty) ...[
            const SizedBox(height: 16),
            label(s.viewsResult),
            const SizedBox(height: 6),
            Text(result, style: boardText(size: 13, color: c.text2)),
          ],
        ],
      ),
    );
  }

  Widget _stage(BuildContext context) {
    final c = context.colors;
    final s = S.current;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              PillTabs(
                tabs: [
                  PillTabVm(id: 'desktop', label: s.viewsWidthDesktop),
                  PillTabVm(id: 'panel', label: s.viewsWidthPanel),
                  PillTabVm(id: 'phone', label: s.viewsWidthPhone),
                ],
                selected: width.value,
                onSelect: width.onChanged,
              ),
              PillTabs(
                label: s.viewsDensity,
                tabs: [
                  PillTabVm(id: '', label: s.viewsDensityAuto),
                  PillTabVm(id: 'desktop', label: s.viewsWidthDesktop),
                  PillTabVm(id: 'panel', label: s.viewsDensityPanel),
                  PillTabVm(id: 'phone', label: s.viewsWidthPhone),
                  PillTabVm(id: 'kiosk', label: s.viewsDensityKiosk),
                ],
                selected: density.value,
                onSelect: density.onChanged,
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final frame = switch (width.value) {
                'panel' => panelWidth.clamp(0.0, box.maxWidth - 32),
                'phone' => phoneWidth.clamp(0.0, box.maxWidth - 32),
                _ => box.maxWidth - 32,
              };
              final d = _density(frame);
              final surface = ViewSurface(
                // Another surface, another state: its controller starts
                // again.
                key: ValueKey(surfaceId),
                surfaceId: surfaceId,
                messages: messages,
                data: data,
                density: d,
                format: format,
                onAction: onAction,
              );
              return Align(
                alignment: .topCenter,
                child: Container(
                  width: frame,
                  margin: const EdgeInsets.only(bottom: 16),
                  // One shape owns the fill, the radius and the border: the
                  // child is clipped to it and the border is drawn over the
                  // child. (A `BoxDecoration` border is drawn under the
                  // child, whose square corner then shows inside the curve.)
                  child: Material(
                    key: const ValueKey('view-frame'),
                    color: c.ground0,
                    clipBehavior: .antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: Radii.panel,
                      side: BorderSide(color: c.line2),
                    ),
                    child: switch (shell) {
                      final vm? => ViewProjectShell(
                        vm: vm,
                        density: d,
                        onItem: onItem,
                        onCrumb: onCrumb,
                        onBack: onPageBack,
                        child: surface,
                      ),
                      null => surface,
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _findings(BuildContext context) {
    final c = context.colors;
    final s = S.current;
    final rows = data.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(left: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: PillTabs(
              tabs: [
                PillTabVm(
                  id: 'checks',
                  label: s.viewsTabChecks,
                  dot: problems > 0 ? .bad : null,
                ),
                PillTabVm(id: 'a2ui', label: s.viewsTabMessages),
                PillTabVm(id: 'data', label: s.viewsTabData),
              ],
              selected: tab.value,
              onSelect: tab.onChanged,
              equal: true,
            ),
          ),
          Expanded(
            child: switch (tab.value) {
              'a2ui' => ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => SelectableText(
                  messages[i],
                  style: mono(size: 11, color: c.text2),
                ),
              ),
              'data' => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        rows[i].key,
                        style: mono(size: 11, color: c.text4),
                      ),
                      Text(
                        '${rows[i].value}',
                        style: mono(size: 13, color: c.text1),
                      ),
                    ],
                  ),
                ),
              ),
              _ => ViewChecks(checks: checks),
            },
          ),
        ],
      ),
    );
  }
}
