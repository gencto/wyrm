import 'package:models/node_kind.dart';

/// The action that makes a node a device: the driver adds its points there
/// (a modbus folder under a device has it too, so it shows the same frame).
const pointActions = {'add_point'};

/// The kind of the node [key] under the site [root] (`wy/<site>`), from its
/// place, its profile (`is`) and its [actions] (docs/design/specs/
/// explorer.md "Frames by node kind"). It agrees with the tree's icon
/// (`AppIcon.nodeName`): a section is a folder, `upstream/<u>` and a
/// `wy:broker` are brokers, `downstream/<l>` is a link, `dataflows/<f>` a
/// flow, anything under `storage` storage.
NodeKind nodeKindOf({
  required String key,
  required String root,
  String? profile,
  Iterable<String> actions = const [],
}) {
  final rel = key.startsWith('$root/') ? key.substring(root.length + 1) : '';
  final parts = rel.isEmpty ? const <String>[] : rel.split('/');
  final p = profile ?? '';
  if (parts.length < 2) {
    return NodeKind.folder;
  }
  final section = parts.first;
  final top = parts.length == 2;
  if (p == 'wy:flow' || (section == 'dataflows' && top)) {
    return NodeKind.flow;
  }
  if (p == 'wy:broker' || (section == 'upstream' && top)) {
    return NodeKind.broker;
  }
  if (p == 'wy:link' || (section == 'downstream' && top)) {
    return NodeKind.link;
  }
  if (section == 'storage') {
    return NodeKind.storage;
  }
  if (p.contains('conn')) {
    return NodeKind.connection;
  }
  if (p.contains('device') ||
      // A device model profile is `<vendor>:<model>`.
      (p.contains(':') && !p.startsWith('wy:')) ||
      actions.any(pointActions.contains)) {
    return NodeKind.device;
  }
  return NodeKind.folder;
}
