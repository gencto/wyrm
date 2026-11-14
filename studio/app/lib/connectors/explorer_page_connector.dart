import 'dart:async';
import 'dart:convert';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/nodes/actions/check_points_action.dart';
import 'package:business/redux/nodes/actions/clear_selection_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/mark_nodes_action.dart';
import 'package:business/redux/nodes/actions/retrieve_audit_action.dart';
import 'package:business/redux/nodes/actions/retrieve_history_action.dart';
import 'package:business/redux/nodes/actions/retrieve_nodes_action.dart';
import 'package:business/redux/nodes/actions/retry_read_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/select_point_action.dart';
import 'package:business/redux/nodes/actions/set_action_action.dart';
import 'package:business/redux/nodes/actions/set_history_range_action.dart';
import 'package:business/redux/nodes/actions/set_history_window_action.dart';
import 'package:business/redux/nodes/actions/set_point_filter_action.dart';
import 'package:business/redux/nodes/actions/set_tab_action.dart';
import 'package:business/redux/nodes/actions/set_tree_filter_action.dart';
import 'package:business/redux/nodes/actions/set_viewed_point_action.dart';
import 'package:business/redux/nodes/actions/stage_invoke_action.dart';
import 'package:business/redux/nodes/actions/stage_point_edit_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:business/redux/nodes/actions/toggle_node_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/wyrm/calls.dart' show clearedNames;
import 'package:business/wyrm/history_steps.dart';
import 'package:business/wyrm/keys.dart';
import 'package:business/wyrm/kinds.dart';
import 'package:business/wyrm/labels.dart';
import 'package:business/wyrm/mappers/flow_value_mapper.dart';
import 'package:business/wyrm/mappers/link_info_mapper.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:business/wyrm/points.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/action_info.dart';
import 'package:models/flow_summary.dart';
import 'package:models/link_mode.dart';
import 'package:models/live_value.dart';
import 'package:models/node_detail.dart';
import 'package:models/node_info.dart';
import 'package:models/node_kind.dart';
import 'package:models/param_spec.dart';
import 'package:models/quality.dart';
import 'package:ui/alerts/read_fail.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/containers/action_card.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/containers/inspector_sections.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/indicators/fail_chip.dart';
import 'package:ui/indicators/quality_mark.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/node_menu.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/explorer_page.dart';
import 'package:ui/tables/points_table.dart';
import 'package:ui/tables/row_table.dart';
import 'package:ui/trees/node_tree.dart';
import 'package:ui/trees/tree_row.dart';

import '../common/flow_state.dart';
import '../common/forms.dart';
import '../common/side_panels.dart';
import '../common/tab_visibility.dart';
import '../common/trend.dart';
import '../common/value_viewer.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';
import 'assistant_page_connector.dart';

/// The sections of a site the tree starts from (`sys/**` is not in the
/// tree: it is in Links, Access, Sites and System, docs/studio.md §7.4).
const _sections = ['downstream', 'dataflows', 'storage', 'upstream'];

/// Explorer's keys (docs/design/specs/explorer.md §6): ⌘⇧C copies the
/// keys, ⌘C the value of the point in the inspector, Esc clears the
/// selection.
enum _Key { copyKeys, copyValue, clear, assistant }

class _KeyIntent extends Intent {
  const _KeyIntent(this.key);

  final _Key key;
}

/// Runs a [_Key] unless a text field has the focus (its own ⌘C and Esc
/// win) or there is nothing to do; then the key passes on.
class _KeyAction extends Action<_KeyIntent> {
  _KeyAction({required this.enabled, required this.run});

  final bool Function(_Key key) enabled;
  final void Function(_Key key) run;

  @override
  bool isEnabled(_KeyIntent intent) =>
      enabled(intent.key) &&
      FocusManager.instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>() ==
          null;

  @override
  Object? invoke(_KeyIntent intent) {
    run(intent.key);
    return null;
  }
}

/// The workspaces the tree's note links to, by their rail index.
const _noteLinks = {'links': 1, 'access': 4, 'sites': 5, 'system': 7};

/// The poll rates of the Polling segments, in seconds.
const _polls = [0.25, 0.5, 1.0, 5.0];

/// Where an `edit` parameter of a point goes in the inspector (docs/design/
/// specs/explorer.md §4); a parameter not named here goes to Register.
const _valueParams = {'unit', 'scale', 'offset', 'precision'};
const _writeParams = {'writable', 'writable_by_master'};

/// What Explorer subscribes to while its tab is shown: the children of the
/// selected node, the selected point, and the links' states for the dots.
final class _Watch {
  var shown = false;
  var keys = <String>[];
}

final _watching = _Watch();

@RoutePage()
class ExplorerPageConnector extends StatelessWidget {
  const ExplorerPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    onWillChange: (context, store, before, now) {
      if (_watching.shown && !_sameKeys(before.watch, now.watch)) {
        store
          ..dispatchSync(WatchKeysAction(now.watch))
          ..dispatchSync(UnwatchKeysAction(before.watch));
        _watching.keys = now.watch;
      }
      if (now.tab == 'audit' &&
          now.auditKey != null &&
          (before.tab != 'audit' || before.keyName != now.keyName)) {
        now.onAudit();
      }
    },
    builder: (context, vm) => TabVisibility(
      onShow: () {
        _watching
          ..shown = true
          ..keys = vm.watch;
        vm.onShow();
      },
      onHide: () {
        _watching.shown = false;
        vm.onHide(_watching.keys);
      },
      child: Shortcuts(
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
          actions: {
            _KeyIntent: _KeyAction(
              enabled: (k) => switch (k) {
                _Key.copyKeys => vm.copyKeys.isNotEmpty,
                _Key.copyValue => vm.pointValue != null,
                _Key.clear => true,
                _Key.assistant => true,
              },
              run: (k) => switch (k) {
                _Key.copyKeys => _copy(context, vm.copyKeys),
                _Key.copyValue => _copyValue(context, vm.pointValue),
                _Key.clear => vm.onClear(),
                _Key.assistant => vm.onToggleAssistant(),
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ExplorerPage(
                    treeLabel: vm.treeLabel,
                    tree: vm.tree,
                    treeLoading: vm.treeLoading,
                    treeFilter: vm.treeFilter,
                    onTreeFilter: vm.onTreeFilter,
                    treeFilterHint: S.current.filter,
                    treeNote: TreeNoteVm(
                      lead: S.current.treeNoteLead,
                      code: 'sys/**',
                      middle: S.current.treeNoteMiddle,
                      and: S.current.andWord,
                      links: [
                        ('links', S.current.wsLinks),
                        ('access', S.current.wsAccess),
                        ('sites', S.current.wsSites),
                        ('system', S.current.wsSystem),
                      ],
                    ),
                    onNoteLink: (id) => AutoTabsRouter.of(
                      context,
                    ).setActiveIndex(_noteLinks[id] ?? 0),
                    onTap: vm.onSelect,
                    onToggle: vm.onToggle,
                    onMark: vm.onMark,
                    onMarkRange: vm.onMarkRange,
                    onMenu: (id, at) => _menu(context, vm, id, at),
                    keyName: vm.keyName,
                    onCopyKey: vm.keyName == null
                        ? null
                        : () => _copy(context, [vm.keyName!]),
                    copyKeyLabel: S.current.copyKey,
                    keyLinks: vm.keyLinks,
                    title: vm.title,
                    titleName: vm.titleName,
                    pill: vm.pill,
                    subtitle: vm.subtitle,
                    headerButtons: vm.headerButtons,
                    openButton: vm.openButton,
                    actionsLabel: vm.keyName == null
                        ? null
                        : S.current.tabActions,
                    onActions: (at) => _menu(context, vm, vm.keyName!, at),
                    onTool: (id) => _tool(context, vm, id),
                    empty: S.current.selectANode,
                    tabs: vm.tabs,
                    tab: vm.tab,
                    onTab: vm.onTab,
                    toolbar: vm.toolbar,
                    selectionBar: vm.selectionBar,
                    onClearSelection: vm.onClear,
                    pointFilter: vm.pointFilter,
                    onPointFilter: vm.onPointFilter,
                    pointFilterHint: S.current.filterPoints,
                    points: vm.points,
                    pointLabels: PointsTableLabels(
                      point: S.current.colPoint,
                      register: S.current.colRegister,
                      type: S.current.colType,
                      unit: S.current.colUnit,
                      poll: S.current.colPoll,
                      value: S.current.colValue,
                      quality: S.current.colQuality,
                      write: S.current.colWrite,
                      was: S.current.wasWord,
                    ),
                    pointsLoading: vm.pointsLoading,
                    pointsEmpty: vm.pointsEmpty,
                    emptyButtons: vm.emptyButtons,
                    pointsNote: S.current.pointsNote,
                    childColumns: [
                      ColumnVm(S.current.colName, flex: 4),
                      ColumnVm(S.current.colKind, flex: 2),
                      ColumnVm(S.current.colValue, flex: 3),
                    ],
                    children: vm.children,
                    childrenEmpty: S.current.noChildren,
                    childrenNote: vm.children.isEmpty
                        ? null
                        : S.current.childrenNote,
                    onChild: vm.onSelect,
                    onPoint: vm.onPoint,
                    onCheck: vm.onCheck,
                    onRange: vm.onRange,
                    onCheckAll: vm.onCheckAll,
                    params: vm.params,
                    actionGroups: vm.actionGroups,
                    onAction: vm.onAction,
                    result: vm.result,
                    ranges: const [
                      TabItemVm(id: '1h', label: '1 h'),
                      TabItemVm(id: '24h', label: '24 h'),
                      TabItemVm(id: '7d', label: '7 d'),
                    ],
                    range: vm.range,
                    onHistoryRange: vm.onHistoryRange,
                    trend: vm.trend,
                    onTrendWindow: vm.onTrendWindow,
                    onTrendReset: vm.onTrendReset,
                    historyColumns: [
                      ColumnVm(S.current.colTime, flex: 2),
                      ColumnVm(S.current.colValue, flex: 3),
                      ColumnVm(S.current.colQuality, flex: 2),
                    ],
                    historyRows: vm.historyRows,
                    historyNote: vm.historyNote,
                    historyFail: vm.historyFail,
                    auditColumns: [
                      ColumnVm(S.current.colTime, flex: 2),
                      ColumnVm(S.current.colOp),
                      ColumnVm(S.current.colKey, flex: 4),
                      ColumnVm(S.current.colWho, flex: 3),
                      ColumnVm(S.current.colResult, flex: 2),
                    ],
                    auditRows: vm.auditRows,
                    auditNote: vm.auditNote,
                    inspector: vm.inspector,
                    busy: vm.busy,
                    onSubmit: vm.onSubmit,
                    onReadAgain: vm.onReadAgain,
                    onCloseInspector: vm.onCloseInspector,
                    panels: vm.panelWidths,
                    onPanelWidth: vm.onPanelWidth,
                    onTapFlowEditor: vm.onTapFlowEditor,
                    viewer: vm.viewer,
                    viewerTables: viewerTables,
                    onViewPoint: vm.onViewPoint,
                    onCloseViewer: vm.onCloseViewer,
                    viewLabel: S.current.viewValue,
                    copyLabel: S.current.copyValue,
                    copiedLabel: S.current.copiedValue,
                    closeLabel: S.current.closeLabel,
                  ),
                ),
                // the Assistant about the selection (⌘J, spec assistant.md §5)
                if (vm.assistantOpen)
                  const Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: 420,
                    child: AssistantDrawerConnector(),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  static bool _sameKeys(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);

  /// Copies [keys], one per line, and says so for 2 s.
  static void _copy(BuildContext context, List<String> keys) {
    if (keys.isEmpty) {
      return;
    }
    unawaited(Clipboard.setData(ClipboardData(text: keys.join('\n'))));
    StoreProvider.dispatchSync<AppState>(
      context,
      ShowNoticeAction(
        keys.length == 1
            ? S.current.keyCopied
            : S.current.keysCopied(keys.length),
      ),
    );
  }

  /// ⌘C: the value of the point in the inspector.
  static void _copyValue(BuildContext context, String? value) {
    if (value == null) {
      return;
    }
    unawaited(Clipboard.setData(ClipboardData(text: value)));
    StoreProvider.dispatchSync<AppState>(
      context,
      ShowNoticeAction(S.current.valueCopied),
    );
  }

  /// The node menu of [id] at [at] (tree `⋯`, right click, Actions ▾).
  static Future<void> _menu(
    BuildContext context,
    _Vm vm,
    String id,
    Offset at,
  ) async {
    if (id != vm.keyName) {
      vm.onSelect(id);
    }
    final menu = await vm.menuOf(id);
    if (!context.mounted || menu == null) {
      return;
    }
    final picked = await NodeMenu.show(context, at: at, vm: menu);
    if (!context.mounted || picked == null) {
      return;
    }
    if (picked == NodeMenu.copyId) {
      _copy(context, [id]);
    } else {
      vm.onPickAction(picked);
    }
  }

  /// A header, toolbar, empty-state or selection-bar button.
  static Future<void> _tool(BuildContext context, _Vm vm, String id) async {
    switch (id) {
      case 'copy_keys':
        _copy(context, vm.copyKeys);
      case 'set_poll':
        final box = context.findRenderObject() as RenderBox?;
        final at = box == null
            ? Offset.zero
            : box.localToGlobal(const Offset(320, 180));
        final picked = await NodeMenu.show(
          context,
          at: at,
          vm: NodeMenuVm(
            title: S.current.colPoll,
            subtitle: S.current.nSelected(vm.checkedCount),
            groups: [
              NodeMenuGroupVm(
                label: S.current.setPoll,
                items: [
                  for (final s in _polls)
                    NodeMenuItemVm(id: '$s', label: pollText(s)),
                ],
              ),
            ],
            copyLabel: S.current.copyKeys,
          ),
        );
        if (!context.mounted || picked == null) {
          return;
        }
        if (picked == NodeMenu.copyId) {
          _copy(context, vm.copyKeys);
        } else {
          vm.onSetPoll(double.parse(picked));
        }
      default:
        vm.onTool(id);
    }
  }
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ExplorerPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  String get _root => site.root ?? '';

  static String _parent(String key) => key.substring(0, key.lastIndexOf('/'));

  /// The children of [key] in the order the broker listed them.
  List<NodeInfo> _children(String key) => [
    for (final k in nodes.view)
      if (_parent(k) == key) ?nodes.table[k],
  ];

  (Tone, String)? _linkDot(String key) {
    if (_parent(key) != '$_root/downstream') {
      return null;
    }
    final id = key.split('/').last;
    final v = live.values['$_root/sys/links/$id/state'];
    if (v == null) {
      return null;
    }
    return switch (linkStateOf(v.value)) {
      'connected' => (Tone.good, S.current.stateConnected),
      'failed' => (Tone.bad, S.current.stateFailed),
      'stopped' => (Tone.neutral, S.current.stateStopped),
      _ => (Tone.warn, S.current.stateStarting),
    };
  }

  /// The framework `status` of [key] (connection or device): its enum name
  /// and tone.
  StatusPillVm? _statusPill(String key) {
    final v = live.values['$key/status'];
    if (v == null) {
      return null;
    }
    final name = valueText(v.value, choices: _choices('$key/status'));
    final tone = switch (name.toLowerCase()) {
      'connected' => Tone.good,
      'connecting' || 'unknown' => Tone.warn,
      'failed' => Tone.bad,
      _ => Tone.neutral,
    };
    return StatusPillVm(
      label: name,
      tone: tone,
      mark: tone == Tone.warn ? .ring : .dot,
    );
  }

  /// The reads of [key] that failed, one sentence each: its value, its
  /// list of children, its `~meta` (docs/design/specs/errors.md §4).
  List<String> _failLines(String key) => [
    if (live.failed[key] case final s?) S.current.readFailedTip(s),
    if (nodes.listFailed[key] case final s?) S.current.listFailedTip(s),
    if (nodes.metaFailed[key] case final s?) S.current.metaFailedTip(s),
  ];

  /// The `read failed` chip of a tree row, the sentences as its tooltip.
  FailChipVm? _failChip(String key) {
    final lines = _failLines(key);
    return lines.isEmpty
        ? null
        : FailChipVm(label: S.current.readFailed, tip: lines.join('\n'));
  }

  /// The same mark in the inspector, with `Read again`.
  ReadFailVm? _readFail(String key) {
    final lines = _failLines(key);
    return lines.isEmpty
        ? null
        : ReadFailVm(
            id: key,
            chip: FailChipVm(label: S.current.readFailed),
            lines: lines,
            retry: S.current.readAgain,
          );
  }

  String? _chip(String key) {
    if (_parent(key) != '$_root/downstream') {
      return null;
    }
    final l = links.table[key.split('/').last];
    return switch (l?.mode) {
      LinkMode.process => S.current.modeProcess,
      LinkMode.external => S.current.modeExternal,
      LinkMode.wasm => 'WASM',
      LinkMode.embedded => S.current.modeEmbedded,
      null => null,
    };
  }

  /// The tree rows; with a filter, the nodes whose name holds it and their
  /// ancestors, opened.
  List<TreeRowVm> _rows() {
    final out = <TreeRowVm>[];
    final selected = nodes.selectedNode;
    final f = nodes.treeFilter.trim().toLowerCase();
    final keep = <String>{};
    if (f.isNotEmpty) {
      for (final n in nodes.table.values) {
        if (n.type == null && n.name.toLowerCase().contains(f)) {
          final parts = n.key.split('/');
          for (var i = 3; i <= parts.length; i++) {
            keep.add(parts.sublist(0, i).join('/'));
          }
        }
      }
    }
    void walk(
      String key,
      String name,
      int depth, {
      NodeInfo? info,
      bool section = false,
    }) {
      if (f.isNotEmpty && !keep.contains(key)) {
        return;
      }
      final open =
          nodes.expanded.contains(key) ||
          (f.isNotEmpty && keep.any((k) => k.startsWith('$key/')));
      final dot = _linkDot(key);
      final kids = open ? _children(key) : const <NodeInfo>[];
      out.add(
        TreeRowVm(
          id: key,
          name: name,
          depth: depth,
          icon: AppIcon.nodeName(
            key: key,
            root: _root,
            profile: info?.profile,
            type: info?.type,
          ),
          hasChildren: section || (info?.hasChildren ?? false),
          expanded: open,
          selected: key == selected,
          marked: nodes.marked.contains(key),
          chip: _chip(key),
          dot: dot?.$1,
          dotLabel: dot?.$2,
          meta: open && kids.isNotEmpty ? '${kids.length}' : null,
          hasHistory: info?.hasHistory ?? false,
          staged: changes.table.values.any((c) => c.key == key),
          failed: _failChip(key),
        ),
      );
      if (open) {
        for (final k in kids) {
          if (k.type == null || k.hasChildren) {
            walk(k.key, k.name, depth + 1, info: k);
          }
        }
      }
    }

    for (final s in _sections) {
      walk('$_root/$s', s, 0, section: true);
    }
    return out;
  }

  List<String> _watch() {
    final sel = nodes.selectedNode;
    return [
      '$_root/sys/links/*/state',
      if (sel != null) '$sel/*',
      // The point in the value viewer stays live when the tree moves on.
      ?nodes.viewedPoint,
      // A flow's state is its own `~val`.
      if (sel != null && _kind(sel, nodes.detail[sel]) == NodeKind.flow) sel,
    ];
  }

  /// The enum names of [key]: a list carries none, the full meta does.
  List<String> _choices(String key) {
    final d = nodes.detail[key]?.choices;
    if (d != null && d.isNotEmpty) {
      return d.unlock;
    }
    return nodes.table[key]?.choices.unlock ?? const [];
  }

  /// The kind of [key], from its place, profile and actions: it picks the
  /// frame (docs/design/specs/explorer.md "Frames by node kind").
  NodeKind _kind(String key, NodeDetail? d) => nodeKindOf(
    key: key,
    root: _root,
    profile: d?.profile ?? nodes.table[key]?.profile,
    actions: [for (final a in d?.actions ?? const <ActionInfo>[]) a.name],
  );

  static String _kindWord(NodeKind kind) => switch (kind) {
    NodeKind.device => S.current.kindDevice,
    NodeKind.connection => S.current.kindConnection,
    NodeKind.link => S.current.kindLink,
    NodeKind.flow => S.current.kindDataflow,
    NodeKind.storage => S.current.kindStorage,
    NodeKind.broker => S.current.kindBroker,
    NodeKind.folder => S.current.kindFolder,
  };

  /// A display name worth showing beside [key]'s name: not empty, not the
  /// name again.
  String? _display(String key, NodeDetail? d) {
    final name = key.split('/').last;
    return switch (d?.display ?? nodes.table[key]?.display) {
      final s? when s.trim().isNotEmpty && s != name => s,
      _ => null,
    };
  }

  ActionInfo? _actionOf(String key, String name) =>
      nodes.detail[key]?.actions.where((a) => a.name == name).firstOrNull;

  /// `HR 10`, `IR 3`, `Coil 1`, `DI 7`: the modbus area and the offset as
  /// the driver takes it (`addr`, 0-based; docs/modbus.md), or the cfg's
  /// `address`.
  static String _register(NodeDetail? d) {
    final cfg = d?.cfg;
    if (cfg == null) {
      return '—';
    }
    if (cfg['addr'] case final a?) {
      final area = switch (cfg['table']) {
        'holding' => 'HR',
        'input' => 'IR',
        'coil' => 'Coil',
        'discrete' => 'DI',
        final t? => t,
        null => '',
      };
      return area.isEmpty ? a : '$area $a';
    }
    return cfg['address'] ?? '—';
  }

  @override
  _Vm fromStore() {
    final sel = nodes.selectedNode;
    final detail = sel == null ? null : nodes.detail[sel];
    final kids = sel == null ? const <NodeInfo>[] : _children(sel);
    final pointsAll = kids.where(isPoint).toList();
    final f = nodes.pointFilter.trim().toLowerCase();
    final shown = [
      for (final p in pointsAll)
        if (f.isEmpty ||
            p.name.toLowerCase().contains(f) ||
            (p.display?.toLowerCase().contains(f) ?? false))
          p,
    ];
    final actions = detail?.actions.unlock ?? const <ActionInfo>[];
    final kind = sel == null ? NodeKind.folder : _kind(sel, detail);
    final flow = sel == null || kind != NodeKind.flow
        ? null
        : flowSummaryOfValue(
            sel.split('/').last,
            live.values[sel]?.value,
            description: _display(sel, detail),
          );
    final tabs = _tabs(kind, pointsAll.length, kids, actions.length);
    // The tab stays when the next node has it; else the frame's first.
    final tab = tabs.any((t) => t.id == nodes.tab) ? nodes.tab : tabs.first.id;
    final linkDot = sel == null ? null : _linkDot(sel);
    final point = nodes.point;
    final checked = nodes.checked;
    final order = [for (final p in shown) p.key];
    final canAudit = site.can('config', '$_root/sys/audit');
    final shownDisplay = sel == null || kind == NodeKind.flow
        ? null
        : _display(sel, detail);
    return _Vm(
      treeLabel: S.current.treeOf(site.viewed ?? ''),
      tree: _rows(),
      treeLoading: nodes.view.isEmpty && nodes.isWaiting,
      treeFilter: nodes.treeFilter,
      watch: _watch(),
      keyName: sel,
      keyLinks: parentLinksOf(sel, sections: _sections),
      // The display name with the name under it (owner 2026-11-11,
      // docs/design/specs/explorer.md §3); a flow's display name is its
      // description and stays in the subtitle.
      title: shownDisplay ?? sel?.split('/').last,
      titleName: shownDisplay == null ? null : sel?.split('/').last,
      pill: switch (sel) {
        null => null,
        _ when flow != null => () {
          final (tone, word, _) = flowStateOf(flow);
          return StatusPillVm(label: word, tone: tone);
        }(),
        _ when linkDot != null => StatusPillVm(
          label: linkDot.$2,
          tone: linkDot.$1,
          mark: linkDot.$1 == Tone.warn ? .ring : .dot,
        ),
        final k when kind == NodeKind.broker => _brokerPill(k),
        final k => _statusPill(k),
      },
      subtitle: sel == null
          ? null
          : _subtitle(sel, kind, detail, pointsAll, kids, flow),
      headerButtons: [
        if (sel != null && kind == NodeKind.device)
          _actionButton(
            sel,
            'ping',
            S.current.ping,
            why: S.current.noPingReason,
          ),
      ],
      openButton: flow == null
          ? null
          : ToolButtonVm(
              id: flow.id,
              label: S.current.editDataflow,
              icon: 'action_edit',
              disabledReason: site.needs('read', sel!) == null
                  ? null
                  : S.current.noReadFlow,
            ),
      tabs: tabs,
      tab: tab,
      children: sel == null || tabs.every((t) => t.id != 'children')
          ? const []
          : [
              for (final k in kids)
                if (!_hidden(kind, k)) _childRow(k),
            ],
      toolbar: sel == null ? const [] : _toolbar(sel),
      selectionBar: checked.length < 2
          ? null
          : SelectionBarVm(
              count: S.current.nSelected(checked.length),
              clear: S.current.clearSelection,
              buttons: [
                ToolButtonVm(
                  id: 'copy_keys',
                  label: S.current.copyKeys,
                  icon: 'ui_copy',
                ),
                ToolButtonVm(
                  id: 'set_poll',
                  label: S.current.setPoll,
                  disabledReason:
                      checked.every((k) => _actionOf(k, 'edit') != null)
                      ? null
                      : S.current.noEditReason,
                ),
                ToolButtonVm(
                  id: 'record',
                  label: S.current.recordInHistory,
                  disabledReason: S.current.noHistoryAction,
                ),
                ToolButtonVm(
                  id: 'remove_checked',
                  label: S.current.removeEllipsis,
                  disabledReason: [
                    for (final k in checked) ?site.needs('config', k),
                  ].firstOrNull,
                ),
              ],
            ),
      checkedCount: checked.length,
      pointFilter: nodes.pointFilter,
      points: [
        for (final p in shown) _pointRow(p),
        if (sel != null) ..._stagedAdds(sel),
      ],
      pointsLoading: sel != null && detail == null && kids.isEmpty,
      pointsEmpty: pointsAll.isEmpty
          ? (_actionOf(sel ?? '', 'add_point') != null
                ? S.current.noPointsYet
                : S.current.noPoints)
          : null,
      emptyButtons: sel == null || _actionOf(sel, 'add_point') == null
          ? const []
          : [
              for (final b in _toolbar(sel))
                if (b.id != 'apply_profile') b,
            ],
      params: [
        if (flow != null) _flowSection(flow, sel),
        ..._nodeSections(sel, detail, kind, withDiagnostics: false),
      ],
      actionGroups: _groups(actions),
      result: _result(),
      range: nodes.historyRange,
      trend: point != null && nodes.historyKey == point ? _trend(point) : null,
      historyRows: [
        if (point != null && nodes.historyKey == point)
          for (final (i, h) in nodes.history.reversed.take(50).indexed)
            RowVm(
              id: '$i',
              cells: [
                CellVm(title: _time(h.time), monospace: true),
                CellVm(
                  title: switch (h.value) {
                    final num n when _choices(point).isNotEmpty => valueText(
                      n,
                      choices: _choices(point),
                    ),
                    _ => h.text,
                  },
                  monospace: true,
                ),
                CellVm(title: h.quality ?? '—', tone: _toneOf(h.quality)),
              ],
            ),
      ],
      historyNote: point == null ? S.current.pickAPoint : null,
      historyFail:
          point != null &&
              nodes.historyKey == point &&
              nodes.historyFailed != null
          ? FailChipVm(
              label: S.current.historyUnavailable,
              tip: S.current.historyUnavailableTip(nodes.historyFailed!),
            )
          : null,
      auditKey: canAudit ? sel : null,
      auditRows: [
        if (sel != null)
          for (final (i, e) in nodes.audit.take(200).indexed)
            RowVm(
              id: '$i',
              cells: [
                CellVm(title: _time(e.time), monospace: true),
                CellVm(title: e.op),
                CellVm(
                  title: e.key.startsWith(sel)
                      ? '…${e.key.substring(sel.length)}'
                      : e.key,
                  monospace: true,
                ),
                CellVm(title: e.who, monospace: true),
                if (e.status == 0)
                  CellVm(title: S.current.auditDone, tone: Tone.good)
                else
                  CellVm(
                    title: S.current.auditRefused(e.status),
                    tone: Tone.bad,
                  ),
              ],
            ),
      ],
      auditNote: !canAudit
          ? S.current.auditNeeds
          : (nodes.audit.isEmpty ? S.current.noAuditHere : null),
      inspector: _inspector(sel, detail, kind, actions, flow),
      copyKeys: [
        if (checked.isNotEmpty)
          ...checked
        else ...[
          ?sel,
          for (final k in nodes.marked)
            if (k != sel) k,
        ],
      ],
      pointValue: point == null
          ? null
          : _value(live.values[point], null, choices: _choices(point)),
      busy: nodes.isWaiting || changes.isWaiting,
      onShow: () {
        dispatchSync(WatchKeysAction(_watch()));
        if (nodes.expanded.isEmpty) {
          unawaited(dispatchAndWait(RetrieveNodesAction()));
        }
        if (links.view.isEmpty) {
          unawaited(dispatchAndWait(RetrieveLinksAction()));
        }
      },
      onHide: (keys) => dispatchSync(UnwatchKeysAction(keys)),
      onSelect: (k) => dispatchSync(SelectNodeAction(k)),
      onToggle: (k) => dispatchSync(ToggleNodeAction(k)),
      onMark: (k) => dispatchSync(MarkNodesAction.toggle(k)),
      onMarkRange: (k) => dispatchSync(
        MarkNodesAction.range(k, [for (final r in _rows()) r.id]),
      ),
      onTreeFilter: (t) => dispatchSync(SetTreeFilterAction(t)),
      onPointFilter: (t) => dispatchSync(SetPointFilterAction(t)),
      onPoint: (k) => dispatchSync(SelectPointAction(k == point ? null : k)),
      onCheck: (k) => dispatchSync(CheckPointsAction.toggle(k)),
      onRange: (k) => dispatchSync(CheckPointsAction.range(k, order)),
      onCheckAll: () => dispatchSync(CheckPointsAction.all(order)),
      onClear: () => dispatchSync(ClearSelectionAction()),
      assistantOpen: assistant.drawer,
      onToggleAssistant: () => dispatchSync(SetDrawerAction.toggle()),
      onTab: (t) {
        dispatchSync(SetTabAction(t));
        if (t == 'history' && point != null) {
          unawaited(dispatchAndWait(RetrieveHistoryAction(point)));
        }
      },
      onAudit: () {
        if (sel != null) {
          unawaited(dispatchAndWait(RetrieveAuditAction(sel)));
        }
      },
      onAction: (a) => dispatchSync(SetActionAction(a)),
      onPickAction: (a) {
        dispatchSync(SetTabAction('actions'));
        dispatchSync(SetActionAction(a));
      },
      onHistoryRange: (r) {
        dispatchSync(SetHistoryRangeAction(r));
        if (point != null) {
          unawaited(dispatchAndWait(RetrieveHistoryAction(point)));
        }
      },
      onTrendWindow: (a, b) {
        final (start, end) = _historyRange();
        dispatchSync(SetHistoryWindowAction(trendWindow(a, b, start, end)));
      },
      onTrendReset: () => dispatchSync(SetHistoryWindowAction(null)),
      onCloseInspector: () => dispatchSync(SetActionAction(null)),
      onSubmit: (values) => _submit(sel, values),
      onReadAgain: (key) => dispatchSync(RetryReadAction(key)),
      onTool: (id) => _onTool(sel, id),
      onSetPoll: (s) {
        for (final k in checked) {
          if (_actionOf(k, 'edit') != null) {
            dispatchSync(StagePointEditAction(k, pollParam, s));
          }
        }
      },
      menuOf: _menuOf,
      panelWidths: WorkspacePanels.explorer.widths(panels.widths),
      onPanelWidth: (side, w) => dispatchSync(
        SetPanelWidthAction(WorkspacePanels.explorer.slot(side), w),
      ),
      onTapFlowEditor: (id) => dispatch(GoAction.push(FlowEditorRoute(id: id))),
      viewer: _pointViewer(),
      onViewPoint: switch (nodes.point) {
        final p? => () => dispatchSync(SetViewedPointAction(p)),
        null => null,
      },
      onCloseViewer: () => dispatchSync(SetViewedPointAction(null)),
    );
  }

  /// The viewer of the point `nodes.viewedPoint`, live (owner request
  /// 2026-11-09): titled by its key under the site, its value whole with
  /// unit and quality.
  ValueViewerVm? _pointViewer() {
    final key = nodes.viewedPoint;
    if (key == null) {
      return null;
    }
    final v = live.values[key];
    final pd = nodes.detail[key];
    final info = nodes.table[key];
    return valueViewerOf(
      title: key.startsWith('$_root/') ? key.substring(_root.length + 1) : key,
      value: v?.value,
      known: v != null,
      unit: pd?.unit ?? info?.unit,
      choices: _choices(key),
      quality: switch (v) {
        null => null,
        _ when !site.connected => QualityMarkVm(
          label: S.current.stale,
          tone: .neutral,
          mark: .dashed,
        ),
        final s => () {
          final q = qualityMarkOf(s.quality);
          return QualityMarkVm(
            label: '${q.label} · ${_time(s.time)}',
            tone: q.tone,
            mark: q.mark,
          );
        }(),
      },
    );
  }

  /// One line under the name: `modbus device · unit 1 · 127.0.0.1:5020 ·
  /// last read 12:00:03`, `dataflow · deployed by admin`, `folder · 3
  /// children`, then the display name (it may be long: the line ends in an
  /// ellipsis and its tooltip holds it all).
  String _subtitle(
    String key,
    NodeKind kind,
    NodeDetail? d,
    List<NodeInfo> points,
    List<NodeInfo> kids,
    FlowSummary? flow,
  ) {
    final parts = key.split('/');
    final link = parts.length > 3 ? parts[3] : null;
    final driver = link == null ? null : links.table[link]?.driver;
    final conn = switch (kind) {
      NodeKind.device => nodes.detail[_parent(key)]?.cfg,
      NodeKind.connection => d?.cfg,
      _ => null,
    };
    DateTime? last;
    for (final p in points) {
      final t = live.values[p.key]?.time;
      if (t != null && (last == null || t.isAfter(last))) {
        last = t;
      }
    }
    final driverKind = switch (kind) {
      NodeKind.device || NodeKind.connection || NodeKind.link => true,
      _ => false,
    };
    return [
      [
        if (driverKind && driver != null && driver.isNotEmpty) driver,
        _kindWord(kind),
      ].join(' '),
      if (flow?.deployedBy case final who?) S.current.deployedByWho(who),
      ?flow?.problem,
      if (kind == NodeKind.device && d?.cfg['unit'] != null)
        S.current.unitNumber(d!.cfg['unit']!),
      if (conn?['host'] case final h?)
        if (conn?['port'] == null) h else '$h:${conn!['port']}',
      ?conn?['serial_port'],
      if (kind == NodeKind.broker) ?d?.attr['root'],
      if (!driverKind && kind != NodeKind.flow && kind != NodeKind.device)
        S.current.childCount(kids.length),
      if (last != null && kind == NodeKind.device)
        S.current.lastRead(_time(last)),
      // Other nodes show their display name as the title.
      if (kind == NodeKind.flow) ?_display(key, d),
    ].join(' · ');
  }

  /// The tabs of [kind]'s frame (docs/design/specs/explorer.md "Frames by
  /// node kind"): a device has its points, a flow its state and actions,
  /// any other node its children.
  static List<TabItemVm> _tabs(
    NodeKind kind,
    int points,
    List<NodeInfo> kids,
    int actions,
  ) => [
    if (kind == NodeKind.device)
      TabItemVm(id: 'points', label: S.current.tabPoints, count: '$points')
    else if (kind != NodeKind.flow)
      TabItemVm(
        id: 'children',
        label: S.current.tabContents,
        count: '${kids.where((k) => !_hidden(kind, k)).length}',
      ),
    TabItemVm(id: 'params', label: S.current.tabParameters),
    TabItemVm(id: 'actions', label: S.current.tabActions, count: '$actions'),
    if (kind != NodeKind.flow)
      TabItemVm(id: 'history', label: S.current.tabHistory),
    TabItemVm(id: 'audit', label: S.current.tabAudit),
  ];

  /// A link's or a connection's diagnostic values are not its contents:
  /// `status` drives the pill, the counters are in the inspector.
  static bool _hidden(NodeKind kind, NodeInfo child) =>
      (kind == NodeKind.connection || kind == NodeKind.link) &&
      isDiagnostic(child);

  /// One row of the Contents tab: the name in mono with the display name
  /// under it, the kind (a value's type), the value.
  RowVm _childRow(NodeInfo k) {
    final value = k.type != null;
    final v = live.values[k.key];
    return RowVm(
      id: k.key,
      selected: k.key == nodes.point,
      cells: [
        CellVm(
          title: k.name,
          subtitle: _display(k.key, nodes.detail[k.key]),
          monospace: true,
        ),
        CellVm(
          title: value
              ? [k.type!, if (k.writable != null) 'RW'].join(' · ')
              : _kindWord(_kind(k.key, nodes.detail[k.key])),
        ),
        CellVm(
          title: !value ? '—' : _value(v, k.unit, choices: _choices(k.key)),
          monospace: true,
        ),
      ],
    );
  }

  /// A broker's `connected` value as its pill.
  StatusPillVm? _brokerPill(String key) =>
      switch (live.values['$key/connected']?.value) {
        true => StatusPillVm(label: S.current.stateConnected, tone: Tone.good),
        false => StatusPillVm(label: S.current.stateOffline, tone: Tone.bad),
        _ => null,
      };

  /// A flow's `~val` as a section: state, version, who deployed it, since
  /// when, the error.
  InspectorSectionVm _flowSection(FlowSummary f, String? key) {
    final (_, word, problem) = flowStateOf(f);
    final since = switch (key == null ? null : live.values[key]?.value) {
      {'since': final int us} => DateTime.fromMicrosecondsSinceEpoch(
        us,
        isUtc: true,
      ),
      _ => null,
    };
    return InspectorSectionVm(
      label: S.current.secState,
      facts: [
        FactVm(label: S.current.colState, value: word),
        FactVm(
          label: S.current.factVersion,
          value: f.version == null ? '—' : 'v${f.version}',
          mono: true,
        ),
        FactVm(
          label: S.current.colDeployedBy,
          value: f.deployedBy ?? '—',
          mono: true,
        ),
        if (since != null)
          FactVm(
            label: S.current.factSince,
            value: '${_date(since)} ${_time(since)}',
            mono: true,
          ),
        if (problem != null)
          FactVm(label: S.current.factProblem, value: problem),
      ],
    );
  }

  static String _date(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }

  /// A header or toolbar button that runs the node's own [action], or is
  /// disabled with [why] when the node has none, or with the level it needs.
  ToolButtonVm _actionButton(
    String key,
    String action,
    String label, {
    required String why,
    String? icon,
    bool quiet = false,
  }) {
    final a = _actionOf(key, action);
    return ToolButtonVm(
      id: action,
      label: label,
      icon: icon,
      quiet: quiet,
      disabledReason: a == null ? why : site.needs(a.level, key),
    );
  }

  List<ToolButtonVm> _toolbar(String key) {
    final import = _actionOf(key, 'import_dsa') != null
        ? 'import_dsa'
        : 'import';
    return [
      _actionButton(
        key,
        'add_point',
        S.current.addPoint,
        icon: 'ui_add',
        why: S.current.noActionReason('add_point'),
      ),
      _actionButton(
        key,
        import,
        S.current.importPoints,
        icon: 'ui_upload',
        quiet: true,
        why: S.current.noActionReason('import'),
      ),
      ToolButtonVm(
        id: 'apply_profile',
        label: S.current.applyProfile,
        icon: 'ui_profile',
        quiet: true,
        disabledReason: S.current.noProfileReason,
      ),
    ];
  }

  void _onTool(String? sel, String id) {
    if (sel == null) {
      return;
    }
    switch (id) {
      case 'remove_checked':
        for (final k in nodes.checked) {
          dispatchSync(StageInvokeAction(k, 'remove', const {}));
        }
        dispatchSync(ClearSelectionAction());
      case 'ping':
        unawaited(dispatchAndWait(InvokeNodeAction(sel, 'ping')));
      default:
        // A node action with a form: Add point, Import.
        dispatchSync(SetActionAction(id));
    }
  }

  PointRowVm _pointRow(NodeInfo p) {
    final v = live.values[p.key];
    final d = nodes.detail[p.key];
    final edit = changes.table[StagePointEditAction.idOf(p.key)];
    final stagedPoll = edit?.args[pollParam];
    final poll = d?.cfg[pollParam];
    final offline = !site.connected;
    final failed = live.failed[p.key];
    return PointRowVm(
      id: p.key,
      name: p.name,
      display: p.display ?? d?.display,
      register: _register(d),
      type: d?.cfg['dtype'] ?? p.type ?? '—',
      unit: switch (p.unit ?? d?.unit ?? d?.cfg['unit']) {
        final u? when u.isNotEmpty => u,
        _ => '—',
      },
      poll: stagedPoll != null ? pollText(stagedPoll) : pollText(poll),
      pollWas: stagedPoll != null && poll != null ? pollText(poll) : null,
      value: v == null || failed != null
          ? '—'
          : valueText(v.value, choices: _choices(p.key)),
      failed: failed == null
          ? null
          : FailChipVm(
              label: S.current.readFailed,
              tip: S.current.readFailedTip(failed),
            ),
      quality: offline
          ? QualityMarkVm(label: S.current.stale, tone: .neutral, mark: .dashed)
          : _quality(v),
      writable: p.writable != null,
      checked: nodes.checked.contains(p.key),
      selected: p.key == nodes.point,
      staged: changes.table.values.any((c) => c.key == p.key),
      stale: offline,
    );
  }

  /// Points staged to be added to [device]: `not applied` until applied.
  List<PointRowVm> _stagedAdds(String device) => [
    for (final c in changes.table.values)
      if (c.key == device && c.action == 'add_point')
        PointRowVm(
          id: c.id,
          name: '${c.args['name'] ?? '—'}',
          register: _register(
            NodeDetail(
              key: '',
              cfg: {for (final e in c.args.entries) e.key: '${e.value}'}.lock,
            ),
          ),
          type: '${c.args['dtype'] ?? '—'}',
          unit: switch (c.args['unit']) {
            final String u when u.isNotEmpty => u,
            _ => '—',
          },
          poll: pollText(c.args[pollParam]),
          quality: QualityMarkVm(
            label: S.current.notApplied,
            tone: .neutral,
            mark: .ring,
          ),
          writable: c.args['writable'] == true,
          staged: true,
        ),
  ];

  QualityMarkVm _quality(LiveValue? v) => switch (v?.quality) {
    null => QualityMarkVm(
      label: S.current.noValue,
      tone: .neutral,
      mark: .ring,
    ),
    Quality.good => const QualityMarkVm(label: 'good', tone: .good),
    Quality.uncertain => const QualityMarkVm(
      label: 'uncertain',
      tone: .warn,
      mark: .ring,
    ),
    Quality.bad => const QualityMarkVm(label: 'bad', tone: .bad),
  };

  static Tone? _toneOf(String? q) => switch (q) {
    'good' => Tone.good,
    'uncertain' => Tone.warn,
    'bad' => Tone.bad,
    _ => null,
  };

  static String _value(
    LiveValue? v,
    String? unit, {
    List<String> choices = const [],
  }) => v == null ? '—' : valueText(v.value, choices: choices, unit: unit);

  /// The point's history range in µs: the span of `nodes.historyRange` up
  /// to when it was read (stable between dispatches).
  (int, int) _historyRange() {
    final span = RetrieveHistoryAction.span(nodes.historyRange);
    final e = trendRangeEnd(nodes.historyAt, [nodes.history.lastOrNull?.time]);
    return (e - span.inMicroseconds, e);
  }

  /// The point's trend (spec trend.md §4): one series of the raw rows read
  /// for the range (≤ 2000), zoomed on them without reading again.
  TrendVm _trend(String point) {
    final (rs, re) = _historyRange();
    final w = nodes.historyWindow;
    final we = w?.end?.microsecondsSinceEpoch ?? re;
    final ws = w == null ? rs : we - w.span.inMicroseconds;
    final span = RetrieveHistoryAction.span(nodes.historyRange);
    final info = nodes.table[point];
    final rows = nodes.history;
    final detail = nodes.detail[point];
    return TrendVm(
      title: info?.display ?? point.split('/').last,
      series: [
        TrendSeriesVm(
          id: point,
          name: point.split('/').last,
          label: info?.display ?? '',
          color: TrendColor.byIndex(0),
          unit: detail?.unit ?? info?.unit ?? '',
          decimals: trendDecimals(rows, precision: detail?.cfg['precision']),
          samples: trendSamples(rows),
          overview: trendSamples(rows),
        ),
      ],
      rangeStart: rs,
      rangeEnd: re,
      windowStart: ws.clamp(rs, re),
      windowEnd: we.clamp(rs, re),
      rollup: rollupText(null),
      minWindow: 12 * stepDuration(stepFor(span, raw: false))!.inMicroseconds,
      endsNow: true,
      following: w?.end == null,
      loading: rows.isEmpty && nodes.historyLoading,
      empty: S.current.noHistory,
      card: false,
      hint: false,
      plotHeight: 180,
      format: trendFormat(),
    );
  }

  static String _time(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  /// The board's word for a modbus `edit` parameter, else its display name.
  static String _label(ParamSpec p) => switch (p.name) {
    'table' => S.current.fieldArea,
    'addr' => S.current.fieldAddress,
    'dtype' => S.current.fieldDataType,
    'unit' => S.current.fieldUnit,
    'scale' => S.current.fieldScale,
    'offset' => S.current.fieldOffset,
    'bit' => S.current.fieldBit,
    'regs' => S.current.fieldRegisters,
    'writable' => S.current.fieldWritable,
    'writable_by_master' => S.current.fieldWritableByMaster,
    _ => labelOf(p.name, display: p.display),
  };

  /// The fields of [key]'s `edit`, each staging its change; the staged
  /// value shows in place of the current one.
  List<ParamFieldVm> _editFields(String key, Iterable<ParamSpec> specs) {
    final staged = changes.table[StagePointEditAction.idOf(key)]?.args;
    return [
      for (final p in specs)
        ParamFieldVm(
          id: '$key/${p.name}',
          label: _label(p),
          code: p.name,
          kind: paramField(p).kind,
          value: staged?[p.name] ?? p.defaultValue,
          choices: p.choices.unlock,
          choiceLabels: choiceLabels(p.choices),
          description: p.description,
          onChanged: (v) => dispatchSync(StagePointEditAction(key, p.name, v)),
        ),
    ];
  }

  /// A field the board shows that the driver has no parameter for.
  static ParamFieldVm _missing(String id, String label, {Object? value}) =>
      ParamFieldVm(
        id: id,
        label: label,
        kind: .text,
        value: value,
        enabled: false,
        description: value == null
            ? S.current.noParamReason(label.toLowerCase())
            : S.current.wordOrderReason,
        onChanged: (_) {},
      );

  /// The word order a modbus data type's suffix sets.
  static String _wordOrder(String? dtype) => switch (dtype) {
    final d? when d.endsWith('_wbswap') => 'DCBA',
    final d? when d.endsWith('_wswap') => 'CDAB',
    final d? when d.endsWith('_bswap') => 'BADC',
    _ => 'ABCD',
  };

  List<InspectorSectionVm> _pointSections(String key, NodeDetail? d) {
    final edit = _actionOf(key, 'edit');
    final v = live.values[key];
    final info = nodes.table[key];
    final type = d?.type ?? info?.type;
    final unit = d?.unit ?? info?.unit;
    final writable = d?.writable ?? info?.writable;
    final publish = InspectorSectionVm(
      label: S.current.secPublish,
      code: [
        (
          '~meta',
          '{type: ${type ?? '—'}${unit == null ? '' : ', unit: $unit'}, '
              'writable: ${writable != null}}',
        ),
        (
          '~val',
          v == null
              ? '—'
              : '{v: ${valueText(v.value, choices: _choices(key))}, '
                    'q: ${v.quality.name}, t: ${_time(v.time)}}',
        ),
      ],
    );
    if (edit == null) {
      return [
        InspectorSectionVm(
          label: S.current.secValue,
          facts: [
            FactVm(label: S.current.colType, value: type ?? '—', mono: true),
            FactVm(label: S.current.colUnit, value: unit ?? '—'),
            FactVm(label: S.current.colWrite, value: writable ?? 'R'),
          ],
          text: S.current.noEditReason,
        ),
        publish,
      ];
    }
    final staged = changes.table[StagePointEditAction.idOf(key)]?.args;
    final specs = edit.params;
    final poll = specs.where((p) => p.name == pollParam).firstOrNull;
    final register = [
      for (final p in specs)
        if (p.name != pollParam &&
            !_valueParams.contains(p.name) &&
            !_writeParams.contains(p.name))
          p,
    ];
    final dtype = '${staged?['dtype'] ?? d?.cfg['dtype'] ?? ''}';
    final registerFields = _editFields(key, register);
    if (specs.any((p) => p.name == 'dtype')) {
      registerFields.insert(
        registerFields.indexWhere((f) => f.id == '$key/dtype') + 1,
        _missing(
          '$key/word_order',
          S.current.fieldWordOrder,
          value: _wordOrder(dtype),
        ),
      );
    }
    final pollNow = staged?[pollParam] ?? poll?.defaultValue;
    final pollWas = poll?.defaultValue;
    final pollIndex = _polls.indexWhere(
      (s) => pollText(s) == pollText(pollNow),
    );
    final pollStaged =
        (staged?.containsKey(pollParam) ?? false) &&
        pollText(pollNow) != pollText(pollWas);
    return [
      InspectorSectionVm(label: S.current.secRegister, fields: registerFields),
      InspectorSectionVm(
        label: S.current.secValue,
        columns: 3,
        fields: [
          ..._editFields(
            key,
            specs.where((p) => p.name == 'unit' || p.name == 'scale'),
          ),
          if (!specs.any((p) => p.name == 'precision'))
            _missing('$key/precision', S.current.fieldPrecision),
          ..._editFields(
            key,
            specs.where(
              (p) =>
                  _valueParams.contains(p.name) &&
                  p.name != 'unit' &&
                  p.name != 'scale',
            ),
          ),
        ],
      ),
      if (poll != null)
        InspectorSectionVm(
          label: S.current.secPolling,
          note: pollStaged ? S.current.stagedWas(pollText(pollWas)) : null,
          segments: [for (final s in _polls) pollText(s)],
          segment: pollIndex < 0 ? null : pollIndex,
          onSegment: (i) =>
              dispatchSync(StagePointEditAction(key, pollParam, _polls[i])),
        ),
      InspectorSectionVm(
        label: S.current.secWrite,
        fields: [
          for (final f in _editFields(
            key,
            specs.where((p) => _writeParams.contains(p.name)),
          ))
            if (f.kind == .toggle)
              ParamFieldVm(
                id: f.id,
                label: f.label,
                code: f.code,
                kind: f.kind,
                value: f.value,
                description: S.current.writableNeeds(edit.level),
                onChanged: f.onChanged,
              )
            else
              f,
        ],
      ),
      publish,
    ];
  }

  /// The node on screen as the inspector and the Parameters tab show it:
  /// its `edit` parameters as a form, its attributes, its diagnostics.
  List<InspectorSectionVm> _nodeSections(
    String? sel,
    NodeDetail? d,
    NodeKind kind, {
    required bool withDiagnostics,
  }) {
    if (sel == null) {
      return const [];
    }
    final edit = _actionOf(sel, 'edit');
    final diag = [
      for (final n in _children(sel))
        if (isDiagnostic(n) && n.name != 'status') n,
    ];
    final noParams = edit == null && (d?.cfg.isEmpty ?? true);
    return [
      if (!noParams || kind == NodeKind.device)
        InspectorSectionVm(
          label: S.current.secParameters,
          fields: edit == null ? const [] : _editFields(sel, edit.params),
          facts: edit != null
              ? const []
              : [
                  for (final e
                      in d?.cfg.entries ?? const <MapEntry<String, String>>[])
                    FactVm(
                      label: humanize(e.key),
                      code: e.key,
                      value: e.value,
                      mono: true,
                    ),
                ],
          text: edit == null && (d?.cfg.isEmpty ?? true)
              ? S.current.noActionReason('edit')
              : null,
        ),
      if (d != null && d.attr.isNotEmpty)
        InspectorSectionVm(
          label: S.current.secAttributes,
          facts: [
            for (final e in d.attr.entries)
              FactVm(label: e.key, value: e.value, mono: true),
          ],
        ),
      if (withDiagnostics && diag.isNotEmpty)
        InspectorSectionVm(
          label: S.current.secDiagnostics,
          facts: [
            for (final n in diag)
              FactVm(
                label: labelOf(n.name, display: n.display),
                code: n.name,
                value: _value(live.values[n.key], n.unit),
                mono: true,
              ),
          ],
        ),
    ];
  }

  List<ActionCardGroupVm> _groups(Iterable<ActionInfo> actions) {
    final sel = nodes.selectedNode ?? '';
    final staged = actions.where((a) => a.level == 'config').toList();
    final now = actions.where((a) => a.level != 'config').toList();
    ActionCardVm card(ActionInfo a) => ActionCardVm(
      id: a.name,
      title: labelOf(a.name, display: a.display),
      level: a.level,
      detail: [
        // The action's own name stays in reach (owner 2026-11-11).
        a.name,
        S.current.paramCount(a.params.length),
        if (a.result case final r?) S.current.returns(r),
      ].join(' · '),
      selected: nodes.action == a.name,
      disabledReason: site.needs(a.level, sel),
    );
    return [
      if (staged.isNotEmpty)
        ActionCardGroupVm(
          label: S.current.configureStaged,
          note: S.current.configureStagedNote,
          cards: [for (final a in staged) card(a)],
        ),
      if (now.isNotEmpty)
        ActionCardGroupVm(
          label: S.current.operateRunsNow,
          note: S.current.operateRunsNowNote,
          cards: [for (final a in now) card(a)],
        ),
    ];
  }

  /// The node menu of [key] (§5): groups from the action `group`, else
  /// Configure · staged and Operate · runs now, in `~meta.actions` order.
  Future<NodeMenuVm?> _menuOf(String key) async {
    NodeDetail? d;
    for (var i = 0; i < 20; i++) {
      d = state.nodes.detail[key];
      if (d != null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (d == null) {
      return null;
    }
    final groups = <String, List<NodeMenuItemVm>>{};
    for (final a in d.actions) {
      final g =
          a.group ??
          (a.level == 'config'
              ? S.current.configureStaged
              : S.current.operateRunsNow);
      (groups[g] ??= []).add(
        NodeMenuItemVm(
          id: a.name,
          label:
              '${labelOf(a.name, display: a.display)}'
              '${a.params.isEmpty ? '' : '…'}',
          code: a.name,
          level: a.level,
          danger: a.name.startsWith('remove') || a.name.startsWith('delete'),
          disabledReason: site.needs(a.level, key),
        ),
      );
    }
    final kind = _kind(key, d);
    final driver = key.split('/').length > 3
        ? links.table[key.split('/')[3]]?.driver
        : null;
    return NodeMenuVm(
      title: key.split('/').last,
      subtitle: S.current.menuSubtitle(
        [
          if (driver != null && driver.isNotEmpty) driver,
          _kindWord(kind),
        ].join(' '),
        d.actions.length,
      ),
      groups: [
        for (final e in groups.entries)
          NodeMenuGroupVm(label: e.key, items: e.value),
      ],
      copyLabel: S.current.copyKey,
    );
  }

  ResultVm? _result() {
    final sel = nodes.selectedNode;
    final a = nodes.action;
    if (sel == null || a == null) {
      return null;
    }
    final lines = nodes.results[InvokeNodeAction.resultId(sel, a)];
    if (lines == null) {
      return null;
    }
    final rows = <Map<String, Object?>>[];
    for (final l in lines) {
      final v = jsonDecode(l);
      switch (v) {
        case final List<Object?> list:
          rows.addAll(list.whereType<Map<String, Object?>>());
        case final Map<String, Object?> m:
          rows.add(m);
      }
    }
    final cols = {for (final r in rows) ...r.keys}.take(6).toList();
    return ResultVm(
      title: S.current.resultOf(
        labelOf(a, display: _actionOf(sel, a)?.display),
      ),
      status: S.current.rowsAnswered(rows.isEmpty ? lines.length : rows.length),
      columns: [for (final c in cols) ColumnVm(humanize(c))],
      rows: rows.length == lines.length || rows.length > 1
          ? [
              for (final (i, r) in rows.take(200).indexed)
                RowVm(
                  id: '$i',
                  cells: [
                    for (final c in cols)
                      CellVm(title: '${r[c] ?? ''}', monospace: true),
                  ],
                ),
            ]
          : const [],
      lines: [for (final l in lines) ...l.split('\n')],
    );
  }

  ExplorerInspectorVm? _inspector(
    String? sel,
    NodeDetail? d,
    NodeKind kind,
    Iterable<ActionInfo> actions,
    FlowSummary? flow,
  ) {
    if (sel == null) {
      return null;
    }
    final a = nodes.action;
    if (a != null) {
      final act = actions.where((x) => x.name == a).firstOrNull;
      if (act != null) {
        final stage = act.level == 'config';
        return ActionInspectorVm(
          id: '$sel ▸ ${act.name}',
          eyebrow: S.current.insAction,
          title: labelOf(act.name, display: act.display),
          keyName: '…/${sel.split('/').last}/~act/${act.name}',
          tags: [
            if (stage) S.current.tagStaged else S.current.tagRunsNow,
            S.current.tagNeeds(act.level),
            if (act.result case final r?) S.current.returns(r),
          ],
          fields: paramFields(act.params),
          submit: stage ? S.current.stage : S.current.runNow,
          note: stage
              ? S.current.stagedActionNote
              : S.current.runNowNote(site.user ?? ''),
          cliLabel: S.current.sameCallCli,
          cli: [
            'wyr invoke $sel ${act.name}',
            for (final p in act.params) '${p.name}=…',
          ].join(' '),
          disabledReason: site.needs(act.level, sel),
        );
      }
    }
    final point = nodes.point;
    if (point != null) {
      final pd = nodes.detail[point];
      final info = nodes.table[point];
      final v = live.values[point];
      final writable = pd?.writable ?? info?.writable;
      final choices = _choices(point);
      final type = pd?.type ?? info?.type;
      return PointInspectorVm(
        eyebrow: S.current.insPoint,
        name: point.split('/').last,
        display: pd?.display ?? info?.display,
        // No value is shown beside the mark: the one held is from before
        // the read failed.
        value: live.failed[point] != null
            ? '—'
            : _value(v, pd?.unit ?? info?.unit, choices: choices),
        fail: _readFail(point),
        quality: switch (_quality(v)) {
          _ when !site.connected => QualityMarkVm(
            label: S.current.stale,
            tone: .neutral,
            mark: .dashed,
          ),
          final q when v != null => QualityMarkVm(
            label: '${q.label} · ${_time(v.time)}',
            tone: q.tone,
            mark: q.mark,
          ),
          final q => q,
        },
        sections: _pointSections(point, pd),
        editLabel: S.current.setValue,
        stageLabel: S.current.stage,
        edit: writable == null
            ? null
            : ParamFieldVm(
                id: 'value',
                label: S.current.newValue,
                kind: switch (type) {
                  'bool' => ParamKind.toggle,
                  'number' => ParamKind.number,
                  _ when choices.isNotEmpty => ParamKind.choice,
                  _ => ParamKind.text,
                },
                value: switch (v?.value) {
                  // An enum is edited by its name and staged as its index.
                  final int i when choices.isNotEmpty =>
                    i >= 0 && i < choices.length ? choices[i] : null,
                  final Object x when x is num || x is bool || x is String => x,
                  _ => null,
                },
                choices: choices,
                choiceLabels: choiceLabels(choices),
                onChanged: (_) {},
              ),
        readOnlyReason: writable == null ? null : site.needs(writable, point),
      );
    }
    // A flow's display name is its description, not a title.
    final shown = kind == NodeKind.flow ? null : _display(sel, d);
    return NodeInspectorVm(
      eyebrow: switch (kind) {
        NodeKind.device => S.current.insDevice,
        NodeKind.connection => S.current.insConnection,
        NodeKind.link => S.current.insLink,
        NodeKind.flow => S.current.dataflow,
        NodeKind.storage => S.current.insStorage,
        NodeKind.broker => S.current.insBroker,
        NodeKind.folder => S.current.insFolder,
      },
      title: shown ?? sel.split('/').last,
      name: shown == null ? null : sel.split('/').last,
      fail: _readFail(sel),
      sections: [
        if (flow != null) _flowSection(flow, sel),
        ..._nodeSections(sel, d, kind, withDiagnostics: true),
      ],
    );
  }

  Future<FieldRefusal?> _submit(
    String? sel,
    Map<String, Object?> values,
  ) async {
    if (sel == null) {
      return null;
    }
    final a = nodes.action;
    final act = a == null ? null : _actionOf(sel, a);
    if (act != null) {
      final args = plainArgs(values);
      if (act.level == 'config') {
        dispatchSync(
          StageInvokeAction(
            sel,
            act.name,
            args,
            display: labelOf(act.name, display: act.display),
            keepEmpty: clearedNames(act.params),
          ),
        );
        return null;
      }
      // Refused as wrong input: the form keeps its values and marks the
      // field (docs/design/specs/errors.md §3, *Back to the form*).
      return sendForm(
        dispatchAndWait(
          InvokeNodeAction(sel, act.name, args, clearedNames(act.params)),
        ),
      );
    }
    final point = nodes.point;
    if (point != null && values.containsKey('value')) {
      final choices = _choices(point);
      final value = values['value'];
      dispatchSync(
        StageValueAction(
          point,
          value is String && choices.contains(value)
              ? choices.indexOf(value)
              : value,
          from: _value(live.values[point], null, choices: choices),
        ),
      );
    }
    return null;
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.assistantOpen,
    required this.onToggleAssistant,
    required this.treeLabel,
    required this.tree,
    required this.treeLoading,
    required this.treeFilter,
    required this.watch,
    required this.keyName,
    required this.keyLinks,
    required this.titleName,
    required this.title,
    required this.pill,
    required this.subtitle,
    required this.headerButtons,
    required this.openButton,
    required this.tabs,
    required this.tab,
    required this.toolbar,
    required this.selectionBar,
    required this.checkedCount,
    required this.pointFilter,
    required this.points,
    required this.pointsLoading,
    required this.pointsEmpty,
    required this.emptyButtons,
    required this.children,
    required this.params,
    required this.actionGroups,
    required this.result,
    required this.range,
    required this.trend,
    required this.onTrendWindow,
    required this.onTrendReset,
    required this.historyRows,
    required this.historyNote,
    required this.historyFail,
    required this.auditKey,
    required this.auditRows,
    required this.auditNote,
    required this.inspector,
    required this.copyKeys,
    required this.pointValue,
    required this.busy,
    required this.onShow,
    required this.onHide,
    required this.onSelect,
    required this.onToggle,
    required this.onMark,
    required this.onMarkRange,
    required this.onTreeFilter,
    required this.onPointFilter,
    required this.onPoint,
    required this.onCheck,
    required this.onRange,
    required this.onCheckAll,
    required this.onClear,
    required this.onTab,
    required this.onAudit,
    required this.onAction,
    required this.onPickAction,
    required this.onHistoryRange,
    required this.onCloseInspector,
    required this.onSubmit,
    required this.onReadAgain,
    required this.onTool,
    required this.onSetPoll,
    required this.menuOf,
    required this.panelWidths,
    required this.onPanelWidth,
    required this.onTapFlowEditor,
    required this.viewer,
    required this.onViewPoint,
    required this.onCloseViewer,
  }) : super(
         equals: [
           assistantOpen,
           treeLabel,
           tree,
           treeLoading,
           treeFilter,
           watch,
           keyName,
           keyLinks,
           titleName,
           title,
           pill,
           subtitle,
           headerButtons,
           openButton,
           tabs,
           tab,
           toolbar,
           selectionBar,
           checkedCount,
           pointFilter,
           points,
           pointsLoading,
           pointsEmpty,
           emptyButtons,
           children,
           params,
           actionGroups,
           result,
           range,
           trend,
           historyRows,
           historyNote,
           historyFail,
           auditKey,
           auditRows,
           auditNote,
           inspector,
           copyKeys,
           pointValue,
           busy,
           panelWidths,
           viewer,
           onViewPoint != null,
         ],
       );

  final String treeLabel;
  final List<TreeRowVm> tree;
  final bool treeLoading;
  final String treeFilter;
  final List<String> watch;
  final String? keyName;
  final Set<String> keyLinks;
  final String? titleName;
  final String? title;
  final StatusPillVm? pill;
  final String? subtitle;
  final List<ToolButtonVm> headerButtons;

  /// A flow's Edit dataflow; its id is the flow's.
  final ToolButtonVm? openButton;
  final List<TabItemVm> tabs;
  final String tab;
  final List<ToolButtonVm> toolbar;
  final SelectionBarVm? selectionBar;
  final int checkedCount;
  final String pointFilter;
  final List<PointRowVm> points;
  final bool pointsLoading;
  final String? pointsEmpty;
  final List<ToolButtonVm> emptyButtons;

  /// The Contents tab of a node that is not a device or a flow.
  final List<RowVm> children;
  final List<InspectorSectionVm> params;
  final List<ActionCardGroupVm> actionGroups;
  final ResultVm? result;
  final String range;
  final TrendVm? trend;
  final void Function(int start, int end) onTrendWindow;
  final VoidCallback onTrendReset;
  final List<RowVm> historyRows;
  final String? historyNote;
  final FailChipVm? historyFail;

  /// The node whose audit the Audit tab reads; null without the rights.
  final String? auditKey;
  final List<RowVm> auditRows;
  final String? auditNote;
  final ExplorerInspectorVm? inspector;

  /// What Copy keys and ⌘⇧C copy: the checked rows, else the node on
  /// screen and the tree rows marked.
  final List<String> copyKeys;

  /// What ⌘C copies: the value of the point in the inspector.
  final String? pointValue;
  final bool busy;
  final VoidCallback onShow;
  final void Function(List<String> keys) onHide;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onMark;
  final ValueChanged<String> onMarkRange;
  final ValueChanged<String> onTreeFilter;
  final ValueChanged<String> onPointFilter;
  final ValueChanged<String> onPoint;
  final ValueChanged<String> onCheck;
  final ValueChanged<String> onRange;
  final VoidCallback onCheckAll;
  final VoidCallback onClear;

  /// The Assistant drawer is open over the page (⌘J).
  final bool assistantOpen;
  final VoidCallback onToggleAssistant;
  final ValueChanged<String> onTab;
  final VoidCallback onAudit;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onPickAction;
  final ValueChanged<String> onHistoryRange;
  final VoidCallback onCloseInspector;
  final FutureOr<FieldRefusal?> Function(Map<String, Object?> values) onSubmit;
  final ValueChanged<String> onReadAgain;
  final ValueChanged<String> onTool;
  final ValueChanged<double> onSetPoll;
  final Future<NodeMenuVm?> Function(String key) menuOf;
  final SidePanelWidths panelWidths;
  final void Function(PanelSide side, double width) onPanelWidth;

  /// The open viewer of a point (`nodes.viewedPoint`), live.
  final ValueViewerVm? viewer;
  final VoidCallback? onViewPoint;
  final VoidCallback onCloseViewer;

  /// Opens the flow editor on a flow id.
  final void Function(String) onTapFlowEditor;
}
