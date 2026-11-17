import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/catalog_category.dart';
import 'package:models/catalog_item.dart';
import 'package:models/install_field.dart';
import 'package:models/install_path.dart';
import 'package:models/install_phase.dart';
import 'package:models/install_source.dart';
import 'package:models/install_step.dart';
import 'package:models/install_target.dart';
import 'package:models/link_mode.dart';
import 'package:models/package_check.dart';
import 'package:models/package_method.dart';
import 'package:models/requested_right.dart';

part 'link_install_state.freezed.dart';

@freezed
abstract class LinkInstallState with _$LinkInstallState {
  const factory LinkInstallState({
    @Default(InstallStep.choose) InstallStep step,
    InstallSource? source,
    String? item,
    String? broker,
    LinkMode? mode,
    String? name,
    @Default(false) bool acceptRights,
    @Default(IListConst([])) IList<PackageCheck> checks,
    String? message,
    @Default(InstallPath.official) InstallPath path,

    /// The category of the official list on screen; null: all of them.
    CatalogCategory? category,
    String? query,
    InstallPhase? phase,
    String? manifest,

    /// What the checked package asks for; null when it asks for nothing.
    IList<RequestedRight>? rights,
    @Default(IListConst([])) IList<CatalogItem> catalog,
    @Default(IListConst([])) IList<InstallTarget> targets,
    @Default(PackageMethod.zip) PackageMethod method,
    InstallField? refusedField,
    String? refusedSaid,
  }) = _LinkInstallState;
}
