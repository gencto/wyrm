import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile_info.freezed.dart';

/// A device profile the admin publishes at `pub/<name>`.
@freezed
abstract class ProfileInfo with _$ProfileInfo {
  const factory ProfileInfo({
    /// `<vendor>:<model>`.
    required String name,

    /// The points its `~meta` lists; null when it could not be read.
    int? points,
  }) = _ProfileInfo;
}
