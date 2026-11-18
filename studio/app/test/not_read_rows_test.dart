import 'package:app/mappers/links_mappers.dart';
import 'package:app/mappers/sites_mappers.dart';
import 'package:business/wyrm/sites.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/quarantine_kind.dart';
import 'package:models/site_node.dart';
import 'package:models/site_pick.dart';

/// A waiting connection and a broker node Studio could not read stay on
/// the screens as "not read" (re-audit of #135, 11): never as a link, a
/// broker or nothing.
void main() {
  test('a waiting entry that was not read is neither a link nor a broker', () {
    const q = QuarantineEntry(
      cn: 'gw-9',
      node: 'gw-9',
      kind: QuarantineKind.notRead,
    );
    final row = q.data();
    expect((row.notRead, row.broker), (true, false));
    // no form of Authorize is made up for it
    expect(row.fields, isNull);

    const link = QuarantineEntry(cn: 'plc', node: 'plc');
    expect(link.data().notRead, isFalse);
    const broker = QuarantineEntry(
      cn: 'broker:plant',
      node: 'broker_plant',
      kind: QuarantineKind.broker,
    );
    expect((broker.data().notRead, broker.data().broker), (false, true));
  });

  test('a node of the map that was not read says so', () {
    const node = SiteMapNode(
      pick: SitePick(SiteNode.upstream, 'lab'),
      name: 'lab',
      notRead: true,
    );
    expect(node.data.notRead, isTrue);
    expect(
      const SiteMapNode(
        pick: SitePick(SiteNode.upstream, 'hq'),
        name: 'hq',
      ).data.notRead,
      isFalse,
    );
  });
}
