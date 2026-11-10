import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/traffic_sample.dart';

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
  /// The rate keys under `sys`, in the order of [TrafficSample]'s fields.
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
    final values = [for (final k in _watch(root)) live.values[k]];
    if (values.any((v) => v == null || v.value is! num)) {
      return null;
    }
    final time = values
        .map((v) => v!.time)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final last = system.samples.lastOrNull;
    if (last != null && !time.isAfter(last.time)) {
      return null;
    }
    double n(int i) => (values[i]!.value! as num).toDouble();
    final from = time.subtract(_keep);
    return state.copyWith.system(
      samples: system.samples
          .removeWhere((s) => s.time.isBefore(from))
          .add(
            TrafficSample(
              time: time,
              messagesIn: n(0),
              messagesOut: n(1),
              framesIn: n(2),
              framesOut: n(3),
              dataIn: n(4),
              dataOut: n(5),
            ),
          ),
    );
  }
}
