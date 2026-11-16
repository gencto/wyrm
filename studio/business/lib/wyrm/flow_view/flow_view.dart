import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/palette_entry.dart';
import 'package:models/palette_tab.dart';
import 'package:models/param_spec.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm, Value;

import '../../common/memo.dart';
import '../../redux/app_state.dart';
import '../../redux/flow_editor/actions/deploy_flow_action.dart';
import '../../redux/flow_editor/actions/remove_library_block_action.dart';
import '../../redux/flow_editor/actions/save_block_to_library_action.dart';
import '../../redux/flow_editor/actions/update_block_from_library_action.dart';
import '../decode/flow_def.dart';
import '../mappers/block_cfg.dart';
import '../mappers/flow_blocks.dart';
import '../mappers/flow_fields.dart';
import '../rights.dart';
import 'block_view.dart';
import 'flow_live.dart';
import 'inspector_view.dart';
import 'off.dart';
import 'palette_view.dart';
import 'prompt_view.dart';
import 'questions_view.dart';
import 'summary_view.dart';
import 'viewer_view.dart';

/// The route id of a flow not made yet (`/flows/+new`).
const newFlowId = '+new';

/// What the top bar says of the draft.
enum EditorStatus {
  /// The flow is being read.
  loading,

  /// A deploy is running.
  deploying,

  /// The draft differs from the deployed version (or is new).
  draft,

  /// The draft is the deployed version ([FlowView.version]).
  deployed,
}

/// Why Deploy is off ([OffFor.reason]); a lacking right is [OffNeeds].
enum DeployOffReason {
  loading,

  /// Inside a custom block: back to the flow first.
  inside,

  /// The draft is the deployed version.
  nothing,

  /// The last validation found problems.
  fixFirst,
}

/// What the editor subscribes to and reads while it is shown: the points
/// of the Tree tab and of the blocks, the flow's own value ([watch]); the
/// nodes whose `~meta` its action blocks wait for ([details]); and what
/// the draft runs as ([run], its definition with the layout aside: a
/// change runs it again as a preview).
final class FlowFollow extends Equatable {
  const FlowFollow({
    required this.watch,
    required this.details,
    required this.run,
  });

  static const none = FlowFollow(
    watch: ISetConst({}),
    details: ISetConst({}),
    run: null,
  );

  final ISet<String> watch;
  final ISet<String> details;
  final Value? run;

  @override
  List<Object?> get props => [watch, details, run];
}

/// The flow editor as it is drawn (flow-editor.md): every part of the page
/// as typed values, made from the state by [flowViewOf]. Each part is kept
/// while its inputs are the same objects, so a dispatch that changes
/// nothing on the page gives an equal (the same) view.
final class FlowView extends Equatable {
  const FlowView({
    required this.root,
    required this.status,
    required this.version,
    required this.dot,
    required this.isNew,
    required this.flowName,
    required this.crumbs,
    required this.palette,
    required this.myBlocksOff,
    required this.catalog,
    required this.myBlocks,
    required this.library,
    required this.blocks,
    required this.wires,
    required this.follow,
    required this.questions,
    this.deployOff,
    this.selected,
    this.selectedCount = 0,
    this.instances,
    this.tree,
    this.inspector,
    this.summary,
    this.viewer,
    this.prompt,
    this.customBlock,
  });

  /// `wy/<site>`.
  final String root;
  final EditorStatus status;

  /// The deployed version ([EditorStatus.deployed]).
  final int version;

  /// The draft differs from the deployed version: a dot before the status.
  final bool dot;

  /// Why Deploy is off; null: it deploys.
  final Off<DeployOffReason>? deployOff;

  /// A flow made here, not deployed yet: its name is typed.
  final bool isNew;

  /// The flow's id; null: a new flow with no name yet.
  final String? flowName;

  /// The selected block; with no one block, how many are selected.
  final String? selected;
  final int selectedCount;

  /// The custom blocks the canvas is inside of, outermost first.
  final IList<String> crumbs;

  /// Inside a block: its instances in the flow.
  final int? instances;
  final PaletteTab palette;

  /// The broker has no custom blocks: My blocks is off.
  final bool myBlocksOff;
  final IList<CatalogEntry> catalog;
  final IList<MyBlockEntry> myBlocks;
  final IList<LibraryEntry> library;

  /// The Tree tab's rows; null on the other tabs.
  final IList<TreeEntry>? tree;
  final IList<BlockView> blocks;
  final IList<WireView> wires;

  /// The selected block's inspector; null: nothing selected.
  final InspectorView? inspector;

  /// The flow's summary while nothing is selected.
  final FlowSummaryView? summary;

  /// The open viewer of a field.
  final ViewerView? viewer;

  /// The scope asked of a key that got a wire.
  final ScopePromptView? prompt;
  final FlowFollow follow;

  /// What the page asks while the user acts (the menu, a wire's refusal,
  /// the dialogs' checks), answered from what the editor shows.
  final FlowQuestions questions;

  /// What `Create custom block…` proposes for the selection; null: there
  /// is nothing to make a block of.
  final CustomBlockView? customBlock;

  /// A block is selected: Remove block is on.
  bool get removable => selected != null;

  /// What the palette's entry at place [i] places: the Blocks tab lists
  /// [catalog], My blocks [myBlocks] then [library], the Tree tab none
  /// (its rows are [tree]); null when there is none.
  PaletteEntry? paletteEntryAt(int i) => switch (palette) {
    PaletteTab.blocks => switch (catalog.elementAtOrNull(i)) {
      final c? => EnginePick(c.type),
      null => null,
    },
    PaletteTab.my =>
      myBlocks.elementAtOrNull(i)?.entry ??
          library.elementAtOrNull(i - myBlocks.length)?.entry,
    PaletteTab.tree => null,
  };

  /// The name of the custom block or of the library's block at place [i]
  /// of My blocks; null on the other tabs or when there is none.
  String? paletteNameAt(int i) => switch (palette) {
    PaletteTab.my =>
      myBlocks.elementAtOrNull(i)?.name ??
          library.elementAtOrNull(i - myBlocks.length)?.name,
    PaletteTab.blocks || PaletteTab.tree => null,
  };

  /// The field that stands at place [row] among block [block]'s rows on the
  /// canvas (what the canvas reports a row by); null when there is none.
  FieldId? rowAt(String block, int row) {
    final rows = blocks.where((b) => b.id == block).firstOrNull?.rows;
    return rows == null || row < 0 || row >= rows.length ? null : rows[row].id;
  }

  @override
  List<Object?> get props => [
    root,
    status,
    version,
    dot,
    deployOff,
    isNew,
    flowName,
    selected,
    selectedCount,
    crumbs,
    instances,
    palette,
    myBlocksOff,
    catalog,
    myBlocks,
    library,
    tree,
    blocks,
    wires,
    inspector,
    summary,
    viewer,
    prompt,
    follow,
    questions,
    customBlock,
  ];
}

/// What every part of the view is made from: the flow, its types and
/// fields. Kept while the draft, the frames, the deployed version, the
/// catalogue, the site and the nodes' `~meta` are the same objects.
final class FlowBase {
  FlowBase._({
    required this.root,
    required this.routeId,
    required this.draft,
    required this.flow,
    required this.deployed,
    required this.allTypes,
    required this.types,
    required this.caps,
    required this.differs,
    required this.previewDiffers,
    required this.run,
    required this.defs,
    required this.fields,
    required this.rows,
    required this.liveKeys,
  });

  /// `wy/<site>`.
  final String root;
  final String routeId;

  /// What the canvas shows: the flow, or the inside of a custom block.
  final FlowDraft? draft;

  /// The flow itself, every inside view folded back into it: what
  /// validate, preview and deploy read.
  final FlowDraft? flow;
  final FlowDraft? deployed;
  final IList<NodeType> allTypes;
  final Map<BlockType, NodeType> types;
  final FlowCaps caps;

  /// The flow differs from the deployed version.
  final bool differs;

  /// The flow runs otherwise than the deployed version (its layout aside).
  final bool previewDiffers;

  /// What the draft runs as.
  final Value? run;
  final Map<String, BlockDef> defs;

  /// Every block's fields, by block id.
  final Map<String, List<FlowField>> fields;

  /// Every block's rows: its pinned fields (spec §12).
  final Map<String, List<FlowField>> rows;

  /// The live values the blocks read ([liveKeysOf]).
  final List<String> liveKeys;

  bool get isNew => routeId == newFlowId;
  bool get inside => draft != null && flow != null && !identical(draft, flow);

  /// The flow's id ('' while a new flow has none).
  String get id => flow?.id ?? '';
}

/// A save to, an update from or a removal from the site's library runs
/// (each is `NonReentrant`): the My blocks tab holds the library's items.
bool libraryBusyOf(AppState s) =>
    s.wait.isWaitingForType<SaveBlockToLibraryAction>() ||
    s.wait.isWaitingForType<UpdateBlockFromLibraryAction>() ||
    s.wait.isWaitingForType<RemoveLibraryBlockAction>();

final _base = Memo<FlowBase>();

/// The base of the view of [s] for the route [routeId].
FlowBase flowBaseOf(AppState s, String routeId) {
  final fe = s.flowEditor;
  return _base.of(
    [
      s.site,
      fe.draft,
      fe.frames,
      fe.deployed,
      fe.types,
      fe.libraryOff,
      s.nodes.detail,
      routeId,
    ],
    () {
      final root = SelectSite(s).root ?? '';
      final d = fe.draft;
      final flow = rootDraft(fe.frames, d);
      final dep = fe.deployed;
      final all = typesWithBlocks(fe.types, d);
      final types = {for (final t in all) t.type: t};
      final edges = d?.edges ?? const IListConst<FlowEdge>([]);
      final blocks = d?.blocks ?? const IMapConst<String, FlowBlock>({});
      final fields = {
        for (final x in blocks.values)
          x.id: fieldsOf(
            types[x.type],
            x,
            edges: edges,
            actionParams: _actionParams(root, x, s),
          ),
      };
      final run = flow == null ? null : previewDefOf(flow);
      return FlowBase._(
        root: root,
        routeId: routeId,
        draft: d,
        flow: flow,
        deployed: dep,
        allTypes: all,
        types: types,
        caps: flowCapsOf(fe.types, libraryOff: fe.libraryOff),
        differs:
            flow != null && (dep == null || defOf(flow, 0) != defOf(dep, 0)),
        previewDiffers:
            flow != null && (dep == null || previewDefOf(dep) != run),
        run: run,
        defs: blockDefsOf(d),
        fields: fields,
        // Rows a block draws: its pinned fields (spec §12): the user's
        // choice, else the type's default, and always a field a wire
        // touches.
        rows: {
          for (final x in blocks.values)
            x.id: [
              for (final f in fields[x.id]!)
                if (fieldPinned(x, f, edges)) f,
            ],
        },
        liveKeys: liveKeysOf(root, flow?.id ?? '', d, dep),
      );
    },
  );
}

/// The parameters of the action an `invoke` block runs, from its node's
/// `~meta` (read once, `nodes.detail`); none while it is not read.
Iterable<ParamSpec> _actionParams(String root, FlowBlock b, AppState s) {
  if (b.type.known != KnownBlock.invoke) {
    return const [];
  }
  final path = pointOf(b);
  final name = b.cfgAction;
  return path == null
      ? const []
      : s.nodes.detail[fullKey(root, path)]?.actions
                .where((a) => a.name == name)
                .firstOrNull
                ?.params ??
            const [];
}

/// Whether the draft's values come from its preview: it runs otherwise
/// than the deployed version (its layout aside), the broker has a preview,
/// and the preview has answered (until then the watch's values stay, so
/// the first edit does not blank every field).
bool previewingOf(AppState s, FlowBase base) {
  final fe = s.flowEditor;
  return base.flow != null &&
      fe.previewOff == null &&
      (fe.previewPorts.isNotEmpty ||
          fe.previewSinks.isNotEmpty ||
          fe.previewError != null) &&
      base.previewDiffers;
}

/// The live values of [base]'s blocks in [s].
FlowLive flowLiveOf(AppState s, FlowBase base, {required bool previewing}) {
  final values = s.live.values;
  return FlowLive(
    root: base.root,
    flow: base.id,
    draft: base.draft,
    deployed: base.deployed,
    frames: s.flowEditor.frames,
    fields: base.fields,
    ports: s.flowEditor.ports,
    previewPorts: s.flowEditor.previewPorts,
    values: {for (final k in base.liveKeys) k: values[k]},
    previewing: previewing,
    differs: base.differs,
  );
}

/// The live values the blocks read, in [s]: the items a memo compares
/// (never the whole map, which is new on every change of any key).
List<LiveValue?> _liveOf(AppState s, FlowBase base) => [
  for (final k in base.liveKeys) s.live.values[k],
];

final _blocks = Memo<IList<BlockView>>();
final _wires = Memo<IList<WireView>>();
final _inspector = Memo<InspectorView?>();
final _summary = Memo<FlowSummaryView?>();
final _viewer = Memo<ViewerView?>();
final _prompt = Memo<ScopePromptView?>();
final _catalog = Memo<IList<CatalogEntry>>();
final _myBlocks = Memo<IList<MyBlockEntry>>();
final _library = Memo<IList<LibraryEntry>>();
final _treeKeys = Memo<List<String>>();
final _tree = Memo<IList<TreeEntry>?>();
final _follow = Memo<FlowFollow>();
final _view = Memo<FlowView>();
final _config = Memo<Lack?>();
final _deployOff = Memo<Off<DeployOffReason>?>();
final _questions = Memo<FlowQuestions>();
final _customBlock = Memo<CustomBlockView?>();

/// The flow editor of [s] for the route [routeId] (`newFlowId` for a new
/// flow): its every part, each made again only when what it reads changed.
FlowView flowViewOf(AppState s, String routeId) {
  final fe = s.flowEditor;
  final site = SelectSite(s);
  final base = flowBaseOf(s, routeId);
  final root = base.root;
  final d = base.draft;
  final previewing = previewingOf(s, base);
  final live = _liveOf(s, base);
  final busy = s.wait.isWaitingForType<DeployFlowAction>();
  final sel = fe.selectedBlock;
  final b = sel == null ? null : d?.blocks[sel];
  final inside = fe.frames.isNotEmpty;
  final config = _config.of(
    [s.site],
    () => site.lacks(Perm.config, '$root/dataflows'),
  );

  final blocks = _blocks.of(
    [
      base,
      previewing,
      fe.ports,
      fe.previewPorts,
      fe.previewSinks,
      fe.previewError,
      fe.selection,
      s.nodes.table,
      ...live,
    ],
    () {
      final l = flowLiveOf(s, base, previewing: previewing);
      return [
        for (final x in d?.blocks.values ?? const <FlowBlock>[])
          blockViewOf(
            x,
            base.types[x.type],
            base.rows[x.id]!,
            d!,
            l.of(x),
            selected: fe.selection.contains(x.id),
            previewing: previewing,
            root: root,
            frames: fe.frames,
            previewSinks: fe.previewSinks,
            previewFailed: fe.previewError != null,
            nodes: s.nodes.table,
            customBlocks: base.caps.blocks,
          ),
      ].lock;
    },
  );
  final wires = _wires.of(
    [base],
    () => d == null
        ? const IListConst<WireView>([])
        : wireViewsOf(d, base.fields),
  );
  final inspector = _inspector.of(
    [
      base,
      b,
      previewing,
      fe.ports,
      fe.previewPorts,
      fe.flowId,
      ...live,
    ],
    () {
      if (b == null || d == null) {
        return null;
      }
      final l = flowLiveOf(s, base, previewing: previewing);
      return inspectorViewOf(
        b,
        base.types[b.type],
        d,
        base.fields,
        l.of(b),
        customBlocks: base.caps.blocks,
        runOff: runOffOf(
          b,
          caps: base.caps,
          isNew: base.isNew,
          deployed: base.deployed != null,
          differs: base.differs,
          engineId: engineIdOf(fe.frames, b.id),
          write: site.lacks(
            Perm.write,
            '$root/dataflows/${fe.flowId ?? ''}',
          ),
        ),
        scopeProblemOf: (scope) => scopeProblemAt(root, scope),
      );
    },
  );
  final own = s.live.values['$root/dataflows/${base.id}'];
  final summary = _summary.of(
    [
      base,
      b == null,
      previewing,
      fe.version,
      fe.problems,
      fe.previewError,
      fe.watchRefused,
      fe.previewOff,
      s.flows.table,
      own,
    ],
    () => b != null
        ? null
        : summaryViewOf(
            base.id,
            base.flow,
            version: fe.version,
            own: own,
            known: s.flows.table[base.id],
            deployed: base.deployed != null,
            previewing: previewing,
            watchRefused: fe.watchRefused,
            previewOff: fe.previewOff,
            previewError: fe.previewError,
            problems: fe.problems,
          ),
  );
  final viewer = _viewer.of(
    [
      base,
      fe.viewedField,
      previewing,
      fe.ports,
      fe.previewPorts,
      s.nodes.table,
      ...live,
    ],
    () {
      final at = fe.viewedField;
      final vb = at == null ? null : d?.blocks[at.block];
      if (at == null || vb == null || d == null) {
        return null;
      }
      final point = pointOf(vb);
      return viewerViewOf(
        vb,
        at.row,
        base.fields[vb.id]!,
        d,
        flowLiveOf(s, base, previewing: previewing).of(vb),
        type: base.allTypes.where((x) => x.type == vb.type).firstOrNull,
        info: point == null ? null : s.nodes.table[fullKey(root, point)],
      );
    },
  );
  final prompt = _prompt.of(
    [base, fe.scopePrompt],
    () => scopePromptOf(
      root,
      fe.scopePrompt,
      d?.blocks ?? const IMapConst<String, FlowBlock>({}),
      base.types,
      base.rows,
    ),
  );
  final catalog = _catalog.of([fe.types], () => catalogOf(fe.types));
  final libraryBusy = libraryBusyOf(s);
  final myBlocks = _myBlocks.of(
    [base, fe.library, config, libraryBusy],
    () => myBlocksOf(
      base.flow,
      base.defs,
      library: fe.library,
      frames: fe.frames,
      config: config,
      libraryBusy: libraryBusy,
    ),
  );
  final library = _library.of(
    [fe.library, fe.frames, config, libraryBusy],
    () => libraryOf(
      fe.library,
      frames: fe.frames,
      config: config,
      libraryBusy: libraryBusy,
    ),
  );
  final tree = fe.palette != PaletteTab.tree
      ? null
      : () {
          final nodes = s.nodes;
          final keys = _treeKeys.of(
            [nodes.table],
            () => treeValueKeysOf(nodes.table),
          );
          final values = [for (final k in keys) s.live.values[k]];
          return _tree.of(
            [
              base,
              nodes.table,
              nodes.view,
              nodes.expanded,
              nodes.detail,
              nodes.listed,
              fe.treeQuery,
              ...values,
            ],
            () => treeOf(
              root: root,
              blocks: d?.blocks ?? const IMapConst<String, FlowBlock>({}),
              table: nodes.table,
              view: nodes.view,
              expanded: nodes.expanded,
              detail: nodes.detail,
              listed: nodes.listed,
              query: fe.treeQuery,
              values: {for (final (i, k) in keys.indexed) k: values[i]},
            ),
          );
        }();
  final follow = _follow.of(
    [base, fe.palette, s.nodes.expanded, s.nodes.detail],
    () => followOf(s, base),
  );
  final status = switch (d) {
    null => EditorStatus.loading,
    _ when busy => EditorStatus.deploying,
    _ when base.differs || base.isNew => EditorStatus.draft,
    _ => EditorStatus.deployed,
  };
  final deployOff = _deployOff.of(
    [d == null, inside, base.differs, base.isNew, fe.problems.isEmpty, config],
    () => d == null
        ? const OffFor<DeployOffReason>(DeployOffReason.loading)
        : inside
        ? const OffFor(DeployOffReason.inside)
        : (!base.differs && !base.isNew
              ? const OffFor(DeployOffReason.nothing)
              : (fe.problems.isNotEmpty
                    ? const OffFor(DeployOffReason.fixFirst)
                    : offNeeds<DeployOffReason>(config))),
  );
  final questions = _questions.of(
    [base, fe.undo.isNotEmpty, fe.redo.isNotEmpty, fe.viewedField],
    () => FlowQuestions(
      base,
      canUndo: fe.undo.isNotEmpty,
      canRedo: fe.redo.isNotEmpty,
      viewed: fe.viewedField,
    ),
  );
  final customBlock = _customBlock.of(
    [d, fe.selection, base.caps.blocks],
    () => customBlockOf(d, fe.selection, customBlocks: base.caps.blocks),
  );
  final selectedCount = fe.selection.length;
  final instances = inside && base.flow != null
      ? instancesOf(base.flow!, fe.frames.last.block)
      : null;
  return _view.of(
    [
      blocks,
      wires,
      inspector,
      summary,
      viewer,
      prompt,
      catalog,
      myBlocks,
      library,
      tree,
      follow,
      status,
      fe.version,
      deployOff,
      sel,
      selectedCount,
      instances,
      fe.palette,
      base,
      questions,
      customBlock,
    ],
    () => FlowView(
      root: root,
      status: status,
      version: fe.version,
      dot: d != null && !busy && (base.differs || base.isNew),
      deployOff: deployOff,
      isNew: base.isNew,
      flowName: base.id.isEmpty ? null : base.id,
      selected: sel,
      selectedCount: selectedCount,
      crumbs: [for (final f in fe.frames) f.block].lock,
      instances: instances,
      palette: fe.palette,
      myBlocksOff: !base.caps.blocks,
      catalog: catalog,
      myBlocks: myBlocks,
      library: library,
      tree: tree,
      blocks: blocks,
      wires: wires,
      inspector: inspector,
      summary: summary,
      viewer: viewer,
      prompt: prompt,
      follow: follow,
      questions: questions,
      customBlock: customBlock,
    ),
  );
}

/// What the editor of [base] subscribes to and reads ([FlowFollow]).
FlowFollow followOf(AppState s, FlowBase base) {
  final root = base.root;
  if (root.isEmpty) {
    return FlowFollow(
      watch: const ISetConst({}),
      details: const ISetConst({}),
      run: base.run,
    );
  }
  final nodes = s.nodes;
  final id = base.routeId;
  final read = nodes.detail;
  return FlowFollow(
    watch: {
      // The values of the leaves the Tree tab shows: every open node's.
      if (s.flowEditor.palette == PaletteTab.tree)
        for (final k in nodes.expanded)
          if (treeSections.any((s) => k.startsWith('$root/$s'))) '$k/*',
      for (final b in base.draft?.blocks.values ?? const <FlowBlock>[])
        if (isPoint(b.type))
          if (pointOf(b) case final k?) fullKey(root, k),
      if (id != newFlowId) '$root/dataflows/$id',
      // What the deployed publish blocks last published: their inputs.
      if (id != newFlowId)
        for (final b in base.deployed?.blocks.values ?? const <FlowBlock>[])
          ?publishedKey(root, id, b),
    }.lock,
    // The nodes whose actions the flow's `invoke` blocks run and whose
    // `~meta` is not read yet: it says what each argument is.
    details: {
      for (final b in base.draft?.blocks.values ?? const <FlowBlock>[])
        if (b.type.known == KnownBlock.invoke)
          if (pointOf(b) case final k? when !read.containsKey(fullKey(root, k)))
            fullKey(root, k),
    }.lock,
    run: base.run,
  );
}

/// The live value the field [row] of [block] shows now (what an unbind
/// keeps of a typed parameter).
LiveValue? shownValueAt(AppState s, String routeId, String block, FieldId row) {
  final base = flowBaseOf(s, routeId);
  final f = base.fields[block]?.where((f) => f.id == row).firstOrNull;
  final port = f?.inPort;
  if (port == null) {
    return null;
  }
  final l = flowLiveOf(s, base, previewing: previewingOf(s, base));
  return l.shown[portKey(PortSide.input, block, port)];
}
