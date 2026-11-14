// The bytes a device signs (ADR 0050, last section): the same canonical CBOR as the
// gateway's `devices::tests::messages_are_canonical_cbor_arrays`.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('the login message matches the gateway test vector', () {
    final m = deviceLoginMessage(
      'plant',
      'https://gw:8443',
      'olena',
      'd1',
      Uint8List.fromList([7, 7, 7, 7]),
    );
    expect(
      hex(m),
      '86737779726d2d6465766963652d6c6f67696e2f3165706c616e746f68747470733a2f2f67773a3834'
      '3433656f6c656e616264314407070707',
    );
  });

  test('register and confirm messages carry their label first', () {
    final n = Uint8List(4);
    final r = deviceRegisterMessage(
      's',
      'https://g',
      'u',
      n,
      Uint8List.fromList([4, 1]),
    );
    final c = deviceConfirmMessage(
      's',
      'https://g',
      'u',
      'd',
      n,
      Uint8List(32),
    );
    expect(Value.fromCbor(r), isA<VArray>());
    expect(
      (Value.fromCbor(r) as VArray).v.first,
      const VStr('wyrm-device-register/1'),
    );
    expect(
      (Value.fromCbor(c) as VArray).v.first,
      const VStr('wyrm-device-confirm/1'),
    );
    expect((Value.fromCbor(c) as VArray).v.length, 7);
  });

  test('a refusal keeps its code, nonce and request', () {
    final e = WyrmException.fromError(
      VMap({
        'status': VInt(Status.permissionDenied.code),
        'message': const VStr('confirm this request'),
        'code': const VStr('confirm_required'),
        'nonce': VBytes(Uint8List(56)),
        'request': VBytes(Uint8List(32)),
      }),
    );
    expect(e.code, 'confirm_required');
    expect(e.nonce!.length, 56);
    expect(e.request!.length, 32);
    expect(e.status, StatusCode.of(Status.permissionDenied));
  });

  test('info and device rows parse', () {
    final i = GatewayInfo.of(
      VMap({
        'site': const VStr('plant'),
        'version': const VStr('0.1.0'),
        'tls': const VBool(true),
        'ca_fp': const VStr('68f7dfccc43c1853c1d268219414440b'),
        'names': VArray([const VStr('gw.plant.example')]),
        'devices': VMap({
          'enabled': const VBool(true),
          'step_up': const VStr('config'),
        }),
      }),
    );
    expect(i.site, 'plant');
    expect(i.devices.enabled, isTrue);
    expect(i.devices.stepUp, 'config');
    expect(i.names, ['gw.plant.example']);
    final d = GatewayDevice.of(
      VMap({
        'id': const VStr('ab'),
        'name': const VStr('Mac'),
        'platform': const VStr('macos'),
        'state': const VStr('removed'),
        'removed_by': const VStr('user:root'),
        'this': const VBool(true),
      }),
    );
    expect(
      (d.state, d.removedBy, d.thisSession),
      ('removed', 'user:root', true),
    );
  });
}
