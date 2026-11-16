import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/action_info.dart';
import 'package:models/block_info.dart';
import 'package:models/block_type.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_frame.dart';
import 'package:models/live_value.dart';
import 'package:models/node_detail.dart';
import 'package:models/node_info.dart';
import 'package:models/node_type.dart';
import 'package:models/palette_entry.dart';
import 'package:wyrm_client/wyrm_client.dart' show TypeCode;

import '../decode/block_def.dart';
import '../labels.dart';
import '../mappers/flow_blocks.dart';
import '../mappers/flow_fields.dart';
import '../mappers/value_text.dart';
import '../rights.dart';
import 'off.dart';

/// Which side of the flow a catalogue type is on: where a value comes from
/// (`IN`), what the flow does to the tree (`OUT`), or a calculation (`FX`).
enum PaletteSide { input, output, logic }

/// One type of the Blocks tab: the engine's catalogue.
final class CatalogEntry extends Equatable {
  const CatalogEntry({
    required this.type,
    required this.title,
    required this.side,
    required this.category,
    required this.description,
  });

  final BlockType type;

  /// In words ([blockLabel]); the engine's name is searched too (spec §2).
  final String title;
  final PaletteSide side;
  final String category;

  /// The catalogue's description; '' when it has none.
  final String description;

  @override
  List<Object?> get props => [type, title, side, category, description];
}

/// An item of the menu of a custom block in the My blocks tab.
enum MyBlockItem { edit, save, rename, update, delete, removeLibrary }

/// Why an item of a custom block's menu is off.
enum MyBlockOffReason {
  /// Inside a custom block: go back to the flow first.
  backFirst,

  /// The site's library has no block of this name.
  notInLibrary,

  /// The flow's copy is the library's version.
  sameVersion,

  /// Instances of it are in the flow ([MyBlockEntry.used]).
  inUse,

  /// A save to, update from or removal from the site's library runs: the
  /// library's items wait for it to answer.
  libraryBusy,
}

/// One item of a custom block's menu, and why it is off.
final class MyBlockMenu extends Equatable {
  const MyBlockMenu(this.item, {this.off});

  final MyBlockItem item;
  final Off<MyBlockOffReason>? off;

  /// The item deletes or removes.
  bool get danger =>
      item == MyBlockItem.delete || item == MyBlockItem.removeLibrary;

  @override
  List<Object?> get props => [item, off];
}

/// A custom block of the flow (My blocks, spec §20).
final class MyBlockEntry extends Equatable {
  const MyBlockEntry({
    required this.name,
    required this.used,
    required this.menu,
    this.description,
    this.updateTo,
    this.insideItself = false,
  });

  final String name;
  final String? description;

  /// Its instances in the flow.
  final int used;

  /// The library has a version other than the flow's copy: that one.
  final int? updateTo;

  /// The canvas shows its inside: it cannot be placed in itself.
  final bool insideItself;
  final IList<MyBlockMenu> menu;

  PaletteEntry get entry => EnginePick(CustomType(name));

  @override
  List<Object?> get props => [
    name,
    description,
    used,
    updateTo,
    insideItself,
    menu,
  ];
}

/// A block of the site's library (My blocks, spec §20).
final class LibraryEntry extends Equatable {
  const LibraryEntry({
    required this.name,
    required this.version,
    this.description,
    this.insideItself = false,
    this.removeOff,
  });

  final String name;
  final String? description;
  final int version;
  final bool insideItself;

  /// Why `Remove from library` is off.
  final Off<MyBlockOffReason>? removeOff;

  PaletteEntry get entry => LibraryPick(name);

  @override
  List<Object?> get props => [
    name,
    description,
    version,
    insideItself,
    removeOff,
  ];
}

/// A row of the Tree tab (spec §18).
sealed class TreeEntry extends Equatable {
  const TreeEntry({
    required this.key,
    required this.name,
    required this.depth,
  });

  final String key;
  final String name;
  final int depth;
}

/// A node of the tree: it opens to its children; a value node is a leaf
/// dragged as a point.
final class TreeNodeEntry extends TreeEntry {
  const TreeNodeEntry({
    required super.key,
    required super.name,
    required super.depth,
    required this.opens,
    required this.open,
    required this.used,
    this.profile,
    this.type,
    this.value,
    this.writable = false,
  });

  /// It may open (it has, or may have, children or actions).
  final bool opens;
  final bool open;

  /// A block of the flow reads or writes it.
  final bool used;
  final String? profile;

  /// A value node's type; null for a node.
  final TypeCode? type;

  /// A value node's live value, as text; null when none came.
  final String? value;

  /// A value that may be written: dropped, it asks Read or Write.
  final bool writable;

  /// What it places on the canvas: a value node, its point.
  PaletteEntry? get entry => type == null ? null : PointPick(key);

  @override
  List<Object?> get props => [
    key,
    name,
    depth,
    opens,
    open,
    used,
    profile,
    type,
    value,
    writable,
  ];
}

/// An action of an open node: dragged, an action block.
final class TreeActionEntry extends TreeEntry {
  const TreeActionEntry({
    required super.key,
    required super.name,
    required super.depth,
    required this.node,
    required this.action,
    required this.inputs,
  });

  /// The node and the action's own name.
  final String node;
  final String action;

  /// How many parameters it takes.
  final int inputs;

  PaletteEntry get entry => ActionPick(node, action);

  @override
  List<Object?> get props => [key, name, depth, node, action, inputs];
}

/// The sections of a site the Tree tab shows: what a flow may read and
/// write (spec 06 step 9).
const List<String> treeSections = scopeSections;

/// The Blocks tab: the engine's catalogue, one line per type.
IList<CatalogEntry> catalogOf(IList<NodeType> types) => [
  for (final t in inPaletteOrder(types))
    CatalogEntry(
      type: t.type,
      title: blockLabel(t.type),
      side: isSource(t.type)
          ? PaletteSide.input
          : (isSink(t.type) ? PaletteSide.output : PaletteSide.logic),
      category: t.category,
      description: t.description,
    ),
].lock;

/// The custom blocks of [flow] ([defs]) for the My blocks tab, with the
/// site's [library]; [config] what saving to the library lacks.
IList<MyBlockEntry> myBlocksOf(
  FlowDraft? flow,
  Map<String, Map<String, Object?>> defs, {
  required IList<BlockInfo> library,
  required IList<FlowFrame> frames,
  required Lack? config,
  bool libraryBusy = false,
}) {
  final inside = frames.isNotEmpty;
  final lib = {for (final l in library) l.name: l};
  final back = inside ? const OffFor(MyBlockOffReason.backFirst) : null;
  // A library call that runs holds the library's items until it answers.
  final busy = libraryBusy ? const OffFor(MyBlockOffReason.libraryBusy) : null;
  final save = offNeeds<MyBlockOffReason>(config) ?? busy;
  return [
    for (final MapEntry(key: name, value: def) in defs.entries)
      () {
        final used = flow == null ? 0 : instancesOf(flow, name);
        final l = lib[name];
        final copied = libraryVersionOf(def);
        return MyBlockEntry(
          name: name,
          description: blockDefOrWarn(name, def)?.description,
          used: used,
          updateTo: l != null && l.version != copied ? l.version : null,
          insideItself: frames.any((f) => f.block == name),
          menu: [
            const MyBlockMenu(MyBlockItem.edit),
            MyBlockMenu(MyBlockItem.save, off: save),
            MyBlockMenu(MyBlockItem.rename, off: back),
            MyBlockMenu(
              MyBlockItem.update,
              off: l == null
                  ? const OffFor(MyBlockOffReason.notInLibrary)
                  : (l.version == copied
                        ? const OffFor(MyBlockOffReason.sameVersion)
                        : back ?? busy),
            ),
            MyBlockMenu(
              MyBlockItem.delete,
              off: used > 0 ? const OffFor(MyBlockOffReason.inUse) : back,
            ),
          ].lock,
        );
      }(),
  ].lock;
}

/// The site's library for the My blocks tab.
IList<LibraryEntry> libraryOf(
  IList<BlockInfo> library, {
  required IList<FlowFrame> frames,
  required Lack? config,
  bool libraryBusy = false,
}) => [
  for (final l in library)
    LibraryEntry(
      name: l.name,
      description: l.description,
      version: l.version,
      insideItself: frames.any((f) => f.block == l.name),
      removeOff:
          offNeeds<MyBlockOffReason>(config) ??
          (libraryBusy ? const OffFor(MyBlockOffReason.libraryBusy) : null),
    ),
].lock;

/// The full keys of the tree's value nodes: the only ones whose live values
/// the Tree tab reads.
List<String> treeValueKeysOf(IMap<String, NodeInfo> table) => [
  for (final n in table.values)
    if (n.type != null) n.key,
];

/// The Tree tab (spec §18): the site's tree as the Explorer draws it,
/// extended for the editor. A node opens to its children; a value node is
/// a leaf with its type tag and live value, dragged as a point; an open
/// node lists its actions first, dragged as action blocks. With a filter
/// ([query]): what holds it, and the nodes above, opened.
IList<TreeEntry> treeOf({
  required String root,
  required IMap<String, FlowBlock> blocks,
  required IMap<String, NodeInfo> table,
  required IList<String> view,
  required ISet<String> expanded,
  required IMap<String, NodeDetail> detail,
  required ISet<String> listed,
  required String query,
  required Map<String, LiveValue?> values,
}) {
  final out = <TreeEntry>[];
  final q = query.trim().toLowerCase();
  final used = {
    for (final x in blocks.values)
      if (pointOf(x) case final k?) fullKey(root, k),
  };
  final keep = <String>{};
  void keepUp(String key) {
    final parts = key.split('/');
    for (var i = 3; i <= parts.length; i++) {
      keep.add(parts.sublist(0, i).join('/'));
    }
  }

  if (q.isNotEmpty) {
    for (final n in table.values) {
      if (n.name.toLowerCase().contains(q)) {
        keepUp(n.key);
      }
    }
    for (final MapEntry(:key, :value) in detail.entries) {
      if (value.actions.any((a) => a.name.toLowerCase().contains(q))) {
        keepUp(key);
      }
    }
  }
  // The children of [key] in the order the broker listed them.
  List<NodeInfo> children(String key) => [
    for (final k in view)
      if (k.startsWith('$key/') && !k.substring(key.length + 1).contains('/'))
        ?table[k],
  ];
  void walk(
    String key,
    String name,
    int depth, {
    NodeInfo? info,
    bool section = false,
  }) {
    if (q.isNotEmpty && !keep.contains(key)) {
      return;
    }
    final typed = info?.type != null;
    final below = q.isNotEmpty && keep.any((k) => k.startsWith('$key/'));
    final open = expanded.contains(key) || below;
    final kids = open ? children(key) : const <NodeInfo>[];
    // A flow may run what needs read or write: never a config action.
    final acts = [
      for (final a in detail[key]?.actions ?? const IListConst<ActionInfo>([]))
        if (!a.staged) a,
    ];
    final hits = q.isEmpty || name.toLowerCase().contains(q);
    // A node may hold values, which only its list tells; so it opens until
    // its list answered empty and it has no action.
    final opens =
        section ||
        (info?.hasChildren ?? false) ||
        (info?.isAction ?? false) ||
        (!typed && !(listed.contains(key) && kids.isEmpty && acts.isEmpty));
    out.add(
      TreeNodeEntry(
        key: key,
        name: name,
        depth: depth,
        profile: info?.profile,
        opens: opens,
        open: open,
        used: used.contains(key),
        type: typed ? info!.type : null,
        writable:
            typed &&
            info!.writable != null &&
            treeSections.any((s) => key.startsWith('$root/$s/')),
        value: !typed
            ? null
            : switch (values[key]) {
                null => null,
                final v => valueText(
                  v.value,
                  choices: detail[key]?.choices.unlock ?? info!.choices.unlock,
                  unit: info!.unit,
                ),
              },
      ),
    );
    if (!open) {
      return;
    }
    for (final a in acts) {
      if (q.isEmpty || hits || a.name.toLowerCase().contains(q)) {
        out.add(
          TreeActionEntry(
            key: '$key/~act/${a.name}',
            name: labelOf(a.name, display: a.display),
            depth: depth + 1,
            node: key,
            action: a.name,
            inputs: a.params.length,
          ),
        );
      }
    }
    for (final k in kids) {
      walk(k.key, k.name, depth + 1, info: k);
    }
  }

  for (final s in treeSections) {
    walk('$root/$s', s, 0, section: true);
  }
  return out.lock;
}
