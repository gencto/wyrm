import 'dart:async';
import 'dart:math' as math;

import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../flows/actions/retrieve_block_types_action.dart';
import '../../flows/actions/retrieve_flows_action.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../nodes/actions/retrieve_nodes_action.dart';
import '../../site/actions/retrieve_sites_action.dart';
import 'set_preload_action.dart';

/// The welcome after a log-in (docs/design/specs/login.md §5): reads, one
/// after the other, what the first screens need, so that moving between the
/// tree, the flows and the links does not wait on the broker:
///
/// 0. the tree root — the live lists of `downstream` (opened in the tree),
///    `dataflows` and `storage` (listed, not opened), until each answered;
/// 1. the flows (`RetrieveFlowsAction`);
/// 2. the flow block catalogue (`RetrieveBlockTypesAction`, once a session);
/// 3. the links (`RetrieveLinksAction`);
/// 4. the sites of the switcher (`RetrieveSitesAction`).
///
/// Each step waits at most [perStep]; the whole welcome at most [atMost] and
/// at least [atLeast], so it neither flashes nor holds the user. A step that
/// does not finish in time goes on in the background; a step the deadline
/// reaches before it starts is started and not waited for. Every read is
/// quiet: a failure (rights the user does not have) opens no dialog, and the
/// screen that needs the data reads it again when it opens.
class OpenTreeAction extends Action {
  OpenTreeAction({
    this.atLeast = const Duration(milliseconds: 600),
    this.atMost = const Duration(seconds: 5),
    this.perStep = const Duration(seconds: 2),
  });

  final Duration atLeast;
  final Duration atMost;
  final Duration perStep;

  /// The tree sections read before Studio opens.
  static const sections = ['downstream', 'dataflows', 'storage'];

  /// How many steps the welcome shows.
  static const steps = 5;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final clock = Stopwatch()..start();
    final shown = Future<void>.delayed(atLeast);
    final late = <int>[];
    dispatchSync(SetPreloadAction(0));

    for (var i = 0; i < steps; i++) {
      final left = atMost - clock.elapsed;
      if (left <= Duration.zero) {
        // The deadline: what has not started loads in the background.
        // Started, not waited for: each read notifies when it lands. One
        // to five reads, those the deadline reached before they started.
        dispatchAll([
          for (var j = i; j < steps; j++) ?_action(j, root),
        ]);
        late.addAll([for (var j = i; j < steps; j++) j]);
        dispatchSync(SetPreloadAction(steps, late: late));
        break;
      }
      final wait = left < perStep ? left : perStep;
      final done = await _start(i, root).timeout(wait, onTimeout: () => false);
      if (!done) {
        late.add(i);
      }
      dispatchSync(SetPreloadAction(i + 1, late: late));
    }

    await shown;
    return null;
  }

  /// The read of step [i]; null for the block catalogue already read this
  /// session.
  ReduxAction<AppState>? _action(int i, String root) => switch (i) {
    0 => RetrieveNodesAction(preload: sections.sublist(1), quiet: true),
    1 => RetrieveFlowsAction(quiet: true),
    2 when flows.blockTypes.isNotEmpty => null,
    2 => RetrieveBlockTypesAction(quiet: true),
    3 => RetrieveLinksAction(quiet: true),
    _ => RetrieveSitesAction(quiet: true),
  };

  /// Starts step [i]; completes with whether it finished well. The tree
  /// (step 0) is done when each section has answered its list, which comes
  /// after its read returns.
  Future<bool> _start(int i, String root) async {
    final action = _action(i, root);
    if (action == null) {
      return true;
    }
    if (i != 0) {
      return _ok(dispatchAndWait(action));
    }
    // It opens the live lists and returns; the lists answer later.
    await dispatchAndWait(action);
    final keys = [for (final s in sections) '$root/$s'];
    try {
      await store.waitCondition(
        (_) => keys.every(nodes.listed.contains),
        timeoutMillis: math.max(1, atMost.inMilliseconds),
      );
      return true;
    } on TimeoutException {
      return false;
    } on StoreException {
      return false;
    }
  }

  static Future<bool> _ok(Future<ActionStatus> status) =>
      status.then((s) => s.isCompletedOk);
}
