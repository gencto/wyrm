import 'package:business/wyrm/rights.dart';
import 'package:ui/indicators/level_badge.dart';
import 'package:ui/models/disabled.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

/// A level of the spec as `ui` words it.
extension PermAccess on Perm {
  AccessLevel get access => switch (this) {
    Perm.none => .none,
    Perm.list => .list,
    Perm.read => .read,
    Perm.write => .write,
    Perm.config => .config,
  };
}

/// What the user lacks, as the reason a control is disabled.
extension LackDisabled on Lack {
  Disabled get disabled => NeedsLevel(level.access, path);
}
