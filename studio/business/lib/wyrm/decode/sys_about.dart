import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

/// What System shows of a value node of `sys`: its description
/// (`attr.description`) and its unit (`~meta.unit`), each null when the
/// node has none.
typedef SysAbout = ({String? description, String? unit});

/// The [SysAbout] of a node's meta; a `description` that is not a text is
/// [Invalid].
Decoded<SysAbout> sysAboutOf(NodeMeta m) => switch (m.attr?['description']) {
  null || VNull() => Valid((description: null, unit: m.unit?.toString())),
  VStr(:final v) => Valid((description: v, unit: m.unit?.toString())),
  _ => const Invalid('sys node', 'description', 'not a text'),
};
