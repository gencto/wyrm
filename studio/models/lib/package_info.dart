import 'package:freezed_annotation/freezed_annotation.dart';

import 'update_report.dart';

part 'package_info.freezed.dart';

@freezed
abstract class PackageInfo with _$PackageInfo {
  /// A package installed under `sys/packages/<name>`.
  const factory PackageInfo({
    required String name,
    @Default('') String version,

    /// `process` or `wasm`.
    @Default('process') String kind,
    String? source,
    String? sha256,

    /// The version in the repository index; empty for a custom package
    /// (ADR 0048 §1).
    @Default('') String latest,
    @Default(false) bool updateAvailable,

    /// The update to [latest] changes the store format.
    @Default(false) bool changesState,

    /// The store format the installed version writes.
    @Default(1) int state,

    /// The version kept for a rollback; null when none is kept.
    String? previous,

    /// Until when [previous] is kept, Unix seconds.
    @Default(0) int keepUntil,

    /// Going back to [previous] crosses a store format change.
    @Default(false) bool previousChangesState,

    /// The last update or rollback; null before the first one.
    UpdateReport? lastUpdate,
  }) = _PackageInfo;
}
