import 'package:freezed_annotation/freezed_annotation.dart';

import 'link_mode.dart';

part 'backup_link_facts.freezed.dart';

@freezed
abstract class BackupLinkFacts with _$BackupLinkFacts {
  /// The link of a link backup and where the backup was made: what the
  /// check of the file shows of it.
  const factory BackupLinkFacts({
    required String id,
    required LinkMode mode,
    required String driver,
    required String site,

    /// The version of the broker that made the backup.
    required String broker,
    required DateTime created,
  }) = _BackupLinkFacts;
}
