import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/install_source.dart';
import 'package:models/link_mode.dart';
import 'package:models/package_check.dart';

part 'link_install_state.freezed.dart';

@freezed
abstract class LinkInstallState with _$LinkInstallState {
  const factory LinkInstallState({
    @Default(1) int step,
    InstallSource? source,
    String? item,
    String? broker,
    LinkMode? mode,
    String? name,
    @Default(false) bool acceptRights,
    @Default(IListConst([])) IList<PackageCheck> checks,
    String? message,
  }) = _LinkInstallState;
}
