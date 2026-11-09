import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'watch_group.freezed.dart';

/// A watch group of the historian (`sys/history/<name>`).
@freezed
abstract class WatchGroup with _$WatchGroup {
  const factory WatchGroup({
    required String name,

    /// `None`, `Interval`, `All Data`, `Point Change`.
    @Default('') String loggingType,
    num? interval,
    num? flush,

    /// The watches' node names (`w1`) and the keys they record.
    @Default(IListConst([])) IList<String> watchIds,
    @Default(IListConst([])) IList<String> keys,
  }) = _WatchGroup;
}
