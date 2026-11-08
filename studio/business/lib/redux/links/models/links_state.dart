import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/link_info.dart';
import 'package:models/link_revision.dart';
import 'package:models/links_tab.dart';

part 'links_state.freezed.dart';

@freezed
abstract class LinksState with _$LinksState {
  const factory LinksState({
    @Default(IMapConst({})) IMap<String, LinkInfo> table,
    @Default(IListConst([])) IList<String> view,
    @Default(LinksTab.local) LinksTab tab,
    String? selectedLink,
    @Default(IListConst([])) IList<String> log,
    @Default(IListConst([])) IList<LinkRevision> revisions,
    String? version,
  }) = _LinksState;
}
