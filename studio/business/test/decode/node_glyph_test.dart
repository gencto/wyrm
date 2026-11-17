import 'package:business/wyrm/decode/node_glyph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/node_glyph.dart';

/// One glyph per node kind (board *Icons*), decoded from what the demo's
/// edge site lists (2026-11-08): profiles arrive as names
/// (`wy:df-connection`) or as interned codes that the client prints as
/// names (`{code: 6}` → `wy:link`).
void main() {
  const root = 'wy/edge';
  NodeGlyph glyph(String rel, {String? profile, bool value = false}) =>
      nodeGlyphOf(
        key: rel.isEmpty ? root : '$root/$rel',
        root: root,
        profile: profile,
        value: value,
      );

  test('the site and its sections', () {
    expect(glyph(''), NodeGlyph.site);
    for (final s in ['downstream', 'dataflows', 'storage', 'upstream']) {
      expect(glyph(s), NodeGlyph.section, reason: s);
    }
    expect(glyph('sys'), NodeGlyph.sys);
  });

  test('links, sites, flows by profile or by place', () {
    expect(glyph('downstream/modbus', profile: 'wy:link'), NodeGlyph.link);
    expect(glyph('downstream/modbus'), NodeGlyph.link);
    expect(glyph('downstream/plant', profile: 'wy:broker'), NodeGlyph.site);
    expect(glyph('upstream/central', profile: 'wy:broker'), NodeGlyph.site);
    expect(glyph('upstream/central'), NodeGlyph.site);
    expect(glyph('dataflows/ahu2_ctl', profile: 'wy:flow'), NodeGlyph.flow);
    expect(glyph('dataflows/ahu2_ctl'), NodeGlyph.flow);
  });

  test('driver levels: connection, device, a device model', () {
    expect(
      glyph('downstream/modbus/line1', profile: 'wy:df-connection'),
      NodeGlyph.connection,
    );
    expect(
      glyph('downstream/modbus/line1/ahu1', profile: 'wy:df-device'),
      NodeGlyph.device,
    );
    expect(
      glyph('downstream/modbus/line1/pm1', profile: 'schneider:pm5560'),
      NodeGlyph.device,
    );
  });

  test('folders, storage, values', () {
    expect(
      glyph('downstream/mock/g0', profile: 'wy:folder'),
      NodeGlyph.section,
    );
    expect(glyph('storage/line1', profile: 'wy:folder'), NodeGlyph.storage);
    expect(
      glyph('downstream/modbus/line1/status', value: true),
      NodeGlyph.point,
    );
    expect(
      glyph('dataflows/ahu2_ctl/nodes/temp_f', value: true),
      NodeGlyph.point,
    );
  });

  test('profiles, watches, what is under sys', () {
    expect(glyph('pub/schneider/pm5560'), NodeGlyph.profile);
    expect(
      glyph('sys/history/groups/g1/w1', profile: 'wy:watch'),
      NodeGlyph.watch,
    );
    expect(glyph('sys/links/modbus'), NodeGlyph.sys);
  });
}
