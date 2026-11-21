import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../alerts/read_fail.dart';
import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../charts/trend.dart';
import '../containers/action_card.dart';
import '../containers/fact_grid.dart';
import '../containers/fault_boundary.dart';
import '../containers/inspector.dart';
import '../containers/inspector_sections.dart';
import '../containers/section_label.dart';
import '../containers/side_panels.dart';
import '../forms/action_form.dart';
import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../indicators/arc_spinner.dart';
import '../indicators/fail_chip.dart';
import '../indicators/key_line.dart';
import '../indicators/key_text.dart';
import '../indicators/lines_text.dart';
import '../indicators/quality_mark.dart';
import '../indicators/status_pill.dart';
import '../models/disabled.dart';
import '../models/panels.dart';
import '../models/submit.dart';
import '../models/value_changed.dart';
import '../overlays/log_view.dart';
import '../overlays/node_menu.dart';
import '../overlays/value_viewer.dart';
import '../tables/points_table.dart';
import '../tables/row_table.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import '../trees/node_tree.dart';
import '../trees/tree_row.dart';
import 'explorer_models.dart';

export 'explorer_models.dart';

/// Board *Studio · Explorer* (docs/design/specs/explorer.md): the tree, the
/// node on screen with its key line, title, tabs and points, and the
/// inspector of the point, action or node. It says every word itself, from
/// the typed values it is handed (studio-rules §5), and owns its keys (§6):
/// ⌘⇧C copies the keys, ⌘C the value of the point in the inspector, Esc
/// clears the selection, ⌘J opens the Assistant.
class ExplorerPage extends StatefulWidget {
  const ExplorerPage({
    required this.site,
    required this.tree,
    required this.onTap,
    required this.onToggle,
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.onTapFlowEditor,
    this.onOpenMenu,
    this.menu,
    this.menuOpening = false,
    this.onMenuShown,
    this.onMenuPick,
    this.onMark,
    this.onMarkRange,
    this.treeFilter = '',
    this.onTreeFilter,
    this.onNoteLink,
    this.treeLoading = false,
    this.keyName,
    this.keyLinks = const {},
    this.copyKeys = const [],
    this.onCopy,
    this.onCopyValue,
    this.onClear,
    this.onToggleAssistant,
    this.title,
    this.titleName,
    this.pill,
    this.subtitle,
    this.headerButtons = const [],
    this.flowId,
    this.flowDisabled,
    this.onTool,
    this.toolbar = const [],
    this.selectionBar,
    this.onSetPoll,
    this.polls = const [],
    this.pointFilter = '',
    this.onPointFilter,
    this.points = const [],
    this.pointsLoading = false,
    this.pointsEmpty,
    this.emptyButtons = const [],
    this.children = const [],
    this.onChild,
    this.onPoint,
    this.onCheck,
    this.onRange,
    this.onCheckAll,
    this.params = const [],
    this.onParam,
    this.actionGroups = const [],
    this.onAction,
    this.result,
    this.range = HistoryRangeTag.hour,
    this.onHistoryRange,
    this.trend,
    this.onTrendWindow,
    this.onTrendReset,
    this.historyRows = const [],
    this.historyNoPoint = false,
    this.historyFailed,
    this.auditRows = const [],
    this.auditNote,
    this.inspector,
    this.submit,
    this.onReadAgain,
    this.onCloseInspector,
    this.panels = const SidePanelWidths(),
    this.onPanelWidth,
    this.viewer,
    this.viewerTables,
    this.onViewPoint,
    this.onCloseViewer,
    this.drawer,
    super.key,
  });

  /// The site on screen: the tree's label.
  final String site;
  final List<TreeRowVm> tree;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onToggle;

  /// The node menu of a node is asked for (tree `⋯`, right click, Actions
  /// ▾); it shows once [menu] is there.
  final ValueChanged<String>? onOpenMenu;

  /// The node menu to show, once its node's `~meta` is read.
  final ExplorerMenuVm? menu;

  /// A node menu waits for its node's `~meta`: Actions ▾ spins.
  final bool menuOpening;

  /// The page took [menu] to show it.
  final VoidCallback? onMenuShown;

  /// An action of the node menu was picked: its name.
  final ValueChanged<String>? onMenuPick;
  final ValueChanged<String>? onMark;
  final ValueChanged<String>? onMarkRange;
  final String treeFilter;
  final ValueChanged<String>? onTreeFilter;
  final ValueChanged<NoteWorkspace>? onNoteLink;
  final bool treeLoading;

  final String? keyName;

  /// The segments of the key line that open their node (KeyLine.links); a
  /// click is a tap on that node in the tree.
  final Set<String> keyLinks;

  /// What Copy keys and ⌘⇧C copy: the checked rows, else the node on
  /// screen and the tree rows marked.
  final List<String> copyKeys;

  /// Copies keys: Copy key, Copy keys, ⌘⇧C, the menus' footer.
  final ValueChanged<List<String>>? onCopy;

  /// ⌘C: the value of the point in the inspector; null with none.
  final VoidCallback? onCopyValue;

  /// Esc.
  final VoidCallback? onClear;

  /// ⌘J.
  final VoidCallback? onToggleAssistant;

  /// The node's display name, else its name.
  final String? title;

  /// The node's name (its key segment) under a [title] that is its display
  /// name, in mono; null when the title is the name (owner 2026-11-11).
  final String? titleName;
  final StatusPillVm? pill;
  final ExplorerSubtitleVm? subtitle;

  /// Ping, beside Actions ▾.
  final List<ToolButtonVm> headerButtons;

  /// A flow's Edit dataflow: its id goes to [onTapFlowEditor]; disabled
  /// with [flowDisabled].
  final String? flowId;
  final Disabled? flowDisabled;

  /// Opens the flow editor on a flow id.
  final ValueChanged<String> onTapFlowEditor;

  /// A header, toolbar, empty-state or selection-bar button, but Copy keys
  /// and Set poll (the page runs those: [onCopy], [onSetPoll]).
  final ValueChanged<ExplorerTool>? onTool;

  final List<ExplorerTabVm> tabs;
  final ExplorerTabTag tab;
  final ValueChanged<ExplorerTabTag> onTab;

  final List<ToolButtonVm> toolbar;
  final SelectionBarVm? selectionBar;

  /// Set poll on the checked rows: the rate picked, in seconds.
  final ValueChanged<double>? onSetPoll;

  /// The poll rates Set poll offers, in seconds.
  final List<double> polls;
  final String pointFilter;
  final ValueChanged<String>? onPointFilter;
  final List<PointRowVm> points;
  final bool pointsLoading;

  /// `No points yet`, with [emptyButtons] under it.
  final PointsEmpty? pointsEmpty;
  final List<ToolButtonVm> emptyButtons;

  /// The Contents tab of a node that is not a device (a link, a
  /// connection, a folder, a broker, storage).
  final List<ChildRowVm> children;

  /// A child row tapped: its key.
  final ValueChanged<String>? onChild;
  final ValueChanged<String>? onPoint;
  final ValueChanged<String>? onCheck;
  final ValueChanged<String>? onRange;
  final VoidCallback? onCheckAll;

  final List<ExplorerSectionVm> params;

  /// A field of a node's or a point's `edit` was changed: it is staged.
  final ValueChanged<ParamEdit>? onParam;

  final List<ActionCardGroupVm> actionGroups;
  final ValueChanged<String>? onAction;
  final ResultVm? result;

  final HistoryRangeTag range;
  final ValueChanged<HistoryRangeTag>? onHistoryRange;

  /// The picked point's trend (one series), null without one.
  final TrendVm? trend;

  /// The trend's window (µs) and `Reset zoom`.
  final RangeChanged<int>? onTrendWindow;
  final VoidCallback? onTrendReset;
  final List<HistoryRowVm> historyRows;

  /// A node, not a point, is on screen: no history to show.
  final bool historyNoPoint;

  /// Reading the history failed, and why: `history unavailable` over the
  /// chart (docs/design/specs/errors.md §4).
  final String? historyFailed;

  final List<AuditRowVm> auditRows;

  /// Why the audit is empty or cannot be read.
  final AuditNote? auditNote;

  final ExplorerInspectorVm? inspector;

  /// The inspector's form: Stage, Run now, a new value.
  final SubmitVm? submit;

  /// `Read again` in the inspector's `read failed` mark: the key of the
  /// node whose reads failed.
  final ValueChanged<String>? onReadAgain;

  /// Closes an action's form (the point and node inspectors have no close:
  /// they are part of the layout).
  final VoidCallback? onCloseInspector;

  /// The tree and inspector widths the viewer chose (§1).
  final SidePanelWidths panels;
  final PanelResized? onPanelWidth;

  /// The open value viewer of a point, live; null: none is open.
  final ValueViewerVm? viewer;

  /// How the viewer reads tables (a date cell, Copy CSV).
  final ViewerTables? viewerTables;

  /// The eye beside the point inspector's value: opens the viewer.
  final VoidCallback? onViewPoint;
  final VoidCallback? onCloseViewer;

  /// The Assistant about the selection, over the page's right edge (⌘J,
  /// spec assistant.md §5); null when closed.
  final Widget? drawer;

  @override
  State<ExplorerPage> createState() => _ExplorerPageState();
}

/// Explorer's keys (docs/design/specs/explorer.md §6).
enum _Key { copyKeys, copyValue, clear, assistant }

class _KeyIntent extends Intent {
  const _KeyIntent(this.key);

  final _Key key;
}

/// Runs a [_Key] unless a text field has the focus (its own ⌘C and Esc
/// win) or there is nothing to do; then the key passes on.
class _KeyAction extends Action<_KeyIntent> {
  _KeyAction(this.page);

  final ExplorerPage page;

  VoidCallback? _run(_Key key) => switch (key) {
    _Key.copyKeys => switch ((page.onCopy, page.copyKeys)) {
      (final copy?, final keys) when keys.isNotEmpty => () => copy(keys),
      _ => null,
    },
    _Key.copyValue => page.onCopyValue,
    _Key.clear => page.onClear,
    _Key.assistant => page.onToggleAssistant,
  };

  @override
  bool isEnabled(_KeyIntent intent) =>
      _run(intent.key) != null &&
      FocusManager.instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>() ==
          null;

  @override
  Object? invoke(_KeyIntent intent) {
    _run(intent.key)?.call();
    return null;
  }
}

class _ExplorerPageState extends State<ExplorerPage> {
  /// Where the next node menu opens (global).
  Offset _menuAt = Offset.zero;

  ExplorerPage get _w => widget;

  @override
  void initState() {
    super.initState();
    _showMenu(null);
  }

  @override
  void didUpdateWidget(ExplorerPage old) {
    super.didUpdateWidget(old);
    _showMenu(old.menu);
  }

  /// The node menu of the page, when it came since [before].
  void _showMenu(ExplorerMenuVm? before) {
    final m = _w.menu;
    if (m == null || m == before) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      _w.onMenuShown?.call();
      final picked = await NodeMenu.show(
        context,
        at: _menuAt,
        vm: _nodeMenu(m),
      );
      if (!mounted) {
        return;
      }
      switch (picked) {
        case ItemPicked(:final id):
          _w.onMenuPick?.call(id);
        case CopyPicked():
          _w.onCopy?.call([m.key]);
        case null:
          break;
      }
    });
  }

  void _openMenu(String id, Offset at) {
    _menuAt = at;
    _w.onOpenMenu?.call(id);
  }

  NodeMenuVm<String> _nodeMenu(ExplorerMenuVm m) => NodeMenuVm(
    title: m.name,
    subtitle: S.current.menuSubtitle(
      [?m.driver, m.kind.word].join(' '),
      m.actions,
    ),
    groups: [
      for (final g in m.groups)
        NodeMenuGroupVm(
          label:
              g.group ??
              (g.staged ? S.current.configureStaged : S.current.operateRunsNow),
          items: [
            for (final i in g.items)
              NodeMenuItemVm(
                id: i.name,
                label: '${i.label}${i.form ? '…' : ''}',
                code: i.name,
                level: i.level,
                danger: i.danger,
                disabled: i.disabled,
              ),
          ],
        ),
    ],
    copyLabel: S.current.copyKey,
  );

  /// Set poll: the rates for the checked rows, under the page's top left.
  Future<void> _pollMenu() async {
    final box = context.findRenderObject() as RenderBox?;
    final at = box == null
        ? Offset.zero
        : box.localToGlobal(const Offset(320, 180));
    final picked = await NodeMenu.show(
      context,
      at: at,
      vm: NodeMenuVm<double>(
        title: S.current.colPoll,
        subtitle: S.current.nSelected(_w.selectionBar?.count ?? 0),
        groups: [
          NodeMenuGroupVm(
            label: S.current.setPoll,
            items: [
              for (final s in _w.polls)
                NodeMenuItemVm(id: s, label: Formats.pollRate(s)),
            ],
          ),
        ],
        copyLabel: S.current.copyKeys,
      ),
    );
    if (!mounted) {
      return;
    }
    switch (picked) {
      case ItemPicked(id: final s):
        _w.onSetPoll?.call(s);
      case CopyPicked():
        _w.onCopy?.call(_w.copyKeys);
      case null:
        break;
    }
  }

  void _tool(ExplorerTool t) => switch (t) {
    ExplorerTool.copyKeys => _w.onCopy?.call(_w.copyKeys),
    ExplorerTool.setPoll => _pollMenu(),
    _ => _w.onTool?.call(t),
  };

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true):
          _KeyIntent(_Key.copyKeys),
      SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
          _KeyIntent(_Key.copyKeys),
      SingleActivator(LogicalKeyboardKey.keyC, meta: true): _KeyIntent(
        _Key.copyValue,
      ),
      SingleActivator(LogicalKeyboardKey.escape): _KeyIntent(_Key.clear),
      SingleActivator(LogicalKeyboardKey.keyJ, meta: true): _KeyIntent(
        _Key.assistant,
      ),
      SingleActivator(LogicalKeyboardKey.keyJ, control: true): _KeyIntent(
        _Key.assistant,
      ),
    },
    child: Actions(
      actions: {_KeyIntent: _KeyAction(_w)},
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 1100;
            final treePanel = NodeTree(
              label: S.current.treeOf(_w.site),
              rows: _w.tree,
              onTap: _w.onTap,
              onToggle: _w.onToggle,
              onMenu: _w.onOpenMenu == null ? null : _openMenu,
              onMark: _w.onMark,
              onMarkRange: _w.onMarkRange,
              filter: _w.treeFilter,
              onFilter: _w.onTreeFilter,
              filterHint: S.current.filter,
              note: TreeNoteVm(
                lead: S.current.treeNoteLead,
                code: 'sys/**',
                middle: S.current.treeNoteMiddle,
                and: S.current.andWord,
                links: [
                  for (final w in NoteWorkspace.values) (w.name, w.label),
                ],
              ),
              onNoteLink: switch (_w.onNoteLink) {
                final go? => (id) => go(NoteWorkspace.values.byName(id)),
                null => null,
              },
              loading: _w.treeLoading,
              width: wide ? 260 : 240,
            );
            final ins = _w.inspector;
            // One stack whether a viewer is open or not, so the panels
            // keep their state when it opens.
            return Stack(
              children: [
                Positioned.fill(child: _panels(context, box, treePanel, ins)),
                if (_w.viewer case final v?)
                  Positioned.fill(
                    child: ValueViewer(
                      key: const ValueKey('value-viewer'),
                      vm: v,
                      onClose: _w.onCloseViewer ?? () {},
                      tables: _w.viewerTables,
                      copyLabel: S.current.copyValue,
                      copiedLabel: S.current.copiedValue,
                      closeLabel: S.current.closeLabel,
                    ),
                  ),
                if (_w.drawer case final d?)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: AppSizes.assistantDrawer,
                    child: d,
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  // ---- the words of the typed values -------------------------------------

  List<TabItemVm<ExplorerTabTag>> get _tabItems => [
    for (final t in _w.tabs)
      TabItemVm(
        id: t.tag,
        label: t.tag.label,
        count: switch (t.count) {
          final n? => '$n',
          null => null,
        },
      ),
  ];

  ParamFieldVm _field(String node, ExplorerFieldVm f, {String? description}) {
    final label = f.word?.label ?? f.label;
    final value = switch (f.value) {
      final WordOrderTag o => o.text,
      final v => v,
    };
    return ParamFieldVm(
      id: f.code,
      label: label,
      // A field the driver has none for shows its full key as its tooltip.
      code: f.missing ? '$node/${f.code}' : f.code,
      kind: f.kind,
      value: value,
      choices: f.choices,
      choiceLabels: f.choiceLabels,
      enabled: !f.missing,
      description:
          description ??
          (!f.missing
              ? f.description
              : value == null
              ? S.current.noParamReason(label.toLowerCase())
              : S.current.wordOrderReason),
      onChanged: f.missing
          ? (_) {}
          : (v) => _w.onParam?.call(ParamEdit(node, f.code, v)),
    );
  }

  InspectorSectionVm _section(ExplorerSectionVm s) => switch (s) {
    FlowStateSectionVm() => InspectorSectionVm(
      label: S.current.secState,
      facts: [
        FactVm(label: S.current.colState, value: s.state.label(s.version)),
        FactVm(
          label: S.current.factVersion,
          value: switch (s.version) {
            final v? => S.current.factVersionOf(v),
            null => '—',
          },
          mono: true,
        ),
        FactVm(
          label: S.current.colDeployedBy,
          value: s.deployedBy ?? '—',
          mono: true,
        ),
        if (s.since case final t?)
          FactVm(
            label: S.current.factSince,
            value: '${Formats.date(t)} ${Formats.clockSeconds(t)}',
            mono: true,
          ),
        if (s.problem case final p?)
          FactVm(
            label: S.current.factProblem,
            value: p.isEmpty ? S.current.flowProblemUnknown : p,
          ),
      ],
    ),
    ParamsSectionVm() => InspectorSectionVm(
      label: S.current.secParameters,
      fields: [for (final f in s.fields) _field(s.node, f)],
      facts: [
        for (final f in s.cfg)
          FactVm(
            label: f.label,
            code: f.name,
            value: f.value ?? '—',
            mono: true,
          ),
      ],
      text: s.noEdit ? S.current.noActionReason('edit') : null,
    ),
    AttributesSectionVm() => InspectorSectionVm(
      label: S.current.secAttributes,
      facts: [
        for (final f in s.attr)
          FactVm(label: f.label, value: f.value ?? '—', mono: true),
      ],
    ),
    DiagnosticsSectionVm() => InspectorSectionVm(
      label: S.current.secDiagnostics,
      facts: [
        for (final f in s.facts)
          FactVm(
            label: f.label,
            code: f.name,
            value: f.value ?? '—',
            mono: true,
          ),
      ],
    ),
    PointFactsSectionVm() => InspectorSectionVm(
      label: S.current.secValue,
      facts: [
        FactVm(
          label: S.current.colType,
          value: s.type?.word ?? '—',
          mono: true,
        ),
        FactVm(label: S.current.colUnit, value: s.unit ?? '—'),
        FactVm(
          label: S.current.colWrite,
          value: s.level?.label ?? S.current.pointR,
        ),
      ],
      text: S.current.noEditReason,
    ),
    PointFieldsSectionVm(value: false) => InspectorSectionVm(
      label: S.current.secRegister,
      fields: [for (final f in s.fields) _field(s.node, f)],
    ),
    PointFieldsSectionVm(value: true) => InspectorSectionVm(
      label: S.current.secValue,
      columns: 3,
      fields: [for (final f in s.fields) _field(s.node, f)],
    ),
    PollingSectionVm() => () {
      String rate(num? r) => r == null ? '—' : Formats.pollRate(r);
      final now = rate(s.now);
      final i = s.rates.indexWhere((r) => rate(r) == now);
      return InspectorSectionVm(
        label: S.current.secPolling,
        note: s.staged ? S.current.stagedWas(rate(s.was)) : null,
        segments: [for (final r in s.rates) rate(r)],
        segment: i < 0 ? null : i,
        onSegment: (i) =>
            _w.onParam?.call(ParamEdit(s.node, s.code, s.rates[i])),
      );
    }(),
    WriteSectionVm() => InspectorSectionVm(
      label: S.current.secWrite,
      fields: [
        for (final f in s.fields)
          _field(
            s.node,
            f,
            description: f.kind == .toggle
                ? S.current.writableNeeds(s.level.label)
                : null,
          ),
      ],
    ),
    PublishSectionVm() => InspectorSectionVm(
      label: S.current.secPublish,
      code: [
        (
          '~meta',
          '{type: ${s.type?.word ?? '—'}'
              '${s.unit == null ? '' : ', unit: ${s.unit}'}, '
              'writable: ${s.writable}}',
        ),
        (
          '~val',
          switch ((s.value, s.time)) {
            (final v?, final t?) =>
              '{v: $v, q: ${s.quality?.name}, t: ${Formats.clockSeconds(t)}}',
            _ => '—',
          },
        ),
      ],
    ),
  };

  // ---- drawing -----------------------------------------------------------

  Widget _panels(
    BuildContext context,
    BoxConstraints box,
    Widget treePanel,
    ExplorerInspectorVm? ins,
  ) {
    final wide = box.maxWidth >= 1100;
    return SidePanels(
      left: box.maxWidth >= 700
          ? SidePanel(
              width: _w.panels.left,
              defaultWidth: wide ? 260 : 240,
              child: FaultBoundary(panel: .tree, child: treePanel),
            )
          : null,
      center: FaultBoundary(panel: .workspace, child: _workspace(context)),
      right: ins != null && wide
          ? SidePanel(
              width: _w.panels.right,
              defaultWidth: 320,
              child: FaultBoundary(
                panel: .inspector,
                child: _inspector(context, ins),
              ),
            )
          : null,
      onChanged: _w.onPanelWidth,
    );
  }

  Widget _button(ToolButtonVm b) {
    final why = b.disabled?.text;
    final onPressed = why != null ? null : () => _tool(b.tool);
    return b.tool.quiet
        ? Button.quiet(
            label: b.tool.label,
            icon: b.tool.icon,
            onPressed: onPressed,
            disabledReason: why,
          )
        : Button.secondary(
            label: b.tool.label,
            icon: b.tool.icon,
            onPressed: onPressed,
            disabledReason: why,
          );
  }

  Widget _workspace(BuildContext context) {
    final c = context.colors;
    final title = _w.title;
    if (title == null) {
      return Center(
        child: Text(
          S.current.selectANode,
          style: TextStyle(fontSize: FontSizes.lg, color: c.text4),
        ),
      );
    }
    final header = Padding(
      padding: Insets.explorerHeader,
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          if (_w.keyName case final k?)
            KeyLine(
              keyName: k,
              onCopy: _w.onCopy == null ? null : () => _w.onCopy!([k]),
              copyLabel: S.current.copyKey,
              links: _w.keyLinks,
              onOpen: _w.onTap,
            ),
          LayoutBuilder(
            // The name and the subtitle take what the buttons leave and
            // end in an ellipsis; under 560 the buttons go below them.
            builder: (context, box) {
              final heading = _heading(c, title);
              final buttons = _headerButtons(c);
              return box.maxWidth < 560
                  ? Column(
                      crossAxisAlignment: .start,
                      spacing: 12,
                      children: [heading, buttons],
                    )
                  : Row(
                      crossAxisAlignment: .end,
                      spacing: 16,
                      children: [
                        Expanded(child: heading),
                        buttons,
                      ],
                    );
            },
          ),
          SegmentedTabs(
            tabs: _tabItems,
            selected: _w.tab,
            onSelect: _w.onTab,
            plainCounts: true,
            height: 44,
          ),
        ],
      ),
    );
    final body = switch (_w.tab) {
      .parameters => _padded([
        InspectorSections(
          key: ValueKey(_w.keyName),
          sections: [for (final s in _w.params) _section(s)],
        ),
      ]),
      .actions => _padded(_actions(c)),
      .history => _padded([
        if (_w.historyNoPoint)
          Text(
            S.current.pickAPoint,
            style: TextStyle(fontSize: FontSizes.md, color: c.text4),
          )
        else ...[
          if (_w.historyFailed case final f?)
            Align(
              alignment: .centerLeft,
              child: FailChip(vm: FailChipVm.history(f)),
            ),
          SegmentedTabs(
            tabs: [
              for (final r in HistoryRangeTag.values)
                TabItemVm(id: r, label: r.label),
            ],
            selected: _w.range,
            onSelect: (r) => _w.onHistoryRange?.call(r),
          ),
          if (_w.trend case final t?)
            Trend(
              vm: t,
              empty: S.current.noHistory,
              onWindow: _w.onTrendWindow ?? (_, _) {},
              onReset: _w.onTrendReset,
            ),
          if (_w.historyRows.isNotEmpty)
            RowTable<String>(
              columns: [
                ColumnVm(S.current.colTime, flex: 2),
                ColumnVm(S.current.colValue, flex: 3),
                ColumnVm(S.current.colQuality, flex: 2),
              ],
              rows: [
                for (final h in _w.historyRows)
                  RowVm(
                    cells: [
                      CellVm(
                        title: Formats.clockSeconds(h.time),
                        monospace: true,
                      ),
                      CellVm(title: h.value, monospace: true),
                      CellVm(
                        title: h.mark?.label ?? '—',
                        tone: h.mark?.tone,
                      ),
                    ],
                  ),
              ],
              rowHeight: 40,
            ),
        ],
      ]),
      .audit => _padded([
        if (_w.auditNote case final n?)
          Text(
            n.text,
            style: TextStyle(fontSize: FontSizes.md, color: c.text4),
          ),
        if (_w.auditRows.isNotEmpty)
          RowTable<String>(
            columns: [
              ColumnVm(S.current.colTime, flex: 2),
              ColumnVm(S.current.colOp),
              ColumnVm(S.current.colKey, flex: 4),
              ColumnVm(S.current.colWho, flex: 3),
              ColumnVm(S.current.colResult, flex: 2),
            ],
            rows: [
              for (final e in _w.auditRows)
                RowVm(
                  cells: [
                    CellVm(
                      title: Formats.clockSeconds(e.time),
                      monospace: true,
                    ),
                    CellVm(title: e.op),
                    CellVm(
                      title: switch (_w.keyName) {
                        final k? when e.key.startsWith(k) =>
                          '…${e.key.substring(k.length)}',
                        _ => e.key,
                      },
                      monospace: true,
                    ),
                    CellVm(title: e.who, monospace: true),
                    if (e.status == 0)
                      CellVm(title: S.current.auditDone, tone: .good)
                    else
                      CellVm(
                        title: S.current.auditRefused(e.status),
                        tone: .bad,
                      ),
                  ],
                ),
            ],
            rowHeight: 40,
          ),
      ]),
      .contents => _padded([
        RowTable(
          columns: [
            ColumnVm(S.current.colName, flex: 4),
            ColumnVm(S.current.colKind, flex: 2),
            ColumnVm(S.current.colValue, flex: 3),
          ],
          rows: [
            for (final k in _w.children)
              RowVm(
                id: k.key,
                selected: k.selected,
                cells: [
                  CellVm(title: k.name, subtitle: k.display, monospace: true),
                  CellVm(
                    title: switch (k) {
                      ChildValueRowVm(:final type, :final writable) => [
                        type.word,
                        if (writable) S.current.pointRw,
                      ].join(' · '),
                      ChildNodeRowVm(:final kind) => kind.word,
                    },
                  ),
                  CellVm(
                    title: switch (k) {
                      ChildValueRowVm(:final value) => value ?? '—',
                      ChildNodeRowVm() => '—',
                    },
                    monospace: true,
                  ),
                ],
              ),
          ],
          rowHeight: 48,
          onTap: _w.onChild,
          empty: S.current.noChildren,
        ),
        if (_w.children.isNotEmpty)
          Text(
            S.current.childrenNote,
            style: TextStyle(fontSize: FontSizes.md, color: c.text4),
          ),
      ]),
      .points => _pointsTab(c),
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [header, body],
    );
  }

  /// The node's name in mono 26 (its display name in sans 26 with the name
  /// in mono under it, when it has one) with its state pill, and one
  /// subtitle line under it: both one line with an ellipsis, the full text
  /// as a tooltip (a display name can be a sentence).
  Widget _heading(AppColors c, String name) => Column(
    crossAxisAlignment: .start,
    mainAxisSize: .min,
    spacing: 6,
    children: [
      Row(
        spacing: 12,
        children: [
          Flexible(
            child: Tooltip(
              message: name,
              waitDuration: const Duration(milliseconds: 600),
              child: Text(
                name,
                maxLines: 1,
                overflow: .ellipsis,
                style: _w.titleName == null
                    ? mono(
                        size: FontSizes.pageTitle,
                        weight: .w600,
                        color: c.text1,
                      )
                    : TextStyle(
                        fontSize: FontSizes.pageTitle,
                        fontWeight: .w600,
                        color: c.text1,
                      ),
              ),
            ),
          ),
          if (_w.pill case final p?) StatusPill(vm: p, dense: true),
        ],
      ),
      if (_w.titleName case final n?)
        Text(
          n,
          key: const ValueKey('title-name'),
          maxLines: 1,
          overflow: .ellipsis,
          style: mono(color: c.text3),
        ),
      if (_w.subtitle?.text case final s?)
        Tooltip(
          message: s,
          waitDuration: const Duration(milliseconds: 600),
          child: Text(
            s,
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(fontSize: FontSizes.lg, color: c.text3),
          ),
        ),
    ],
  );

  /// Edit dataflow, Ping, Actions ▾.
  Widget _headerButtons(AppColors c) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (_w.flowId case final id?)
        Button.secondary(
          label: S.current.editDataflow,
          icon: AppIcon.actionEdit,
          onPressed: _w.flowDisabled == null
              ? () => _w.onTapFlowEditor(id)
              : null,
          disabledReason: _w.flowDisabled?.text,
        ),
      for (final b in _w.headerButtons) _button(b),
      if (_w.keyName case final key?)
        Builder(
          builder: (context) => _actionsButton(
            c,
            label: S.current.tabActions,
            onTap: _w.onOpenMenu == null
                ? null
                : () {
                    final box = context.findRenderObject()! as RenderBox;
                    _openMenu(
                      key,
                      box.localToGlobal(
                        Offset(box.size.width - 300, box.size.height + 6),
                      ),
                    );
                  },
          ),
        ),
    ],
  );

  Widget _padded(List<Widget> children) => Padding(
    padding: Insets.explorerTab,
    child: Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: children,
    ),
  );

  Widget _pointsTab(AppColors c) {
    final bar = _w.selectionBar;
    final toolbarRow = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: SizedBox(
        height: AppSizes.pointsBar,
        child: bar != null
            ? Row(
                spacing: 8,
                children: [
                  Text(
                    S.current.nSelected(bar.count),
                    style: TextStyle(
                      fontSize: FontSizes.lg,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                  Gaps.hXs,
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: .horizontal,
                      child: Row(
                        spacing: 8,
                        children: [for (final b in bar.buttons) _button(b)],
                      ),
                    ),
                  ),
                  Button.quiet(
                    label: S.current.clearSelection,
                    onPressed: _w.onClear,
                  ),
                ],
              )
            : LayoutBuilder(
                // The filter takes up to 240 and gives way first; the
                // buttons scroll only when even a 160 filter leaves them
                // too little room.
                builder: (context, box) => Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: .horizontal,
                        child: Row(
                          spacing: 8,
                          children: [
                            for (final b in _w.toolbar)
                              if (b.tool.quiet) _button(b) else _filled(c, b),
                          ],
                        ),
                      ),
                    ),
                    if (_w.onPointFilter != null)
                      SizedBox(
                        width: (box.maxWidth - 500).clamp(160, 240),
                        child: _filterBox(c),
                      ),
                  ],
                ),
              ),
      ),
    );
    final showEmpty =
        !_w.pointsLoading && _w.points.isEmpty && _w.pointsEmpty != null;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        toolbarRow,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: showEmpty
              ? _empty(c)
              : PointsTable(
                  rows: _w.points,
                  loading: _w.pointsLoading,
                  onTap: _w.onPoint,
                  onCheck: _w.onCheck,
                  onRange: _w.onRange,
                  onCheckAll: _w.onCheckAll,
                ),
        ),
        Padding(
          padding: Insets.explorerPointsNote,
          child: Text(
            S.current.pointsNote,
            style: TextStyle(fontSize: FontSizes.md, color: c.text4),
          ),
        ),
      ],
    );
  }

  /// Add point: an outline on the raised ground.
  Widget _filled(AppColors c, ToolButtonVm b) => DecoratedBox(
    decoration: BoxDecoration(color: c.ground2, borderRadius: Radii.button),
    child: _button(b),
  );

  Widget _filterBox(AppColors c) => Container(
    height: 40,
    padding: Insets.field,
    decoration: BoxDecoration(
      color: c.ground1,
      border: .all(color: c.line1),
      borderRadius: Radii.button,
    ),
    child: Row(
      spacing: 8,
      children: [
        AppIconView(AppIcon.uiSearch, size: IconSizes.sm, color: c.text4),
        Expanded(
          child: TextFormField(
            initialValue: _w.pointFilter,
            onChanged: _w.onPointFilter,
            style: TextStyle(fontSize: FontSizes.md, color: c.text1),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: S.current.filterPoints,
              hintStyle: TextStyle(fontSize: FontSizes.md, color: c.text4),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _empty(AppColors c) => Container(
    padding: Insets.explorerEmpty,
    decoration: BoxDecoration(
      color: c.ground1,
      border: .all(color: c.line1),
      borderRadius: Radii.card,
    ),
    child: Column(
      spacing: 16,
      children: [
        Text(
          _w.pointsEmpty!.text,
          style: TextStyle(
            fontSize: FontSizes.sectionTitle,
            fontWeight: .w600,
            color: c.text1,
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: .center,
          children: [for (final b in _w.emptyButtons) _button(b)],
        ),
      ],
    ),
  );

  List<Widget> _actions(AppColors c) => [
    for (final g in _w.actionGroups)
      Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Column(
            crossAxisAlignment: .stretch,
            spacing: 4,
            children: [
              SectionLabel(
                g.staged ? S.current.configureStaged : S.current.operateRunsNow,
              ),
              Text(
                g.staged
                    ? S.current.configureStagedNote
                    : S.current.operateRunsNowNote,
                style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, box) {
              final n = box.maxWidth > 640 ? 2 : 1;
              final w = (box.maxWidth - 12 * (n - 1)) / n;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in g.cards)
                    SizedBox(
                      width: w,
                      child: ActionCard(vm: card, onTap: _w.onAction),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    if (_w.result case final r?) ...[
      Row(
        spacing: 12,
        children: [
          Text(
            S.current.resultOf(r.action),
            style: const TextStyle(fontSize: FontSizes.lg, fontWeight: .w600),
          ),
          QualityMark(
            vm: QualityMarkVm(
              label: S.current.rowsAnswered(r.count),
              tone: .good,
            ),
          ),
        ],
      ),
      if (r.rows.isNotEmpty)
        RowTable<String>(
          columns: [for (final c in r.columns) ColumnVm(c)],
          rows: [
            for (final row in r.rows)
              RowVm(
                cells: [
                  for (final cell in row) CellVm(title: cell, monospace: true),
                ],
              ),
          ],
        )
      else
        SizedBox(
          height: AppSizes.logPane,
          child: LogView(lines: r.lines),
        ),
    ],
  ];

  Widget _inspector(BuildContext context, ExplorerInspectorVm ins) {
    final c = context.colors;
    return switch (ins) {
      PointInspectorVm() => Inspector(
        eyebrow: S.current.insPoint,
        title: '',
        width: 320,
        header: Column(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            // The display name when there is one, its name (the key
            // segment) in mono under it (owner 2026-11-11).
            if (ins.display case final d?) ...[
              Tooltip(
                message: d,
                waitDuration: const Duration(milliseconds: 600),
                child: Text(
                  d,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontSize: FontSizes.inspectorTitle,
                    fontWeight: .w600,
                    color: c.text1,
                  ),
                ),
              ),
              Text(
                ins.name,
                maxLines: 1,
                overflow: .ellipsis,
                style: mono(size: FontSizes.sm, color: c.text3),
              ),
            ] else
              Text(
                ins.name,
                maxLines: 1,
                overflow: .ellipsis,
                style: mono(size: FontSizes.inspectorTitle, weight: .w600),
              ),
            Row(
              spacing: 10,
              children: [
                Flexible(
                  child: LinesText(
                    ins.value ?? '—',
                    onOpen: _w.onViewPoint,
                    style: mono(size: FontSizes.figure, color: c.text1),
                  ),
                ),
                QualityMark(
                  vm: ins.mark.vm(at: ins.time),
                  size: FontSizes.sm,
                ),
                if (_w.onViewPoint case final view?)
                  IconButton(
                    tooltip: S.current.viewValue,
                    visualDensity: .compact,
                    onPressed: view,
                    icon: AppIconView(
                      AppIcon.uiView,
                      size: IconSizes.md,
                      color: c.text3,
                    ),
                  ),
              ],
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 18,
          children: [
            if (ins.fail case final f?)
              ReadFail(vm: f, onRetry: _w.onReadAgain),
            InspectorSections(
              key: ValueKey(ins.key),
              sections: [for (final s in ins.sections) _section(s)],
            ),
            if (ins.edit case final kind?) ...[
              SectionLabel(S.current.setValue),
              ActionForm(
                key: ValueKey('set:${ins.name}'),
                fields: [
                  ParamFieldVm(
                    // the point's own field; a `~set` sets its `value`
                    id: ins.key,
                    code: 'value',
                    label: S.current.newValue,
                    kind: kind,
                    value: ins.editValue,
                    choices: ins.choices,
                    choiceLabels: ins.choiceLabels,
                    onChanged: (_) {},
                  ),
                ],
                submit: S.current.stage,
                busy: _w.submit?.busy ?? false,
                disabledReason: ins.readOnly?.text,
                onSubmit: _w.submit?.onSubmit ?? (_) => null,
              ),
            ],
          ],
        ),
      ),
      ActionInspectorVm() => Inspector(
        eyebrow: S.current.insAction,
        title: ins.title,
        width: 320,
        onClose: _w.onCloseInspector,
        header: Column(
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            KeyText(ins.keyName, size: FontSizes.sm, color: c.text3),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in [
                  if (ins.staged) S.current.tagStaged else S.current.tagRunsNow,
                  S.current.tagNeeds(ins.level.label),
                  if (ins.result case final r?) S.current.returns(r),
                ])
                  Container(
                    padding: Insets.monoTag,
                    decoration: BoxDecoration(
                      color: c.ground4,
                      borderRadius: Radii.chip,
                    ),
                    child: Text(
                      t,
                      style: mono(size: FontSizes.xs, color: c.text2),
                    ),
                  ),
              ],
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            ActionForm(
              key: ValueKey((ins.node, ins.action)),
              fields: ins.fields,
              submit: ins.staged ? S.current.stage : S.current.runNow,
              busy: _w.submit?.busy ?? false,
              disabledReason: ins.disabled?.text,
              onSubmit: _w.submit?.onSubmit ?? (_) => null,
            ),
            Text(
              ins.staged
                  ? S.current.stagedActionNote
                  : S.current.runNowNote(ins.user),
              style: TextStyle(
                fontSize: FontSizes.sm,
                height: LineHeights.body,
                color: c.text3,
              ),
            ),
            SectionLabel(S.current.sameCallCli),
            Container(
              padding: Insets.box,
              decoration: BoxDecoration(
                color: c.ground0,
                border: .all(color: c.line1),
                borderRadius: Radii.button,
              ),
              child: SelectableText(
                ins.cli,
                style: mono(size: FontSizes.sm, color: c.text2),
              ),
            ),
          ],
        ),
      ),
      NodeInspectorVm() => Inspector(
        eyebrow: ins.kind.eyebrow,
        title: ins.title,
        header: switch (ins.name) {
          final n? => KeyText(n, size: FontSizes.sm, color: c.text3),
          null => null,
        },
        width: 320,
        child: switch (ins.fail) {
          final f? => Column(
            crossAxisAlignment: .stretch,
            spacing: 18,
            children: [
              ReadFail(vm: f, onRetry: _w.onReadAgain),
              InspectorSections(
                key: ValueKey(ins.key),
                sections: [for (final s in ins.sections) _section(s)],
              ),
            ],
          ),
          null => InspectorSections(
            key: ValueKey(ins.key),
            sections: [for (final s in ins.sections) _section(s)],
          ),
        },
      ),
    };
  }

  /// Actions ▾: an outline 40 with a chevron.
  Widget _actionsButton(
    AppColors c, {
    required String label,
    VoidCallback? onTap,
  }) => Material(
    color: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: Radii.button,
      side: BorderSide(color: c.line3),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: Radii.button,
      child: Container(
        height: 40,
        padding: Insets.button,
        child: Row(
          mainAxisSize: .min,
          spacing: 8,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: FontSizes.lg, color: c.text1),
            ),
            if (_w.menuOpening)
              ArcSpinner(color: c.text1, size: 14)
            else
              AppIconView(
                AppIcon.uiChevronDown,
                size: IconSizes.sm,
                color: c.text1,
              ),
          ],
        ),
      ),
    ),
  );
}
