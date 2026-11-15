import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/decode/traffic_sample.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';
import '../../live/actions/watch_keys_action.dart';

/// One tick of `TrafficService`: the ring of router rates behind the
/// Overview chart (specs/system.md, Traffic; Studio-side).
///
/// It keeps the six rate keys of the site on screen watched while a session
/// is open — not only while System is shown — and adds a sample when the
/// broker has published a new one (one per metrics interval). The ring
/// holds at most one hour; another site starts another ring.
class SampleTrafficAction extends Action {
  /// The rate keys under `sys`, in the order of a traffic sample's fields.
  static const keys = [
    'messages_in_per_second',
    'messages_out_per_second',
    'frames_in_per_second',
    'frames_out_per_second',
    'data_in_per_second',
    'data_out_per_second',
  ];

  static const _keep = Duration(hours: 1);

  static List<String> _watch(String root) => [
    for (final k in keys) '$root/sys/$k',
  ];

  @override
  AppState? reduce() {
    final root = session.isAvailable ? site.root : null;
    final held = system.trafficRoot;
    if (root != held) {
      if (held != null) {
        dispatchSync(UnwatchKeysAction(_watch(held)));
      }
      if (root != null) {
        dispatchSync(WatchKeysAction(_watch(root)));
      }
      // `state` is the store's: it holds what the two dispatches wrote.
      return state.copyWith.system(
        trafficRoot: root,
        samples: const IListConst([]),
      );
    }
    if (root == null) {
      return null;
    }
    final sample = trafficSampleOf([
      for (final k in _watch(root)) (k, live.values[k]),
    ]).orWarn('traffic of $root');
    final last = system.samples.lastOrNull;
    if (sample == null || (last != null && !sample.time.isAfter(last.time))) {
      return null;
    }
    final from = sample.time.subtract(_keep);
    return state.copyWith.system(
      samples: system.samples
          .removeWhere((s) => s.time.isBefore(from))
          .add(sample),
    );
  }
}
