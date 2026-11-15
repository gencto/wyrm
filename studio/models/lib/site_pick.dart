import 'package:freezed_annotation/freezed_annotation.dart';

import 'site_node.dart';

part 'site_pick.freezed.dart';

/// A node of the Sites map: what it is and its name (a site, a link, the
/// node of a quarantine entry).
@freezed
abstract class SitePick with _$SitePick {
  const factory SitePick(SiteNode node, String name) = _SitePick;
}
