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
        for (var j = i; j < steps; j++) {
          unawaited(_start(j, root));
          late.add(j);
        }
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

  /// Starts step [i]; completes with whether it finished well.
  Future<bool> _start(int i, String root) async {
    switch (i) {
      case 0:
        unawaited(
          dispatchAndWait(
            RetrieveNodesAction(preload: sections.sublist(1), quiet: true),
          ),
        );
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
      case 1:
        return _ok(dispatchAndWait(RetrieveFlowsAction(quiet: true)));
      case 2:
        return flows.blockTypes.isNotEmpty ||
            await _ok(
              dispatchAndWait(RetrieveBlockTypesAction(quiet: true)),
            );
      case 3:
        return _ok(dispatchAndWait(RetrieveLinksAction(quiet: true)));
      default:
        return _ok(dispatchAndWait(RetrieveSitesAction(quiet: true)));
    }
  }

  static Future<bool> _ok(Future<ActionStatus> status) =>
      status.then((s) => s.isCompletedOk);
}
