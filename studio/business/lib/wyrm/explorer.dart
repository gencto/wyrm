import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/action_answer.dart';
import 'package:models/action_info.dart';
import 'package:models/audit_entry.dart';
import 'package:models/driver_status.dart';
import 'package:models/explorer_tab.dart';
import 'package:models/flow_summary.dart';
import 'package:models/hist_point.dart';
import 'package:models/link_mode.dart';
import 'package:models/link_state.dart';
import 'package:models/live_value.dart';
import 'package:models/node_detail.dart';
import 'package:models/node_glyph.dart';
import 'package:models/node_info.dart';
import 'package:models/node_kind.dart';
import 'package:models/param_spec.dart';
import 'package:models/point_mark.dart';
import 'package:models/point_param.dart';
import 'package:models/point_register.dart';
import 'package:models/quality.dart';
import 'package:models/read_failure.dart';
import 'package:models/staged_change.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm, TypeCode;

import '../common/memo.dart';
import '../redux/app_state.dart';
import '../redux/nodes/actions/invoke_node_action.dart';
import '../redux/nodes/actions/stage_point_edit_action.dart';
import 'decode/decoded.dart';
import 'decode/live_values.dart';
import 'decode/node_glyph.dart';
import 'decode/point_edit.dart';
import 'history_steps.dart';
import 'kinds.dart';
import 'labels.dart';
import 'mappers/value_text.dart';
import 'points.dart';
import 'trend_window.dart';

// What Explorer shows, computed from the state (studio-rules §3): the
// connector reads these and maps them to `ui`; it filters, sorts and
// formats nothing itself. Words are `ui`'s: what is here is typed (enums,
// numbers, times) or the domain's own text (a node's name, a broker's
// enum name, a value as the user reads it).

/// The sections of a site the tree starts from (`sys/**` is not in the
/// tree: it is in Links, Access, Sites and System, docs/studio.md §7.4).
const explorerSections = ['downstream', 'dataflows', 'storage', 'upstream'];

/// The poll rates of the Polling segments and of Set poll, in seconds.
const explorerPolls = [0.25, 0.5, 1.0, 5.0];

/// A read of a node that failed: what, and why (the status's wire name).
typedef ReadFail = ({ReadFailure what, String reason});

/// Whether a control can run: the action is there and the user has its
/// level on the node.
sealed class Reach {
  const Reach();
}

/// It runs.
final class CanRun extends Reach {
  const CanRun();
}

/// The node has no action [action].
final class NoSuchAction extends Reach {
  const NoSuchAction(this.action);

  final String action;
}

/// The user lacks [level] on [path] (the key under the site).
final class LacksLevel extends Reach {
  const LacksLevel(this.level, this.path);

  final Perm level;
  final String path;
}

/// One row of the tree.
typedef ExplorerTreeRow = ({
  String key,
  String name,
  int depth,
  NodeInfo? info,

  /// What the row is drawn as.
  NodeGlyph glyph,
  bool section,
  bool open,

  /// The children shown under an open row.
  int? count,

  /// A link's run mode (`downstream/<l>` only).
  LinkMode? mode,

  /// A link's state (`downstream/<l>` only): null with no sample yet.
  Decoded<LinkState>? linkState,
  bool selected,
  bool marked,
  bool staged,
  List<ReadFail> fails,
});

/// The pill beside the node's name.
sealed class ExplorerPill {
  const ExplorerPill();
}

/// A flow's state.
final class FlowPill extends ExplorerPill {
  const FlowPill(this.flow);

  final FlowSummary flow;
}

/// A link's state.
final class LinkPill extends ExplorerPill {
  const LinkPill(this.state);

  final Decoded<LinkState> state;
}

/// A broker's `connected`.
final class BrokerPill extends ExplorerPill {
  const BrokerPill({required this.connected});

  final bool connected;
}

/// A connection's or a device's framework `status`: its enum name as the
/// driver gives it, and the state it is when this client knows it.
final class DriverPill extends ExplorerPill {
  const DriverPill(this.name, this.status);

  final String name;
  final DriverStatus? status;
}

/// The line under the node's name: `modbus device · unit 1 ·
/// 127.0.0.1:5020 · last read 12:00:03`, `dataflow · deployed by admin`,
/// `folder · 3 children`, then a flow's description.
typedef ExplorerSubtitle = ({
  String? driver,
  NodeKind kind,
  String? deployedBy,
  String? problem,
  String? unit,
  String? host,
  String? port,
  String? serialPort,
  String? root,
  int? children,
  DateTime? lastRead,
  String? description,
});

/// One row of the points table: a point, or one staged to be added
/// (`adding`: `not applied`).
typedef ExplorerPointRow = ({
  String id,

  /// Null: a point staged to be added with no name given.
  String? name,
  String? display,
  PointRegister register,

  /// The driver's data type (`f32_wswap`), when it names one.
  String? dtype,

  /// The value's type.
  TypeCode? type,
  String? unit,
  num? poll,

  /// The rate before a staged edit of it.
  num? pollWas,

  /// The value as the user reads it; null: none to show (`—`).
  String? value,
  PointMark mark,

  /// Why reading the value failed (the status's wire name).
  String? failed,
  bool writable,
  bool checked,
  bool selected,
  bool staged,
  bool stale,
  bool adding,
});

/// One row of the Contents tab: a child value ([ExplorerValueRow]) or
/// node ([ExplorerNodeRow]).
sealed class ExplorerChildRow {
  const ExplorerChildRow({
    required this.key,
    required this.name,
    required this.display,
    required this.selected,
  });

  final String key;
  final String name;
  final String? display;
  final bool selected;
}

/// A child value: its type, whether it is writable, and its value as the
/// user reads it, with its unit (null: none read yet).
final class ExplorerValueRow extends ExplorerChildRow {
  const ExplorerValueRow({
    required super.key,
    required super.name,
    required super.display,
    required super.selected,
    required this.type,
    required this.writable,
    required this.value,
  });

  final TypeCode type;
  final bool writable;
  final String? value;
}

/// A child node: its kind.
final class ExplorerNodeRow extends ExplorerChildRow {
  const ExplorerNodeRow({
    required super.key,
    required super.name,
    required super.display,
    required super.selected,
    required this.kind,
  });

  final NodeKind kind;
}

/// One field of a node's or a point's `edit` (or one the board shows the
/// driver has no parameter for: `missing`).
typedef ExplorerField = ({
  /// The parameter's name in the `edit`.
  String code,
  PointParam? param,

  /// The domain's label: the parameter's display name, else its name.
  String label,
  ParamSpec? spec,
  Object? value,
  String? description,
  bool missing,
});

/// A section of the inspector or of the Parameters tab.
sealed class ExplorerSection {
  const ExplorerSection();
}

/// A flow's `~val`: state, version, who deployed it, since, the error.
final class FlowStateSection extends ExplorerSection {
  const FlowStateSection(this.flow);

  final FlowSummary flow;
}

/// One fact of a node: the entry [name] of its `cfg` or `attr`, or one of
/// its diagnostic values, shown as [label]; [value] is the driver's own
/// text, null with none read.
final class NodeFact {
  const NodeFact(this.name, this.label, this.value);

  final String name;
  final String label;
  final String? value;
}

/// The node's `edit` as fields, else its `cfg` as facts; [noEdit]: it has
/// neither.
final class ParamsSection extends ExplorerSection {
  const ParamsSection({
    required this.key,
    this.fields = const [],
    this.cfg = const [],
    this.noEdit = false,
  });

  final String key;
  final List<ExplorerField> fields;

  /// `cfg`, a fact per entry.
  final List<NodeFact> cfg;
  final bool noEdit;
}

/// The node's `attr`.
final class AttributesSection extends ExplorerSection {
  const AttributesSection(this.attr);

  /// `attr`, a fact per entry (its label is its name).
  final List<NodeFact> attr;
}

/// The framework's diagnostic values (`requests`, `errors`, …).
final class DiagnosticsSection extends ExplorerSection {
  const DiagnosticsSection(this.facts);

  /// A fact per diagnostic value; its value is null with none read.
  final List<NodeFact> facts;
}

/// A point with no `edit`: its type, unit and level, read only.
final class PointFactsSection extends ExplorerSection {
  const PointFactsSection({this.type, this.unit, this.writable});

  final TypeCode? type;
  final String? unit;
  final Perm? writable;
}

/// A point's register fields (area, address, data type, word order, …).
final class RegisterSection extends ExplorerSection {
  const RegisterSection(this.key, this.fields);

  final String key;
  final List<ExplorerField> fields;
}

/// A point's value fields (unit, scale, precision, offset).
final class ValueSection extends ExplorerSection {
  const ValueSection(this.key, this.fields);

  final String key;
  final List<ExplorerField> fields;
}

/// A point's poll rate: now (staged or not), before a staged edit.
final class PollingSection extends ExplorerSection {
  const PollingSection({
    required this.key,
    required this.now,
    required this.was,
    required this.staged,
  });

  final String key;

  /// In seconds.
  final num? now;
  final num? was;
  final bool staged;
}

/// A point's write fields; a toggle says it needs [level].
final class WriteSection extends ExplorerSection {
  const WriteSection(this.key, this.fields, this.level);

  final String key;
  final List<ExplorerField> fields;
  final Perm level;
}

/// What the tree publishes for the point: its `~meta` and `~val`.
final class PublishSection extends ExplorerSection {
  const PublishSection({
    required this.type,
    required this.unit,
    required this.writable,
    required this.sample,
    required this.value,
  });

  final TypeCode? type;
  final String? unit;
  final bool writable;
  final LiveValue? sample;

  /// The sample's value as the user reads it.
  final String? value;
}

/// What the inspector shows: an action's form, a point, or the node.
sealed class ExplorerInspector {
  const ExplorerInspector();
}

/// An action's form: Stage (`config`) or Run now.
final class ActionInspector extends ExplorerInspector {
  const ActionInspector({
    required this.key,
    required this.action,
    required this.title,
    required this.cli,
    required this.reach,
    required this.user,
  });

  final String key;
  final ActionInfo action;
  final String title;

  /// The same call from `wyr`.
  final String cli;
  final Reach reach;
  final String user;

  bool get staged => action.staged;
}

/// A point: its value and quality, its sections, its new value.
final class PointInspector extends ExplorerInspector {
  const PointInspector({
    required this.key,
    required this.name,
    required this.display,
    required this.value,
    required this.fails,
    required this.mark,
    required this.time,
    required this.sections,
    required this.edit,
    required this.editValue,
    required this.choices,
    required this.readOnly,
  });

  final String key;
  final String name;
  final String? display;

  /// The value with its unit; null when a read failed (the one held is
  /// from before).
  final String? value;
  final List<ReadFail> fails;
  final PointMark mark;

  /// When the value was read; null with none or offline.
  final DateTime? time;
  final List<ExplorerSection> sections;

  /// How a new value is typed; null when the point cannot be set.
  final TypeCode? edit;
  final Object? editValue;
  final List<String> choices;

  /// Why the user cannot set it.
  final Reach readOnly;
}

/// The node on screen with no point and no action.
final class NodeInspector extends ExplorerInspector {
  const NodeInspector({
    required this.key,
    required this.kind,
    required this.title,
    required this.name,
    required this.fails,
    required this.sections,
  });

  final String key;
  final NodeKind kind;
  final String title;
  final String? name;
  final List<ReadFail> fails;
  final List<ExplorerSection> sections;
}

/// What a submit of the inspector's form does.
sealed class InspectorSubmit {
  const InspectorSubmit();
}

/// Stages the action (`config`): it waits for Review and apply.
final class StageActionSubmit extends InspectorSubmit {
  const StageActionSubmit(this.key, this.action, this.display);

  final String key;
  final ActionInfo action;
  final String display;
}

/// Runs the action now.
final class RunActionSubmit extends InspectorSubmit {
  const RunActionSubmit(this.key, this.action);

  final String key;
  final ActionInfo action;
}

/// Stages a new value of the point.
final class StageValueSubmit extends InspectorSubmit {
  const StageValueSubmit(this.key);

  final String key;
}

/// Nothing to submit.
final class NoSubmit extends InspectorSubmit {
  const NoSubmit();
}

/// One card of the Actions tab.
typedef ExplorerActionCard = ({
  ActionInfo action,
  String title,
  bool selected,
  Reach reach,
});

/// A menu item of the node menu.
typedef ExplorerMenuItem = ({
  ActionInfo action,
  String label,
  bool danger,
  Reach reach,
});

/// The node menu (§5): groups from the action `group` (null: the level's
/// own, Configure · staged or Operate · runs now), in `~meta.actions`
/// order.
typedef ExplorerMenu = ({
  String key,
  String name,
  String? driver,
  NodeKind kind,
  int actions,
  List<({String? group, bool staged, List<ExplorerMenuItem> items})> groups,
});

/// One history row, newest first.
typedef ExplorerHistoryRow = ({DateTime time, String value, Quality? quality});

/// What the History tab shows for the point.
typedef ExplorerHistory = ({
  String point,
  List<ExplorerHistoryRow> rows,

  /// Why reading it failed (the status's wire name).
  String? failed,
});

/// The selection bar's: how many rows are checked and what they allow.
typedef ExplorerSelection = ({
  int count,

  /// Every checked row has an `edit`.
  bool canSetPoll,

  /// The first checked row the user cannot remove.
  Reach remove,
});

/// The trend's range and window (µs).
typedef ExplorerTrendSpan = ({
  int rangeStart,
  int rangeEnd,
  int windowStart,
  int windowEnd,
  int minWindow,
  bool following,
});

/// The point's trend (spec trend.md §4): its rows read for the range and
/// the range and window over them.
typedef ExplorerTrend = ({
  String point,
  String name,
  String? display,
  String? unit,

  /// The point's `cfg.precision`, when it has one.
  String? precision,
  IList<HistPoint> rows,
  ExplorerTrendSpan span,
  bool loading,
});

/// The point in the value viewer, live: its key under the site, its sample.
typedef ExplorerViewer = ({
  String title,
  LiveValue? sample,
  String? unit,
  List<String> choices,

  /// The site is online: the sample is live, not the last one held.
  bool connected,
});

/// Explorer's view of the state.
extension type ExplorerView(AppState _state) {
  SelectNodes get _nodes => SelectNodes(_state);

  SelectSite get _site => SelectSite(_state);

  String get root => _site.root ?? '';

  static String parentOf(String key) => key.substring(0, key.lastIndexOf('/'));

  /// The children of [key] in the order the broker listed them.
  List<NodeInfo> childrenOf(String key) => [
    for (final k in _nodes.view)
      if (parentOf(k) == key) ?_nodes.table[k],
  ];

  bool _isLink(String key) => parentOf(key) == '$root/downstream';

  /// A link's run mode.
  LinkMode? linkModeOf(String key) =>
      _isLink(key) ? _state.links.table[key.split('/').last]?.mode : null;

  /// A link's state, from `sys/links/<id>/state`; null with no sample.
  Decoded<LinkState>? linkStateOf(String key) {
    if (!_isLink(key)) {
      return null;
    }
    final v =
        _state.live.values['$root/sys/links/${key.split('/').last}/state'];
    return v == null ? null : linkStateSampleOf(v.value);
  }

  /// The reads of [key] that failed: its value, its list, its `~meta`
  /// (docs/design/specs/errors.md §4).
  List<ReadFail> failsOf(String key) => [
    if (_state.live.failed[key] case final s?)
      (what: ReadFailure.value, reason: s),
    if (_nodes.listFailed[key] case final s?)
      (what: ReadFailure.list, reason: s),
    if (_nodes.metaFailed[key] case final s?)
      (what: ReadFailure.meta, reason: s),
  ];

  bool _staged(String key) =>
      _state.changes.table.values.any((c) => c.key == key);

  /// The tree rows; with a filter, the nodes whose name holds it and their
  /// ancestors, opened.
  List<ExplorerTreeRow> get treeRows {
    final out = <ExplorerTreeRow>[];
    final selected = _nodes.selectedNode;
    final f = _nodes.treeFilter.trim().toLowerCase();
    final keep = <String>{};
    if (f.isNotEmpty) {
      for (final n in _nodes.table.values) {
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
          _nodes.expanded.contains(key) ||
          (f.isNotEmpty && keep.any((k) => k.startsWith('$key/')));
      final kids = open ? childrenOf(key) : const <NodeInfo>[];
      out.add((
        key: key,
        name: name,
        depth: depth,
        info: info,
        glyph: nodeGlyphAt(key, root: root, info: info),
        section: section,
        open: open,
        count: open && kids.isNotEmpty ? kids.length : null,
        mode: linkModeOf(key),
        linkState: linkStateOf(key),
        selected: key == selected,
        marked: _nodes.marked.contains(key),
        staged: _staged(key),
        fails: failsOf(key),
      ));
      if (open) {
        for (final k in kids) {
          if (k.type == null || k.hasChildren) {
            walk(k.key, k.name, depth + 1, info: k);
          }
        }
      }
    }

    for (final s in explorerSections) {
      walk('$root/$s', s, 0, section: true);
    }
    return out;
  }

  /// The keys of the tree rows on screen, in their order (Shift-click).
  List<String> get treeOrder => [for (final r in treeRows) r.key];

  /// What Explorer subscribes to while its tab is shown: the links' states
  /// for the dots, the children of the selected node, the point in the
  /// value viewer, a flow's own `~val`.
  List<String> get watchKeys {
    final sel = _nodes.selectedNode;
    return [
      '$root/sys/links/*/state',
      if (sel != null) '$sel/*',
      // The point in the value viewer stays live when the tree moves on.
      ?_nodes.viewedPoint,
      if (sel != null && kindOf(sel) == NodeKind.flow) sel,
    ];
  }

  /// The enum names of [key]: a list carries none, the full meta does.
  List<String> choicesOf(String key) {
    final d = _nodes.detail[key]?.choices;
    if (d != null && d.isNotEmpty) {
      return d.unlock;
    }
    return _nodes.table[key]?.choices.unlock ?? const [];
  }

  /// The kind of [key], from its place, profile and actions: it picks the
  /// frame (docs/design/specs/explorer.md "Frames by node kind").
  NodeKind kindOf(String key) {
    final d = _nodes.detail[key];
    return nodeKindOf(
      key: key,
      root: root,
      profile: d?.profile ?? _nodes.table[key]?.profile,
      actions: [for (final a in d?.actions ?? const <ActionInfo>[]) a.name],
    );
  }

  /// A display name worth showing beside [key]'s name: not empty, not the
  /// name again.
  String? displayOf(String key) {
    final name = key.split('/').last;
    return switch (_nodes.detail[key]?.display ?? _nodes.table[key]?.display) {
      final s? when s.trim().isNotEmpty && s != name => s,
      _ => null,
    };
  }

  ActionInfo? actionOf(String key, String name) =>
      _nodes.detail[key]?.actions.where((a) => a.name == name).firstOrNull;

  /// The user may call a [level] action on [key].
  Reach reachOf(Perm level, String key) => _site.can(level, key)
      ? const CanRun()
      : LacksLevel(level, key.split('/').skip(2).join('/'));

  /// The node's own [action], with the level it needs.
  Reach actionReach(String key, String action) => switch (actionOf(
    key,
    action,
  )) {
    final a? => reachOf(a.level, key),
    null => NoSuchAction(action),
  };

  /// A value read as the user reads it, with [unit] after a number.
  String? valueOf(
    LiveValue? v,
    String? unit, {
    List<String> choices = const [],
  }) => v == null ? null : valueText(v.value, choices: choices, unit: unit);

  // ---- the node on screen --------------------------------------------------

  String? get selected => _nodes.selectedNode;

  NodeDetail? get _detail => switch (selected) {
    final s? => _nodes.detail[s],
    null => null,
  };

  List<NodeInfo> get _kids => switch (selected) {
    final s? => childrenOf(s),
    null => const [],
  };

  /// The selected node's points (its values that are no diagnostics).
  List<NodeInfo> get points => _kids.where(isPoint).toList();

  /// The kind of the selected node; a folder with none.
  NodeKind get kind => switch (selected) {
    final s? => kindOf(s),
    null => NodeKind.folder,
  };

  /// The selected flow's `~val`; null for any other node.
  Decoded<FlowSummary>? get flow {
    final s = selected;
    if (s == null || kind != NodeKind.flow) {
      return null;
    }
    return flowSampleOf(
      s.split('/').last,
      _state.live.values[s]?.value,
      description: displayOf(s),
    );
  }

  FlowSummary? get _flow => switch (flow) {
    Valid(:final value) => value,
    _ => null,
  };

  /// A link's or a connection's diagnostic values are not its contents:
  /// `status` drives the pill, the counters are in the inspector.
  bool _hidden(NodeInfo child) =>
      (kind == NodeKind.connection || kind == NodeKind.link) &&
      isDiagnostic(child);

  /// The tabs of the node's frame (docs/design/specs/explorer.md "Frames
  /// by node kind"), each with its count where it has one.
  List<(ExplorerTab, int?)> get tabs {
    final k = kind;
    return [
      if (k == NodeKind.device)
        (ExplorerTab.points, points.length)
      else if (k != NodeKind.flow)
        (ExplorerTab.children, _kids.where((c) => !_hidden(c)).length),
      (ExplorerTab.params, null),
      (ExplorerTab.actions, _detail?.actions.length ?? 0),
      if (k != NodeKind.flow) (ExplorerTab.history, null),
      (ExplorerTab.audit, null),
    ];
  }

  /// The tab on screen: the one picked when the node has it, else the
  /// frame's first.
  ExplorerTab get tab {
    final all = tabs;
    return all.any((t) => t.$1 == _nodes.tab) ? _nodes.tab : all.first.$1;
  }

  /// The display name, with the name under it (owner 2026-11-11,
  /// docs/design/specs/explorer.md §3); a flow's display name is its
  /// description and stays in the subtitle.
  String? get shownDisplay {
    final s = selected;
    return s == null || kind == NodeKind.flow ? null : displayOf(s);
  }

  /// The pill beside the name.
  ExplorerPill? get pill {
    final s = selected;
    if (s == null) {
      return null;
    }
    if (_flow case final f?) {
      return FlowPill(f);
    }
    if (linkStateOf(s) case final l?) {
      return LinkPill(l);
    }
    if (kind == NodeKind.broker) {
      return switch (_state.live.values['$s/connected']) {
        final v? => switch (brokerConnectedOf(v.value)) {
          Valid(:final value) => BrokerPill(connected: value),
          Invalid() => null,
        },
        null => null,
      };
    }
    final v = _state.live.values['$s/status'];
    if (v == null) {
      return null;
    }
    final status = driverStatusSampleOf(v.value, choicesOf('$s/status'));
    return DriverPill(status.name, status.status);
  }

  /// The line under the name.
  ExplorerSubtitle? get subtitle {
    final key = selected;
    if (key == null) {
      return null;
    }
    final k = kind;
    final d = _detail;
    final parts = key.split('/');
    final link = parts.length > 3 ? parts[3] : null;
    final driver = link == null ? null : _state.links.table[link]?.driver;
    final conn = switch (k) {
      NodeKind.device => _nodes.detail[parentOf(key)]?.cfg,
      NodeKind.connection => d?.cfg,
      _ => null,
    };
    DateTime? last;
    for (final p in points) {
      final t = _state.live.values[p.key]?.time;
      if (t != null && (last == null || t.isAfter(last))) {
        last = t;
      }
    }
    final driverKind = switch (k) {
      NodeKind.device || NodeKind.connection || NodeKind.link => true,
      _ => false,
    };
    return (
      driver: driverKind && driver != null && driver.isNotEmpty ? driver : null,
      kind: k,
      deployedBy: _flow?.deployedBy,
      problem: _flow?.problem,
      unit: k == NodeKind.device ? d?.cfg['unit'] : null,
      host: conn?['host'],
      port: conn?['host'] == null ? null : conn?['port'],
      serialPort: conn?['serial_port'],
      root: k == NodeKind.broker ? d?.attr['root'] : null,
      children: !driverKind && k != NodeKind.flow && k != NodeKind.device
          ? _kids.length
          : null,
      lastRead: k == NodeKind.device ? last : null,
      description: k == NodeKind.flow ? displayOf(key) : null,
    );
  }

  /// The selected flow's Edit dataflow: the user may read it.
  Reach? get flowEditor {
    final s = selected;
    if (s == null || _flow == null) {
      return null;
    }
    return reachOf(Perm.read, s);
  }

  /// A device's Ping, beside Actions ▾; null for any other node.
  Reach? get ping {
    final s = selected;
    return s != null && kind == NodeKind.device ? actionReach(s, 'ping') : null;
  }

  /// The name of the node's import action: `import_dsa` when it has it.
  String get importAction =>
      selected != null && actionOf(selected!, 'import_dsa') != null
      ? 'import_dsa'
      : 'import';

  /// The node can have points added (its Points tab's empty state offers
  /// the toolbar).
  bool get addsPoints =>
      selected != null && actionOf(selected!, 'add_point') != null;

  // ---- points ------------------------------------------------------------

  /// The points that pass the filter, in the broker's order.
  List<NodeInfo> get shownPoints {
    final f = _nodes.pointFilter.trim().toLowerCase();
    return [
      for (final p in points)
        if (f.isEmpty ||
            p.name.toLowerCase().contains(f) ||
            (p.display?.toLowerCase().contains(f) ?? false))
          p,
    ];
  }

  /// The keys of the point rows on screen, in their order (Shift-click,
  /// the header box).
  List<String> get pointOrder => [for (final p in shownPoints) p.key];

  /// The register of the point [key] (`HR 10`, `Coil 1`; a `cfg.address`).
  PointRegister registerOf(String key) =>
      pointRegisterOf(_nodes.detail[key]?.cfg.unlock);

  num? _seconds(Object? v) => switch (v) {
    final num n => n,
    final String t => num.tryParse(t),
    _ => null,
  };

  /// The rows of the points table: the points that pass the filter, then
  /// the points staged to be added.
  List<ExplorerPointRow> get pointRows {
    final s = selected;
    if (s == null) {
      return const [];
    }
    final offline = !_site.connected;
    return [
      for (final p in shownPoints) _pointRow(p, offline: offline),
      for (final c in _state.changes.table.values)
        if (c.key == s && c.action == 'add_point') _added(c),
    ];
  }

  ExplorerPointRow _pointRow(NodeInfo p, {required bool offline}) {
    final v = _state.live.values[p.key];
    final d = _nodes.detail[p.key];
    final edit = _state.changes.table[StagePointEditAction.idOf(p.key)];
    final stagedPoll = _seconds(edit?.args[pollParam]);
    final poll = _seconds(d?.cfg[pollParam]);
    final failed = _state.live.failed[p.key];
    return (
      id: p.key,
      name: p.name,
      display: p.display ?? d?.display,
      register: pointRegisterOf(d?.cfg.unlock),
      dtype: d?.cfg['dtype'],
      type: p.type,
      unit: switch (p.unit ?? d?.unit ?? d?.cfg['unit']) {
        final u? when u.isNotEmpty => u,
        _ => null,
      },
      poll: stagedPoll ?? poll,
      pollWas: stagedPoll != null ? poll : null,
      value: v == null || failed != null
          ? null
          : valueText(v.value, choices: choicesOf(p.key)),
      mark: offline ? PointMark.stale : _markOf(v),
      failed: failed,
      writable: p.writable != null,
      checked: _nodes.checked.contains(p.key),
      selected: p.key == _nodes.point,
      staged: _staged(p.key),
      stale: offline,
      adding: false,
    );
  }

  /// A point staged to be added to the device: `not applied`.
  ExplorerPointRow _added(StagedChange c) => (
    id: c.id,
    name: _text(c.args['name']),
    display: null,
    register: pointRegisterOf({
      for (final e in c.args.entries) e.key: '${e.value}',
    }),
    dtype: _text(c.args['dtype']),
    type: null,
    unit: switch (c.args['unit']) {
      final String u when u.isNotEmpty => u,
      _ => null,
    },
    poll: _seconds(c.args[pollParam]),
    pollWas: null,
    value: null,
    mark: PointMark.notApplied,
    failed: null,
    writable: c.args['writable'] == true,
    checked: false,
    selected: false,
    staged: true,
    stale: false,
    adding: true,
  );

  /// A staged argument as text; null when it is not given.
  static String? _text(Object? v) => switch (v) {
    null => null,
    final String t => t,
    final Object o => '$o',
  };

  static PointMark _markOf(LiveValue? v) => switch (v?.quality) {
    null => PointMark.none,
    Quality.good => PointMark.good,
    Quality.uncertain => PointMark.uncertain,
    Quality.bad => PointMark.bad,
  };

  /// No row to show (the points are still listed).
  bool get pointsLoading =>
      selected != null && _detail == null && _kids.isEmpty;

  /// The selection bar, with 2 or more rows checked.
  ExplorerSelection? get selection {
    final checked = _nodes.checked;
    if (checked.length < 2) {
      return null;
    }
    return (
      count: checked.length,
      canSetPoll: checked.every((k) => actionOf(k, 'edit') != null),
      remove:
          [
            for (final k in checked)
              if (reachOf(Perm.config, k) case final LacksLevel l) l,
          ].firstOrNull ??
          const CanRun(),
    );
  }

  /// What Copy keys and ⌘⇧C copy: the checked rows, else the node on
  /// screen and the tree rows marked.
  List<String> get copyKeys {
    final checked = _nodes.checked;
    final sel = selected;
    return [
      if (checked.isNotEmpty)
        ...checked
      else ...[
        ?sel,
        for (final k in _nodes.marked)
          if (k != sel) k,
      ],
    ];
  }

  /// What ⌘C copies: the value of the point in the inspector; null with
  /// no point or no value read.
  String? get pointValue => switch (_nodes.point) {
    final p? => valueOf(_state.live.values[p], null, choices: choicesOf(p)),
    null => null,
  };

  // ---- contents ----------------------------------------------------------

  /// The Contents tab of a node that is not a device or a flow.
  List<ExplorerChildRow> get childRows {
    if (selected == null || tabs.every((t) => t.$1 != ExplorerTab.children)) {
      return const [];
    }
    return [
      for (final k in _kids)
        if (!_hidden(k))
          switch (k.type) {
            final type? => ExplorerValueRow(
              key: k.key,
              name: k.name,
              display: displayOf(k.key),
              selected: k.key == _nodes.point,
              type: type,
              writable: k.writable != null,
              value: valueOf(
                _state.live.values[k.key],
                k.unit,
                choices: choicesOf(k.key),
              ),
            ),
            null => ExplorerNodeRow(
              key: k.key,
              name: k.name,
              display: displayOf(k.key),
              selected: k.key == _nodes.point,
              kind: kindOf(k.key),
            ),
          },
    ];
  }

  // ---- parameters and the inspector --------------------------------------

  /// The fields of [key]'s `edit` [params], the staged value in place of the
  /// current one.
  List<ExplorerField> _editFields(String key, Iterable<EditParam> params) {
    final staged = _state.changes.table[StagePointEditAction.idOf(key)]?.args;
    return [
      for (final (:spec, :param) in params)
        (
          code: spec.name,
          param: param,
          label: labelOf(spec.name, display: spec.display),
          spec: spec,
          value: staged?[spec.name] ?? spec.defaultValue?.raw,
          description: spec.description,
          missing: false,
        ),
    ];
  }

  /// A field the board shows that the driver has no parameter for.
  static ExplorerField _missing(PointParam param, {Object? value}) => (
    code: param.wire,
    param: param,
    label: param.wire,
    spec: null,
    value: value,
    description: null,
    missing: true,
  );

  /// The node's `edit` as a form, its attributes, its diagnostics (the
  /// inspector's; the Parameters tab has none).
  List<ExplorerSection> nodeSections(
    String key, {
    required bool withDiagnostics,
  }) {
    final d = _nodes.detail[key];
    final edit = actionOf(key, 'edit');
    final diag = [
      for (final n in childrenOf(key))
        if (isDiagnostic(n) && n.name != 'status') n,
    ];
    final noParams = edit == null && (d?.cfg.isEmpty ?? true);
    return [
      if (!noParams || kindOf(key) == NodeKind.device)
        ParamsSection(
          key: key,
          fields: edit == null
              ? const []
              : _editFields(key, editParamsOf(edit)),
          cfg: edit != null
              ? const []
              : [
                  for (final e
                      in d?.cfg.entries ?? const <MapEntry<String, String>>[])
                    NodeFact(e.key, humanize(e.key), e.value),
                ],
          noEdit: noParams,
        ),
      if (d != null && d.attr.isNotEmpty)
        AttributesSection([
          for (final e in d.attr.entries) NodeFact(e.key, e.key, e.value),
        ]),
      if (withDiagnostics && diag.isNotEmpty)
        DiagnosticsSection([
          for (final n in diag)
            NodeFact(
              n.name,
              labelOf(n.name, display: n.display),
              valueOf(_state.live.values[n.key], n.unit),
            ),
        ]),
    ];
  }

  /// The Parameters tab: a flow's state, then the node's sections.
  List<ExplorerSection> get params {
    final s = selected;
    if (s == null) {
      return const [];
    }
    return [
      if (_flow case final f?) FlowStateSection(f),
      ...nodeSections(s, withDiagnostics: false),
    ];
  }

  /// The sections of the point [key] in the inspector.
  List<ExplorerSection> pointSections(String key) {
    final d = _nodes.detail[key];
    final edit = actionOf(key, 'edit');
    final v = _state.live.values[key];
    final info = _nodes.table[key];
    final type = d?.type ?? info?.type;
    final unit = d?.unit ?? info?.unit;
    final writable = d?.writable ?? info?.writable;
    final publish = PublishSection(
      type: type,
      unit: unit,
      writable: writable != null,
      sample: v,
      value: v == null ? null : valueText(v.value, choices: choicesOf(key)),
    );
    if (edit == null) {
      return [
        PointFactsSection(type: type, unit: unit, writable: writable),
        publish,
      ];
    }
    final staged = _state.changes.table[StagePointEditAction.idOf(key)]?.args;
    final params = editParamsOf(edit);
    final poll = params
        .where((p) => p.param == PointParam.poll)
        .firstOrNull
        ?.spec;
    // A parameter the board does not name goes to Register.
    final registerFields = _editFields(key, [
      for (final p in params)
        if ((p.param?.group ?? PointParamGroup.register) ==
            PointParamGroup.register)
          p,
    ]);
    if (params.any((p) => p.param == PointParam.dtype)) {
      final dtype = '${staged?['dtype'] ?? d?.cfg['dtype'] ?? ''}';
      registerFields.insert(
        registerFields.indexWhere((f) => f.param == PointParam.dtype) + 1,
        _missing(PointParam.wordOrder, value: wordOrderOf(dtype)),
      );
    }
    final pollNow = staged?[PointParam.poll.wire] ?? poll?.defaultValue?.raw;
    final pollWas = poll?.defaultValue?.raw;
    return [
      RegisterSection(key, registerFields),
      ValueSection(key, [
        ..._editFields(key, [
          for (final p in params)
            if (p.param == PointParam.unit || p.param == PointParam.scale) p,
        ]),
        if (!params.any((p) => p.param == PointParam.precision))
          _missing(PointParam.precision),
        ..._editFields(key, [
          for (final p in params)
            if (p.param?.group == PointParamGroup.value &&
                p.param != PointParam.unit &&
                p.param != PointParam.scale)
              p,
        ]),
      ]),
      if (poll != null)
        PollingSection(
          key: key,
          now: _seconds(pollNow),
          was: _seconds(pollWas),
          staged:
              (staged?.containsKey(PointParam.poll.wire) ?? false) &&
              _seconds(pollNow) != _seconds(pollWas),
        ),
      WriteSection(
        key,
        _editFields(key, [
          for (final p in params)
            if (p.param?.group == PointParamGroup.write) p,
        ]),
        edit.level,
      ),
      publish,
    ];
  }

  /// What the inspector shows.
  ExplorerInspector? get inspector {
    final sel = selected;
    if (sel == null) {
      return null;
    }
    if (_nodes.action case final a?) {
      final act = _detail?.actions.where((x) => x.name == a).firstOrNull;
      if (act != null) {
        return ActionInspector(
          key: sel,
          action: act,
          title: labelOf(act.name, display: act.display),
          cli: [
            'wyr invoke $sel ${act.name}',
            for (final p in act.params) '${p.name}=…',
          ].join(' '),
          reach: reachOf(act.level, sel),
          user: _site.user ?? '',
        );
      }
    }
    if (_nodes.point case final point?) {
      final pd = _nodes.detail[point];
      final info = _nodes.table[point];
      final v = _state.live.values[point];
      final writable = pd?.writable ?? info?.writable;
      final choices = choicesOf(point);
      final type = pd?.type ?? info?.type;
      return PointInspector(
        key: point,
        name: point.split('/').last,
        display: pd?.display ?? info?.display,
        // No value is shown beside the mark: the one held is from before
        // the read failed.
        value: _state.live.failed[point] != null
            ? null
            : valueOf(v, pd?.unit ?? info?.unit, choices: choices),
        fails: failsOf(point),
        mark: !_site.connected ? PointMark.stale : _markOf(v),
        time: _site.connected ? v?.time : null,
        sections: pointSections(point),
        edit: writable == null
            ? null
            : switch (type) {
                TypeCode.bool_ || TypeCode.number => type,
                _ when choices.isNotEmpty => TypeCode.enum_,
                _ => TypeCode.string,
              },
        editValue: switch (v?.value) {
          // An enum is edited by its name and staged as its index.
          final int i when choices.isNotEmpty =>
            i >= 0 && i < choices.length ? choices[i] : null,
          final Object x when x is num || x is bool || x is String => x,
          _ => null,
        },
        choices: choices,
        readOnly: writable == null ? const CanRun() : reachOf(writable, point),
      );
    }
    // A flow's display name is its description, not a title.
    final shown = kind == NodeKind.flow ? null : displayOf(sel);
    return NodeInspector(
      key: sel,
      kind: kind,
      title: shown ?? sel.split('/').last,
      name: shown == null ? null : sel.split('/').last,
      fails: failsOf(sel),
      sections: [
        if (_flow case final f?) FlowStateSection(f),
        ...nodeSections(sel, withDiagnostics: true),
      ],
    );
  }

  /// What a submit of the inspector's form does.
  InspectorSubmit get submit {
    final sel = selected;
    if (sel == null) {
      return const NoSubmit();
    }
    final act = switch (_nodes.action) {
      final a? => actionOf(sel, a),
      null => null,
    };
    if (act != null) {
      return act.staged
          ? StageActionSubmit(sel, act, labelOf(act.name, display: act.display))
          : RunActionSubmit(sel, act);
    }
    return switch (_nodes.point) {
      final p? => StageValueSubmit(p),
      null => const NoSubmit(),
    };
  }

  // ---- actions -----------------------------------------------------------

  /// The cards of the Actions tab: Configure · staged, then Operate · runs
  /// now.
  ({List<ExplorerActionCard> staged, List<ExplorerActionCard> now})
  get actionCards {
    final sel = selected ?? '';
    final all = _detail?.actions ?? const IListConst<ActionInfo>([]);
    ExplorerActionCard card(ActionInfo a) => (
      action: a,
      title: labelOf(a.name, display: a.display),
      selected: _nodes.action == a.name,
      reach: reachOf(a.level, sel),
    );
    return (
      staged: [
        for (final a in all)
          if (a.staged) card(a),
      ],
      now: [
        for (final a in all)
          if (!a.staged) card(a),
      ],
    );
  }

  /// The answer of the last run of the selected action; with its title
  /// and its columns' labels.
  ({String title, ActionAnswer answer, List<String> columns})? get answer {
    final sel = selected;
    final a = _nodes.action;
    if (sel == null || a == null) {
      return null;
    }
    return switch (_nodes.answers[InvokeNodeAction.resultId(sel, a)]) {
      final r? => (
        title: labelOf(a, display: actionOf(sel, a)?.display),
        answer: r,
        columns: [for (final c in r.columns) humanize(c)],
      ),
      null => null,
    };
  }

  /// The node menu of [key]; null until its `~meta` is read.
  ExplorerMenu? menuOf(String key) {
    final d = _nodes.detail[key];
    if (d == null) {
      return null;
    }
    final groups = <(String?, bool), List<ExplorerMenuItem>>{};
    for (final a in d.actions) {
      final g = (a.group, a.group == null && a.staged);
      (groups[g] ??= []).add((
        action: a,
        label: labelOf(a.name, display: a.display),
        danger: a.name.startsWith('remove') || a.name.startsWith('delete'),
        reach: reachOf(a.level, key),
      ));
    }
    final parts = key.split('/');
    final driver = parts.length > 3
        ? _state.links.table[parts[3]]?.driver
        : null;
    return (
      key: key,
      name: parts.last,
      driver: driver == null || driver.isEmpty ? null : driver,
      kind: kindOf(key),
      actions: d.actions.length,
      groups: [
        for (final MapEntry(key: (group, staged), value: items)
            in groups.entries)
          (group: group, staged: staged, items: items),
      ],
    );
  }

  /// The menu open on screen, once its node's `~meta` is read.
  ExplorerMenu? get menu => switch (_nodes.menu) {
    final k? => menuOf(k),
    null => null,
  };

  // ---- history and audit -------------------------------------------------

  /// The point whose history the History tab shows; null: none picked.
  String? get historyPoint => _nodes.point;

  /// The rows read for the point (newest first, at most 50) and why the
  /// read failed; null until its history is read.
  ExplorerHistory? get history {
    final point = _nodes.point;
    if (point == null || _nodes.historyKey != point) {
      return null;
    }
    final choices = choicesOf(point);
    return (
      point: point,
      rows: [
        for (final h in _nodes.history.reversed.take(50))
          (
            time: h.time,
            value: switch (h.value) {
              final num n when choices.isNotEmpty => valueText(
                n,
                choices: choices,
              ),
              _ => h.text,
            },
            quality: h.quality,
          ),
      ],
      failed: _nodes.historyFailed,
    );
  }

  /// The point's history range in µs: the span of `nodes.historyRange` up
  /// to when it was read (stable between dispatches).
  (int, int) get historyBounds {
    final span = _nodes.historyRange.span;
    final e = trendRangeEnd(_nodes.historyAt, [
      _nodes.history.lastOrNull?.time,
    ]);
    return (e - span.inMicroseconds, e);
  }

  /// The trend's range and window over the rows read (≤ 2000), zoomed on
  /// them without reading again (spec trend.md §4).
  ExplorerTrendSpan get trendSpan {
    final (rs, re) = historyBounds;
    final w = _nodes.historyWindow;
    final we = w?.end?.microsecondsSinceEpoch ?? re;
    final ws = w == null ? rs : we - w.span.inMicroseconds;
    final span = _nodes.historyRange.span;
    return (
      rangeStart: rs,
      rangeEnd: re,
      windowStart: ws.clamp(rs, re),
      windowEnd: we.clamp(rs, re),
      minWindow: 12 * stepDuration(stepFor(span, raw: false))!.inMicroseconds,
      following: w?.end == null,
    );
  }

  /// The trend of the point whose history is on screen; null with none.
  ExplorerTrend? get trend {
    final point = _nodes.point;
    if (point == null || _nodes.historyKey != point) {
      return null;
    }
    final info = _nodes.table[point];
    final detail = _nodes.detail[point];
    final rows = _nodes.history;
    return (
      point: point,
      name: point.split('/').last,
      display: info?.display,
      unit: detail?.unit ?? info?.unit,
      precision: detail?.cfg['precision'],
      rows: rows,
      span: trendSpan,
      loading: rows.isEmpty && _nodes.historyLoading,
    );
  }

  /// The point in the value viewer (owner request 2026-11-09); null when
  /// none is open.
  ExplorerViewer? get viewer {
    final key = _nodes.viewedPoint;
    if (key == null) {
      return null;
    }
    return (
      title: key.startsWith('$root/') ? key.substring(root.length + 1) : key,
      sample: _state.live.values[key],
      unit: _nodes.detail[key]?.unit ?? _nodes.table[key]?.unit,
      choices: choicesOf(key),
      connected: _site.connected,
    );
  }

  /// The user may read the site's audit (`config` on `sys/audit`).
  bool get canAudit => _site.can(Perm.config, '$root/sys/audit');

  /// The audit rows of the node on screen (at most 200), newest first.
  List<AuditEntry> get auditRows =>
      selected == null ? const [] : _nodes.audit.take(200).toList();

  /// The flow's Edit dataflow id.
  String? get flowId => _flow?.id;

  /// The keys whose live value or failed read the view reads: the tree
  /// rows (their failed reads, a link's `sys/links/<id>/state` for its
  /// dot), the node on screen, its children and its `connected`/`status`,
  /// the point in the inspector and the one in the value viewer.
  List<String> get readKeys {
    final sel = selected;
    return [
      for (final k in treeOrder) ...[
        k,
        if (_isLink(k)) '$root/sys/links/${k.split('/').last}/state',
      ],
      if (sel != null) ...[
        sel,
        '$sel/connected',
        '$sel/status',
        for (final c in childrenOf(sel)) c.key,
      ],
      ?_nodes.point,
      ?_nodes.viewedPoint,
    ];
  }

  /// The keys of the tree's rows whose live value or failed read the tree
  /// reads (a row's failed read, a link's dot).
  List<String> get treeReadKeys => [
    for (final k in treeOrder) ...[
      k,
      if (_isLink(k)) '$root/sys/links/${k.split('/').last}/state',
    ],
  ];
}

final _readKeys = Memo<List<String>>();
final _treeReadKeys = Memo<List<String>>();

/// The live samples and failed reads of [keys] in [s]: the items a memo
/// compares, never the whole maps, which are new on every change of any key.
List<Object?> _liveOf(AppState s, List<String> keys) => [
  for (final k in keys) s.live.values[k],
  for (final k in keys) s.live.failed[k],
];

/// What [ExplorerView] reads of [s], each the very object it read: what is
/// made of the view is kept (`Memo`) while every input is the same object.
/// The parts of the state it reads ([SelectSite], [SelectNodes], the links'
/// and the changes' tables), the one wait it reads (a history read: the
/// trend's spinner, [SelectNodes.historyLoading]) and the live values of
/// [ExplorerView.readKeys]. It reads no clock.
List<Object?> explorerInputsOf(AppState s) => [
  s.site,
  s.nodes,
  s.links.table,
  s.changes.table,
  SelectNodes(s).historyLoading,
  ..._liveOf(
    s,
    _readKeys.of([s.site, s.nodes], () => ExplorerView(s).readKeys),
  ),
];

/// What the tree's rows read of [s] ([ExplorerView.treeRows]): the same as
/// [explorerInputsOf] with the live values of its own rows only, so a
/// value of the node on screen leaves the tree as it is.
List<Object?> explorerTreeInputsOf(AppState s) => [
  s.site,
  s.nodes,
  s.links.table,
  s.changes.table,
  ..._liveOf(
    s,
    _treeReadKeys.of([s.site, s.nodes], () => ExplorerView(s).treeReadKeys),
  ),
];
