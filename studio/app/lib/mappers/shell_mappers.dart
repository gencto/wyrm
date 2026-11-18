import 'package:business/wyrm/shell.dart';
import 'package:models/change_op.dart';
import 'package:models/change_side.dart';
import 'package:models/site_choice.dart';
import 'package:models/site_relation.dart';
import 'package:models/step_up_deed.dart';
import 'package:models/workspace.dart';
import 'package:ui/models/change_words.dart';
import 'package:ui/shell/studio_frame.dart';

import 'icon_mappers.dart';
import 'rights_mappers.dart';

/// A workspace as the rail draws it.
extension WorkspaceTabOf on Workspace {
  WorkspaceTab get tab => switch (this) {
    Workspace.explorer => .explorer,
    Workspace.links => .links,
    Workspace.flows => .flows,
    Workspace.history => .history,
    Workspace.access => .access,
    Workspace.sites => .sites,
    Workspace.assistant => .assistant,
    Workspace.system => .system,
  };
}

/// A tab of the rail as the workspace it shows.
extension WorkspaceTabWorkspace on WorkspaceTab {
  Workspace get workspace => switch (this) {
    WorkspaceTab.explorer => .explorer,
    WorkspaceTab.links => .links,
    WorkspaceTab.flows => .flows,
    WorkspaceTab.history => .history,
    WorkspaceTab.access => .access,
    WorkspaceTab.sites => .sites,
    WorkspaceTab.assistant => .assistant,
    WorkspaceTab.system => .system,
  };
}

extension SiteChoiceVmOf on SiteChoice {
  SiteChoiceVm get vm => SiteChoiceVm(
    site: site,
    tie: switch (relation) {
      SiteRelation.self => .self,
      SiteRelation.downstream => .downstream,
      SiteRelation.upstream => .upstream,
    },
    via: via,
  );
}

extension ChangeOpTagOf on ChangeOp {
  ChangeOpTag get tag => switch (this) {
    ChangeOp.edit => .edit,
    ChangeOp.add => .add,
    ChangeOp.remove => .remove,
  };
}

extension ChangeSideVmOf on ChangeSide {
  ChangeSideVm get vm => switch (this) {
    ChangeSideText(:final text) => .text(text),
    ChangeSideNone() => const .none(),
    ChangeSideRev(:final rev, :final detail) => .rev(rev, detail: detail),
    ChangeSideFlag(:final on) => .flag(on: on),
    ChangeSideKeys(:final count) => .keys(count),
  };
}

extension StepUpDeedVmOf on StepUpDeed {
  StepUpDeedVm get vm => switch (this) {
    StepUpDeedSet(:final name) => .set(name),
    StepUpDeedAction(:final name) => .action(name),
    StepUpDeedChange(:final op, :final field, :final to) => .change(
      op: op.tag,
      field: field,
      to: to.vm,
    ),
    StepUpDeedAddUser(:final name) => .account(.addUser, name),
    StepUpDeedRemoveUser(:final name) => .account(.removeUser, name),
    StepUpDeedSetRoles(:final name) => .account(.setRoles, name),
    StepUpDeedSetPassword(:final name) => .account(.setPassword, name),
    StepUpDeedDisableUser(:final name) => .account(.disableUser, name),
    StepUpDeedEnableUser(:final name) => .account(.enableUser, name),
    StepUpDeedRemoveDevice() => const .account(.removeDevice),
  };
}

extension ReviewCardDataOf on ReviewCard {
  ReviewCardData get data => ReviewCardData(
    id: change.id,
    op: change.op.tag,
    key: change.key,
    field: change.field,
    from: change.from.vm,
    to: change.to.vm,
    level: change.level.access,
    have: have.access,
    allowed: allowed,
  );
}

extension SearchNodeVmOf on SearchNode {
  SearchNodeVm get vm => SearchNodeVm(key: key, title: title, icon: glyph.icon);
}
