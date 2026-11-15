import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/node_info.dart';
import 'package:wyrm_client/wyrm_client.dart' show TypeCode;

import '../../../wyrm/failures.dart';
import '../../../wyrm/points.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/resolve_stream_action.dart';
import 'retrieve_details_action.dart';
import 'retrieve_enum_names_action.dart';
import 'set_children_action.dart';

/// A live list of [parent] answered with [children] (the tree watch): the
/// table shows them at once ([SetChildrenAction]), a stream problem of its
/// site is resolved, then the meta of the points of the node on screen
/// (the table's columns) and the names of the enum values (a list carries
/// none) are read in parallel; this action ends when they have answered.
class ChildrenListedAction extends Action {
  ChildrenListedAction(this.parent, this.children);

  final String parent;
  final IList<NodeInfo> children;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(SetChildrenAction(parent, children));
    // A list answered: the streams of its site are open.
    if (siteOf(parent) case final site?
        when problems.items.any((e) => e.stream == site)) {
      dispatchSync(ResolveStreamAction(site));
    }
    await Future.wait(
      [
        ...newPointReads(state, parent, children),
        ...enumNameReads(children),
      ].map(dispatchAndWait),
    );
    return null;
  }

  /// The meta read of the points among [children] of [parent] when it is the
  /// node on screen.
  static List<Action> newPointReads(
    AppState s,
    String parent,
    Iterable<NodeInfo> children,
  ) => [
    if (parent == s.nodes.selectedNode)
      RetrieveDetailsAction([
        for (final c in children)
          if (isPoint(c)) c.key,
      ]),
  ];

  /// The names of the enum values among [children]: a list carries none.
  static List<Action> enumNameReads(Iterable<NodeInfo> children) {
    final enums = [
      for (final c in children)
        if (c.type == TypeCode.enum_ && c.choices.isEmpty) c.key,
    ];
    return [if (enums.isNotEmpty) RetrieveEnumNamesAction(enums)];
  }
}
