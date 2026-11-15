import 'package:wyrm_core/wyrm_core.dart';

/// How a site of the switcher stands to the one logged into: itself, a
/// broker below it (`downstream/<d>`), or one above it (`upstream/<u>`).
/// [wire] is the word the site search shows beside it.
enum SiteRelation implements WireName {
  here('this'),
  downstream('downstream'),
  upstream('upstream');

  const SiteRelation(this.wire);

  @override
  final String wire;
}
