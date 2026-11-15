import 'package:models/flow_permissions.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

/// `permissions` of a flow `~def` (spec 06, 0.2.32: `maxperm` is a code,
/// `0 none … 3 write`, or a name, `"write"`; `Perm.fromValue` reads both).
///
/// No `permissions` (null) and a map with no `maxperm` are a valid
/// "none named". A `permissions` that is not a map, or a `maxperm` that is
/// neither a known code nor a known name, is [Invalid] with the field.
Decoded<FlowPermissions> flowPermissionsOf(Value? v) => switch (v) {
  null || VNull() => const Valid(FlowPermissions()),
  VMap(:final v) => switch (v['maxperm']) {
    null || VNull() => const Valid(FlowPermissions()),
    final m => switch (Perm.fromValue(m)) {
      final p? => Valid(FlowPermissions(maxperm: p)),
      null => const Invalid('flow permissions', 'maxperm', 'not a level'),
    },
  },
  _ => const Invalid('flow permissions', '', 'not a map'),
};
