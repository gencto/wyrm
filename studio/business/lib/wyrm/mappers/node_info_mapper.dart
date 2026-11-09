import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/node_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// A child of `list(parent)` (`~meta?view=list`) as a [NodeInfo].
NodeInfo nodeInfoOf(String parent, Child child) {
  final m = child.meta;
  final writable = switch (m.writable) {
    Writable.write => 'write',
    Writable.config => 'config',
    _ => null,
  };
  return NodeInfo(
    key: '$parent/${child.name}',
    name: child.name,
    display: m.displayName,
    type: m.ty?.wireName,
    unit: m.unit?.toString(),
    writable: writable,
    // spec 02 0.2.6: the triangle only where a child node exists
    hasChildren: m.hasNodes ?? false,
    hasHistory: m.hasHistory ?? false,
    isAction: m.actions?.isNotEmpty ?? false,
    profile: m.profileName,
    choices: (m.enumValues ?? const <String>[]).lock,
  );
}
