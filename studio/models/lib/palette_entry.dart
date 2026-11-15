import 'block_type.dart';

/// What the flow editor's palette offers to place on the canvas
/// (flow-editor.md §2, §18, §20): a block of the engine's catalogue or of
/// the flow's own custom blocks, a block of the site's library, a point of
/// the Tree tab (read, or written when dropped as `Write`), or an action
/// of a node of the tree.
sealed class PaletteEntry {
  const PaletteEntry();
}

/// A type of the catalogue, or a custom block of the flow
/// ([CustomType]).
final class EnginePick extends PaletteEntry {
  const EnginePick(this.type);

  final BlockType type;

  @override
  bool operator ==(Object other) => other is EnginePick && other.type == type;

  @override
  int get hashCode => type.hashCode;

  @override
  String toString() => 'EnginePick($type)';
}

/// A block of the site's library, by its name: the flow copies it first.
final class LibraryPick extends PaletteEntry {
  const LibraryPick(this.name);

  final String name;

  @override
  bool operator ==(Object other) => other is LibraryPick && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'LibraryPick($name)';
}

/// A value point of the tree, by its full key (`wy/<site>/…`).
final class PointPick extends PaletteEntry {
  const PointPick(this.key);

  final String key;

  @override
  bool operator ==(Object other) => other is PointPick && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'PointPick($key)';
}

/// Action [action] of the tree's node [node] (a full key).
final class ActionPick extends PaletteEntry {
  const ActionPick(this.node, this.action);

  final String node;
  final String action;

  @override
  bool operator ==(Object other) =>
      other is ActionPick && other.node == node && other.action == action;

  @override
  int get hashCode => Object.hash(node, action);

  @override
  String toString() => 'ActionPick($node, $action)';
}
