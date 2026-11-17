import 'package:models/node_glyph.dart';

/// What the node [key] under the site [root] (`wy/<site>`) is drawn as in a
/// tree, a search result and a breadcrumb (board *Icons* "What a node
/// is"): decoded here, once, from the two wire strings that say it — the
/// node's place in the key space (spec 01) and its profile `is` (spec 02).
/// [value]: the node holds a value (it has a type), so it is a point.
///
/// The profile is an open set (a device model is `<vendor>:<model>`, a
/// driver names its own levels), so after the three profiles the broker
/// itself owns it is matched by what the SDK's driver framework writes
/// into it (`conn`, `device`, `watch`).
NodeGlyph nodeGlyphOf({
  required String key,
  required String root,
  String? profile,
  bool value = false,
}) {
  if (value) {
    return NodeGlyph.point;
  }
  if (key == root) {
    return NodeGlyph.site;
  }
  final rel = key.startsWith('$root/') ? key.substring(root.length + 1) : key;
  final parts = rel.split('/');
  final section = parts.first;
  final top = parts.length == 2;
  final p = profile ?? '';
  if (parts.length == 1) {
    return section == 'sys' ? NodeGlyph.sys : NodeGlyph.section;
  }
  return switch (p) {
    'wy:broker' => NodeGlyph.site,
    'wy:link' => NodeGlyph.link,
    'wy:flow' => NodeGlyph.flow,
    _ when section == 'upstream' && top => NodeGlyph.site,
    _ when section == 'downstream' && top => NodeGlyph.link,
    _ when section == 'dataflows' && top => NodeGlyph.flow,
    _ when section == 'pub' => NodeGlyph.profile,
    _ when p.contains('watch') => NodeGlyph.watch,
    _ when section == 'sys' => NodeGlyph.sys,
    _ when section == 'storage' => NodeGlyph.storage,
    _ when p.contains('conn') => NodeGlyph.connection,
    _ when p.contains('device') => NodeGlyph.device,
    // A device model profile is `<vendor>:<model>`.
    _ when p.contains(':') && !p.startsWith('wy:') => NodeGlyph.device,
    _ => NodeGlyph.section,
  };
}
