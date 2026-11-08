import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/package_info.dart';

part 'packages_state.freezed.dart';

@freezed
abstract class PackagesState with _$PackagesState {
  const factory PackagesState({
    @Default(IMapConst({})) IMap<String, PackageInfo> table,
    @Default(IListConst([])) IList<String> view,
  }) = _PackagesState;
}
