import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart';

part 'flow_permissions.freezed.dart';

/// `permissions` of a flow definition (spec 06): the most the flow's
/// commands may do. Decoded once from the `~def` by
/// `business/lib/wyrm/decode/flow_permissions.dart`; the `token` stays in
/// the draft's `rest`, which writes the definition back as it came.
@freezed
abstract class FlowPermissions with _$FlowPermissions {
  const factory FlowPermissions({
    /// `maxperm`, given on the wire as a code (`3`) or a name (`"write"`,
    /// 0.2.32); null when the definition names none.
    Perm? maxperm,
  }) = _FlowPermissions;
}
