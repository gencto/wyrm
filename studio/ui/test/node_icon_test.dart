import 'package:flutter_test/flutter_test.dart';
import 'package:ui/indicators/app_icon.dart';

/// One glyph per node kind (board *Icons*), from what the demo's edge site
/// lists (2026-11-08): profiles arrive as names (`wy:df-connection`) or as
/// interned codes that the client prints as names (`{code: 6}` → `wy:link`).
void main() {
  const root = 'wy/edge';
  String icon(String rel, {String? profile, String? type}) => AppIcon.nodeName(
    key: rel.isEmpty ? root : '$root/$rel',
    root: root,
    profile: profile,
    type: type,
  );

  test('the site and its sections', () {
    expect(icon(''), 'node_site');
    for (final s in ['downstream', 'dataflows', 'storage', 'upstream']) {
      expect(icon(s), 'node_section', reason: s);
    }
    expect(icon('sys'), 'node_sys');
  });

  test('links, sites, flows by profile or by place', () {
    expect(icon('downstream/modbus', profile: 'wy:link'), 'node_link');
    expect(icon('downstream/modbus'), 'node_link');
    expect(icon('downstream/plant', profile: 'wy:broker'), 'node_site');
    expect(icon('upstream/central', profile: 'wy:broker'), 'node_site');
    expect(icon('dataflows/ahu2_ctl', profile: 'wy:flow'), 'node_flow');
  });

  test('driver levels: connection, device, a device model', () {
    expect(
      icon('downstream/modbus/line1', profile: 'wy:df-connection'),
      'node_conn',
    );
    expect(
      icon('downstream/modbus/line1/ahu1', profile: 'wy:df-device'),
      'node_device',
    );
    expect(
      icon('downstream/modbus/line1/pm1', profile: 'schneider:pm5560'),
      'node_device',
    );
  });

  test('folders, storage, values', () {
    expect(icon('downstream/mock/g0', profile: 'wy:folder'), 'node_section');
    expect(icon('storage/line1', profile: 'wy:folder'), 'node_storage');
    expect(
      icon('downstream/modbus/line1/status', type: 'enum'),
      'node_point',
    );
    expect(
      icon('dataflows/ahu2_ctl/nodes/temp_f', type: 'dynamic'),
      'node_point',
    );
  });

  test('a point carries its type tag', () {
    expect(
      ['number', 'bool', 'enum', 'string', 'map'].map(AppIcon.typeTag),
      ['.0', '01', '≡', 'Aa', '{}'],
    );
  });
}
