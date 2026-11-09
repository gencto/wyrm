import 'package:business/wyrm/kinds.dart';
import 'package:business/wyrm/mappers/flow_value_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/node_kind.dart';

/// The frame rule of docs/design/specs/explorer.md "Frames by node kind",
/// on the nodes of the demo's `edge` site.
void main() {
  const root = 'wy/edge';
  NodeKind kind(
    String rel, {
    String? profile,
    List<String> actions = const [],
  }) => nodeKindOf(
    key: '$root/$rel',
    root: root,
    profile: profile,
    actions: actions,
  );

  test('sections are folders', () {
    for (final s in ['downstream', 'dataflows', 'storage', 'upstream']) {
      // `storage` and `dataflows` are links (`wy:link`) of their own.
      expect(kind(s, profile: 'wy:link'), NodeKind.folder, reason: s);
    }
  });

  test('links, connections and devices of a driver', () {
    expect(kind('downstream/modbus', profile: 'wy:link'), NodeKind.link);
    expect(kind('downstream/scheduler'), NodeKind.link);
    expect(
      kind('downstream/modbus/line1', profile: 'wy:df-connection'),
      NodeKind.connection,
    );
    expect(
      kind('downstream/modbus/line1/ahu1', profile: 'wy:df-device'),
      NodeKind.device,
    );
    // A modbus folder under a device: the device's point action.
    expect(
      kind('downstream/modbus/line1/ahu1/zone', actions: ['add_point']),
      NodeKind.device,
    );
    // A device model profile.
    expect(
      kind('downstream/bacnet/net/vav7', profile: 'acme:vav'),
      NodeKind.device,
    );
    // A group of the mock link: a plain node.
    expect(kind('downstream/mock/g0', profile: 'wy:node'), NodeKind.folder);
  });

  test('a link with import_dsa is still a link', () {
    expect(
      kind('downstream/modbus', profile: 'wy:link', actions: ['import_dsa']),
      NodeKind.link,
    );
  });

  test('flows, brokers and storage', () {
    expect(kind('dataflows/ahu2_ctl', profile: 'wy:flow'), NodeKind.flow);
    expect(kind('dataflows/ahu2_ctl'), NodeKind.flow);
    expect(
      kind('dataflows/ahu2_ctl/nodes', profile: 'wy:flow-node'),
      NodeKind.folder,
    );
    expect(kind('upstream/central', profile: 'wy:broker'), NodeKind.broker);
    expect(kind('downstream/plant', profile: 'wy:broker'), NodeKind.broker);
    expect(kind('storage/line1', profile: 'wy:node'), NodeKind.storage);
    expect(
      kind('storage/line1/test', actions: ['add_value']),
      NodeKind.storage,
    );
  });

  test("a flow's ~val as the demo's broker sends it", () {
    final f = flowSummaryOfValue('ahu2_ctl', {
      'deployed_by': 'user:admin@central',
      'since': 1794144199907560,
      'state': 0,
      'version': 2,
    });
    expect(f.running, isTrue);
    expect(f.version, 2);
    expect(f.deployedBy, 'user:admin@central');
    expect(f.problem, isNull);
    final bad = flowSummaryOfValue('x', {
      'state': 2,
      'version': 3,
      'error': 'no such key',
    });
    expect(bad.problem, 'no such key');
    expect(bad.running, isFalse);
    final none = flowSummaryOfValue('y', null);
    expect(none.draft, isTrue);
    expect(none.version, isNull);
  });
}
