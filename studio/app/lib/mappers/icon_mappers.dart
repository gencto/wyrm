import 'package:models/error_kind.dart';
import 'package:models/node_glyph.dart';
import 'package:ui/indicators/app_icon.dart';

/// The icon of what a node is (board *Icons* "What a node is"): the same
/// in every tree, search result and breadcrumb.
extension NodeGlyphIcon on NodeGlyph {
  AppIcon get icon => switch (this) {
    .site => .nodeSite,
    .section => .nodeSection,
    .sys => .nodeSys,
    .link => .nodeLink,
    .flow => .nodeFlow,
    .profile => .nodeProfile,
    .watch => .nodeWatch,
    .storage => .nodeStorage,
    .connection => .nodeConn,
    .device => .nodeDevice,
    .point => .nodePoint,
  };
}

/// The icon of an error's kind (errors.md §1).
extension ErrorKindIcon on ErrorKind {
  AppIcon get icon => switch (this) {
    .rights => .errRights,
    .reach => .errReach,
    .input => .errInput,
    .busy => .errBusy,
    .gone => .errGone,
    .broker => .errBroker,
    .studio => .errStudio,
  };
}
