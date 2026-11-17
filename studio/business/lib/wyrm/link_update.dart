import 'package:models/package_info.dart';
import 'package:models/restore_point.dart';
import 'package:models/update_next.dart';
import 'package:models/update_result.dart';
import 'package:models/update_stage.dart';

import 'rights.dart';

/// A restore point of one link (`sys/links/<id>/restore_points`).
final class LinkPoint {
  const LinkPoint(this.link, this.point);

  final String link;
  final RestorePoint point;
}

/// What the update sheet of one package is made of (boards `LinkUpdate*`,
/// spec `docs/design/specs/updates-backups.md` §1), and what it decides:
/// its stage, its primary button, whether a rollback is offered.
final class LinkUpdate {
  const LinkUpdate({
    required this.package,
    required this.links,
    required this.follow,
    this.official = true,
    this.title,
    this.summary,
    this.takePoint = true,
    this.autoRollback = true,
    this.acceptNew = false,
    this.asks,
    this.said,
    this.busy = false,
    this.rollingBack = false,
    this.seenAt = -1,
    this.points = const [],
    this.queue = const [],
    this.reason,
  });

  /// The package with its live values.
  final PackageInfo package;

  /// The links that run it, by id.
  final List<String> links;

  /// The sheet follows `last_update` (progress or result), else it is the
  /// review.
  final bool follow;

  /// The repository lists it; else it is custom (updated from a file).
  final bool official;

  /// The `title` and `summary` of its catalog row.
  final String? title;
  final String? summary;
  final bool takePoint;
  final bool autoRollback;
  final bool acceptNew;

  /// The broker's answer of an update it did not make: the rights the new
  /// version asks for.
  final String? asks;

  /// What the broker answered to the update or the rollback.
  final String? said;

  /// The update action is in flight.
  final bool busy;
  final bool rollingBack;

  /// `last_update.at` before the action of this sheet; negative when the
  /// sheet only shows what is there.
  final int seenAt;

  /// The restore points of the links, newest first.
  final List<LinkPoint> points;

  /// The packages updated after this one.
  final List<String> queue;

  /// Why the user may not update (`config` on `sys/links`), or null.
  final Lack? reason;

  UpdateStage get stage {
    if (!follow) {
      return .review;
    }
    final r = package.lastUpdate;
    if (busy) {
      return .progress;
    }
    if (r == null) {
      // No update was ever made and none was started from this sheet
      // (`seenAt` is -1 then): only the restore points are there to show.
      return seenAt == -1 ? .points : .progress;
    }
    return r.at == seenAt || r.result == UpdateResult.checking
        ? .progress
        : .result;
  }

  /// The broker answered the update and checks it: the steps before the
  /// check are done.
  bool get answered {
    final r = package.lastUpdate;
    return !busy &&
        r != null &&
        r.at != seenAt &&
        r.result == UpdateResult.checking;
  }

  /// The result offers the rollback first: the update failed, or ran with
  /// nodes gone, and a version is kept.
  bool get offersRollBack {
    final r = package.lastUpdate;
    return package.previous != null &&
        r != null &&
        (r.result == UpdateResult.failed ||
            (r.result != UpdateResult.rolledBack && r.gone > 0));
  }

  /// A kept version can be rolled back to by this user.
  bool get canRollBack => package.previous != null && reason == null;

  /// What the primary button does at this stage; null when it does
  /// nothing (progress, the restore points alone).
  UpdateNext? get next => switch (stage) {
    .review => official ? .update : .file,
    .progress || .points => null,
    .result when offersRollBack => .rollback,
    .result when package.lastUpdate?.result == UpdateResult.rolledBack => .log,
    .result => .open,
  };
}
