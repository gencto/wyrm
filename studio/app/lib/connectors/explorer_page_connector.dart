import 'dart:async';
import 'dart:convert';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/retrieve_history_action.dart';
import 'package:business/redux/nodes/actions/retrieve_nodes_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/set_action_action.dart';
import 'package:business/redux/nodes/actions/set_history_range_action.dart';
import 'package:business/redux/nodes/actions/set_tab_action.dart';
import 'package:business/redux/nodes/actions/stage_invoke_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:business/redux/nodes/actions/toggle_node_action.dart';
import 'package:business/wyrm/mappers/link_info_mapper.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:models/action_info.dart';
import 'package:models/link_mode.dart';
import 'package:models/live_value.dart';
import 'package:models/node_info.dart';
import 'package:models/quality.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/charts/trend_chart.dart';
import 'package:ui/containers/action_card.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/indicators/quality_mark.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/explorer_page.dart';
import 'package:ui/tables/row_table.dart';
import 'package:ui/trees/tree_row.dart';

import '../common/forms.dart';
import '../common/tab_visibility.dart';

/// The sections of a site the tree starts from (`sys/**` is not in the
/// tree: it is in Links, Access, Sites and System, docs/studio.md §7.4).
const _sections = ['downstream', 'dataflows', 'storage', 'upstream'];

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
      child: ExplorerPage(
        treeLabel: vm.treeLabel,
        tree: vm.tree,
        treeNote: S.current.treeNote,
        onTap: vm.onSelect,
        onToggle: vm.onToggle,
        onMenu: (id, at) => vm.onMenu(context, id, at),
        keyName: vm.keyName,
        title: vm.title,
        pill: vm.pill,
        empty: S.current.selectANode,
        tabs: vm.tabs,
        tab: vm.tab,
        onTab: vm.onTab,
        pointColumns: [
          ColumnVm(S.current.colPoint, flex: 3),
          ColumnVm(S.current.colType, flex: 2),
          ColumnVm(S.current.colValue, flex: 3),
          ColumnVm(S.current.colQuality, flex: 2),
          ColumnVm(S.current.colTime, flex: 2),
          ColumnVm(S.current.colWrite),
        ],
        points: vm.points,
        pointsEmpty: S.current.noPoints,
        pointsNote: S.current.pointsNote,
        onPoint: vm.onSelect,
        params: vm.params,
        paramsNote: S.current.paramsNote,
        actionGroups: vm.actionGroups,
        onAction: vm.onAction,
        result: vm.result,
        ranges: const [
          TabItemVm(id: '1h', label: '1 h'),
          TabItemVm(id: '24h', label: '24 h'),
          TabItemVm(id: '7d', label: '7 d'),
        ],
        range: vm.range,
        onRange: vm.onRange,
        trend: vm.trend,
        trendLabels: vm.trendLabels,
        trendEmpty: S.current.noHistory,
        historyColumns: [
          ColumnVm(S.current.colTime, flex: 2),
          ColumnVm(S.current.colValue, flex: 3),
          ColumnVm(S.current.colQuality, flex: 2),
        ],
        historyRows: vm.historyRows,
        inspector: vm.inspector,
        busy: vm.busy,
        onSubmit: vm.onSubmit,
        onCloseInspector: vm.onCloseInspector,
      ),
    ),
  );

  static bool _sameKeys(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);
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

  List<TreeRowVm> _rows() {
    final out = <TreeRowVm>[];
    final selected = nodes.selectedNode;
    void walk(
      String key,
      String name,
      int depth, {
      NodeInfo? info,
      bool section = false,
    }) {
      final open = nodes.expanded.contains(key);
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
          chip: _chip(key),
          dot: dot?.$1,
          dotLabel: dot?.$2,
          meta: open && kids.isNotEmpty ? '${kids.length}' : null,
          hasHistory: info?.hasHistory ?? false,
          staged: changes.table.values.any((c) => c.key == key),
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
      if (sel != null && nodes.table[sel]?.type != null) sel,
    ];
  }

  @override
  _Vm fromStore() {
    final sel = nodes.selectedNode;
    final info = sel == null ? null : nodes.table[sel];
    final detail = sel == null ? null : nodes.detail[sel];
    final isPoint = info?.type != null || detail?.type != null;
    final pointsHere = sel == null
        ? const <NodeInfo>[]
        : _children(sel).where((n) => n.type != null).toList();
    final actions = detail?.actions.unlock ?? const <ActionInfo>[];
    final tab = nodes.tab;
    final dot = sel == null ? null : _linkDot(sel);
    final histChoices = sel == null ? const <String>[] : _choices(sel);
    return _Vm(
      treeLabel: S.current.treeOf(site.viewed ?? ''),
      tree: _rows(),
      watch: _watch(),
      keyName: sel,
      title: sel == null
          ? null
          : (detail?.display ?? info?.display ?? sel.split('/').last),
      pill: dot == null
          ? null
          : StatusPillVm(
              label: dot.$2,
              tone: dot.$1,
              mark: dot.$1 == Tone.warn ? .ring : .dot,
            ),
      tabs: [
        TabItemVm(
          id: 'points',
          label: S.current.tabPoints,
          count: '${pointsHere.length}',
        ),
        TabItemVm(id: 'params', label: S.current.tabParameters),
        TabItemVm(
          id: 'actions',
          label: S.current.tabActions,
          count: '${actions.length}',
        ),
        TabItemVm(id: 'history', label: S.current.tabHistory),
      ],
      tab: tab,
      points: [
        for (final p in [if (isPoint && info != null) info, ...pointsHere])
          _pointRow(p, selected: p.key == sel),
      ],
      params: [
        if (detail != null) ...[
          if (detail.profile case final p?)
            FactVm(label: 'is', value: p, mono: true),
          if (detail.type case final t?)
            FactVm(label: 'type', value: t, mono: true),
          if (detail.unit case final u?) FactVm(label: 'unit', value: u),
          if (detail.writable case final w?)
            FactVm(label: 'writable', value: w, mono: true),
          if (detail.invokable case final i?)
            FactVm(label: 'invokable', value: i, mono: true),
          if (detail.choices.isNotEmpty)
            FactVm(label: 'enum', value: detail.choices.join(', '), mono: true),
          if (detail.rev case final r?)
            FactVm(label: 'rev', value: '$r', mono: true),
          for (final e in detail.cfg.entries)
            FactVm(label: 'cfg.${e.key}', value: e.value, mono: true),
          for (final e in detail.attr.entries)
            FactVm(label: 'attr.${e.key}', value: e.value, mono: true),
        ],
      ],
      actionGroups: _groups(actions),
      result: _result(),
      range: nodes.historyRange,
      trend: [
        if (nodes.historyKey == sel)
          TrendSeriesVm(
            label: sel ?? '',
            points: [
              for (final h in nodes.history)
                if (h.value case final v?)
                  (h.time.millisecondsSinceEpoch, v.toDouble()),
            ],
          ),
      ],
      trendLabels: nodes.history.isEmpty
          ? ('', '')
          : (_time(nodes.history.first.time), _time(nodes.history.last.time)),
      historyRows: [
        if (nodes.historyKey == sel)
          for (final (i, h) in nodes.history.reversed.take(50).indexed)
            RowVm(
              id: '$i',
              cells: [
                CellVm(title: _time(h.time), monospace: true),
                CellVm(
                  title: switch (h.value) {
                    final num n when histChoices.isNotEmpty => valueText(
                      n,
                      choices: histChoices,
                    ),
                    _ => h.text,
                  },
                  monospace: true,
                ),
                CellVm(title: h.quality ?? '—', tone: _toneOf(h.quality)),
              ],
            ),
      ],
      inspector: _inspector(sel, info, isPoint, actions),
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
      onTab: (t) {
        dispatchSync(SetTabAction(t));
        if (t == 'history' && sel != null) {
          unawaited(dispatchAndWait(RetrieveHistoryAction(sel)));
        }
      },
      onAction: (a) => dispatchSync(SetActionAction(a)),
      onRange: (r) {
        dispatchSync(SetHistoryRangeAction(r));
        if (sel != null) {
          unawaited(dispatchAndWait(RetrieveHistoryAction(sel)));
        }
      },
      onCloseInspector: () => dispatchSync(SetActionAction(null)),
      onSubmit: (values) => _submit(sel, values),
      onMenu: _menu,
    );
  }

  /// The enum names of [key]: a list carries none, the full meta does.
  List<String> _choices(String key) {
    final d = nodes.detail[key]?.choices;
    if (d != null && d.isNotEmpty) {
      return d.unlock;
    }
    return nodes.table[key]?.choices.unlock ?? const [];
  }

  RowVm _pointRow(NodeInfo p, {required bool selected}) {
    final v = live.values[p.key];
    final staged = changes.table['set:${p.key}'];
    final choices = _choices(p.key);
    return RowVm(
      id: p.key,
      selected: selected,
      cells: [
        CellVm(title: p.name, subtitle: p.display, strong: true),
        CellVm(title: p.type ?? '—', monospace: true),
        CellVm(
          title: staged != null
              ? '${staged.to} ●'
              : _value(v, p.unit, choices: choices),
          subtitle: staged != null
              ? S.current.wasValue(_value(v, p.unit, choices: choices))
              : null,
          monospace: true,
        ),
        _qualityCell(v),
        CellVm(title: v == null ? '—' : _time(v.time), monospace: true),
        CellVm(title: p.writable == null ? 'R' : 'RW'),
      ],
    );
  }

  CellVm _qualityCell(LiveValue? v) => switch (v?.quality) {
    null => CellVm(title: S.current.noValue, tone: Tone.neutral, mark: .ring),
    Quality.good => const CellVm(title: 'good', tone: Tone.good),
    Quality.uncertain => const CellVm(
      title: 'uncertain',
      tone: Tone.warn,
      mark: .ring,
    ),
    Quality.bad => const CellVm(title: 'bad', tone: Tone.bad),
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

  static String _time(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  List<ActionCardGroupVm> _groups(Iterable<ActionInfo> actions) {
    final sel = nodes.selectedNode ?? '';
    final staged = actions.where((a) => a.level == 'config').toList();
    final now = actions.where((a) => a.level != 'config').toList();
    ActionCardVm card(ActionInfo a) => ActionCardVm(
      id: a.name,
      title: a.display ?? a.name,
      level: a.level,
      detail: [
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
      title: S.current.resultOf(a),
      status: S.current.rowsAnswered(rows.isEmpty ? lines.length : rows.length),
      columns: [for (final c in cols) ColumnVm(c)],
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
    NodeInfo? info,
    bool isPoint,
    Iterable<ActionInfo> actions,
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
          title: act.display ?? act.name,
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
    final d = nodes.detail[sel];
    if (isPoint) {
      final v = live.values[sel];
      final writable = d?.writable ?? info?.writable;
      final choices = _choices(sel);
      final type = d?.type ?? info?.type;
      return PointInspectorVm(
        name: sel.split('/').last,
        display: d?.display ?? info?.display,
        value: _value(v, d?.unit ?? info?.unit, choices: choices),
        quality: switch (v?.quality) {
          Quality.good => QualityMarkVm(
            label: 'good · ${_time(v!.time)}',
            tone: Tone.good,
          ),
          Quality.uncertain => QualityMarkVm(
            label: 'uncertain · ${_time(v!.time)}',
            tone: Tone.warn,
            mark: .ring,
          ),
          Quality.bad => QualityMarkVm(
            label: 'bad · ${_time(v!.time)}',
            tone: Tone.bad,
          ),
          null => QualityMarkVm(
            label: S.current.noValue,
            tone: Tone.neutral,
            mark: .ring,
          ),
        },
        facts: [
          FactVm(label: 'type', value: type ?? '—', mono: true),
          if (d?.unit ?? info?.unit case final u?)
            FactVm(label: 'unit', value: u),
          FactVm(label: 'writable', value: writable ?? 'no', mono: true),
          if (d?.profile ?? info?.profile case final p?)
            FactVm(label: 'is', value: p, mono: true),
          FactVm(
            label: S.current.factHistory,
            value: (d?.hasHistory ?? info?.hasHistory ?? false)
                ? S.current.recorded
                : S.current.notRecorded,
          ),
        ],
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
                onChanged: (_) {},
              ),
        readOnlyReason: writable == null
            ? S.current.notWritable
            : site.needs(writable, sel),
      );
    }
    return NodeInspectorVm(
      title: d?.display ?? info?.display ?? sel.split('/').last,
      facts: [
        FactVm(label: 'key', value: sel, mono: true),
        if (d?.profile ?? info?.profile case final p?)
          FactVm(label: 'is', value: p, mono: true),
        FactVm(label: S.current.tabActions, value: '${actions.length}'),
      ],
      cfg: [
        for (final e in d?.cfg.entries ?? const <MapEntry<String, String>>[])
          FactVm(label: e.key, value: e.value, mono: true),
      ],
      attr: [
        for (final e in d?.attr.entries ?? const <MapEntry<String, String>>[])
          FactVm(label: e.key, value: e.value, mono: true),
      ],
    );
  }

  Future<void> _submit(String? sel, Map<String, Object?> values) async {
    if (sel == null) {
      return;
    }
    final a = nodes.action;
    final act = a == null
        ? null
        : nodes.detail[sel]?.actions.where((x) => x.name == a).firstOrNull;
    if (act != null) {
      final args = plainArgs(values);
      if (act.level == 'config') {
        dispatchSync(
          StageInvokeAction(sel, act.name, args, display: act.display),
        );
      } else {
        await dispatchAndWait(InvokeNodeAction(sel, act.name, args));
      }
      return;
    }
    if (values.containsKey('value')) {
      final choices = _choices(sel);
      final value = values['value'];
      dispatchSync(
        StageValueAction(
          sel,
          value is String && choices.contains(value)
              ? choices.indexOf(value)
              : value,
          from: _value(live.values[sel], null, choices: choices),
        ),
      );
    }
  }

  Future<void> _menu(BuildContext context, String id, Offset at) async {
    dispatchSync(SelectNodeAction(id));
    final d = await _detailWhenRead(id);
    if (!context.mounted || d == null || d.isEmpty) {
      return;
    }
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        for (final a in d)
          PopupMenuItem(
            value: a.name,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${a.display ?? a.name}${a.params.isEmpty ? '' : '…'}',
                  ),
                ),
                Text(a.level, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
    );
    if (picked != null) {
      dispatchSync(SetTabAction('actions'));
      dispatchSync(SetActionAction(picked));
    }
  }

  Future<List<ActionInfo>?> _detailWhenRead(String id) async {
    for (var i = 0; i < 20; i++) {
      final d = state.nodes.detail[id];
      if (d != null) {
        return d.actions.unlock;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.treeLabel,
    required this.tree,
    required this.watch,
    required this.keyName,
    required this.title,
    required this.pill,
    required this.tabs,
    required this.tab,
    required this.points,
    required this.params,
    required this.actionGroups,
    required this.result,
    required this.range,
    required this.trend,
    required this.trendLabels,
    required this.historyRows,
    required this.inspector,
    required this.busy,
    required this.onShow,
    required this.onHide,
    required this.onSelect,
    required this.onToggle,
    required this.onTab,
    required this.onAction,
    required this.onRange,
    required this.onCloseInspector,
    required this.onSubmit,
    required this.onMenu,
  }) : super(
         equals: [
           treeLabel,
           tree,
           watch,
           keyName,
           title,
           pill,
           tabs,
           tab,
           points,
           params,
           actionGroups,
           result,
           range,
           trend,
           trendLabels,
           historyRows,
           inspector,
           busy,
         ],
       );

  final String treeLabel;
  final List<TreeRowVm> tree;
  final List<String> watch;
  final String? keyName;
  final String? title;
  final StatusPillVm? pill;
  final List<TabItemVm> tabs;
  final String tab;
  final List<RowVm> points;
  final List<FactVm> params;
  final List<ActionCardGroupVm> actionGroups;
  final ResultVm? result;
  final String range;
  final List<TrendSeriesVm> trend;
  final (String, String) trendLabels;
  final List<RowVm> historyRows;
  final ExplorerInspectorVm? inspector;
  final bool busy;
  final VoidCallback onShow;
  final void Function(List<String> keys) onHide;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onTab;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onRange;
  final VoidCallback onCloseInspector;
  final Future<void> Function(Map<String, Object?> values) onSubmit;
  final Future<void> Function(BuildContext context, String id, Offset at)
  onMenu;
}
