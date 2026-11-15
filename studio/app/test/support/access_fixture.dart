import 'dart:typed_data';

import 'package:wyrm_client/wyrm_client.dart';

import 'screen_app.dart';

/// What the gateway and the broker hold for Access on `plant`: two users
/// (one disabled), the grants of `sys ▸ get_permissions`, the audit tail
/// and ivan's two devices (one an administrator removed).
void accessBroker(ScreenApp app) {
  app.session.userTable
    ..['olena'] = const GatewayUser('olena', ['admin'], devices: 2)
    ..['ivan'] = const GatewayUser(
      'ivan',
      ['operator', 'engineer'],
      disabled: true,
    );
  app.api
    ..invokes['$plant/sys ▸ get_permissions'] = [
      Value.from([
        {
          'subject': 'admin',
          'path': 'wy/{site}/**',
          'level': 'config',
          'source': 'gateway',
        },
        {
          'subject': 'operator',
          'path': 'wy/{site}/downstream/**',
          'level': 'write',
          'source': 'gateway',
        },
        {
          'subject': 'link:modbus',
          'path': 'wy/plant/downstream/modbus/**',
          'level': 'config',
          'source': 'link',
        },
      ]),
    ]
    ..invokes['$plant/sys/audit ▸ tail'] = [
      Value.from([
        {
          'time': '2026-11-12T02:01:40Z',
          'who': 'user:olena',
          'op': 'set',
          'key': 'downstream/plc1/sp',
          'result': 'ok',
        },
        {
          'time': '2026-11-12T02:03:00Z',
          'subject': 'link:agent',
          'event': 'invoke',
          'target': 'downstream/modbus',
          'action': 'restart',
          'status': 'refused',
        },
      ]),
    ]
    ..invokes['$plant/sys ▸ update_permissions'] = const [VNull()];
  app.session.gateway.records
    ..['d1'] = FakeDeviceRecord('d1', 'ivan', 'MacBook · Studio', Uint8List(0))
    ..['d2'] = (FakeDeviceRecord('d2', 'ivan', 'Pixel · Studio', Uint8List(0))
      ..state = 'removed'
      ..removedBy = 'user:ivan');
}
