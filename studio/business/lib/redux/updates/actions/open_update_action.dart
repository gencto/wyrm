import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../models/updates_state.dart';

/// Opens the update sheet of [package] (ADR 0048 §1): its review, or with
/// [follow] the progress or result of its last update as the broker shows
/// it (`sys/packages/<name>/last_update`). [queue] holds the packages
/// updated after it (*Update all official*).
class OpenUpdateAction extends Action {
  OpenUpdateAction(
    this.package, {
    this.follow = false,
    this.queue = const [],
  });

  final String package;
  final bool follow;
  final List<String> queue;

  @override
  AppState reduce() => state.copyWith(
    updates: UpdatesState(
      package: package,
      view: follow ? 'follow' : 'review',
      queue: queue.lock,
      seenAt: -1,
    ),
  );
}
