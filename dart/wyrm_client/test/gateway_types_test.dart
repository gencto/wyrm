// The decoders of the gateway's HTTP replies, and the typed gateway calls
// against a fake gateway: shapes as `crates/wyrm-gateway` sends them, then
// malformed ones.

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

Matcher _decodeError(String path) =>
    isA<DecodeError>().having((e) => e.path, 'path', path);

Matcher _malformed(String path) => isA<WyrmException>()
    .having((e) => e.status.known, 'status', Status.invalidMessage)
    .having((e) => e.message, 'message', contains(path));

// `Gateway::info` (lib.rs) over TLS, with a standby pair.
final _info = VMap({
  'site': const VStr('plant'),
  'version': const VStr('0.9.0'),
  'tls': const VBool(true),
  'role': const VStr('active'),
  'devices': VMap({
    'enabled': const VBool(true),
    'max_per_user': const VInt(5),
    'password_every_days': const VInt(30),
    'idle_lock_max_min': const VInt(15),
    'step_up': const VStr('config'),
    'allow_device_credential': const VBool(false),
  }),
  'min_studio': const VStr('1.0.0'),
  'up': VArray([const VStr('central')]),
  'ca_fp': const VStr('00112233445566778899aabbccddeeff'),
  'ca': VBytes(Uint8List.fromList([0x30, 0x82])),
  'pair': const VStr('10.0.0.2:8446'),
  'names': VArray([const VStr('gw.plant'), const VStr('10.0.0.1')]),
});

// `devices_of` (devices.rs): one active, one removed by an admin.
VMap _device({
  String platform = 'macos',
  String alg = 'es256',
  String state = 'active',
}) => VMap({
  'id': const VStr('0123456789abcdef0123456789abcdef'),
  'name': const VStr('Olena’s Mac'),
  'platform': VStr(platform),
  'alg': VStr(alg),
  'added': const VInt(100),
  'last_used': const VInt(200),
  'password_at': const VInt(150),
  'password_due_at': const VInt(150 + 30 * 86400),
  'state': VStr(state),
  'this': const VBool(true),
});

void main() {
  group('GatewayInfo', () {
    test('decodes what the gateway sends', () {
      final i = GatewayInfo.fromValue(_info);
      expect(i.site, 'plant');
      expect(i.tls, isTrue);
      expect(i.role, GatewayRole.active);
      expect(i.up, ['central']);
      expect(i.minStudio, '1.0.0');
      expect(i.pair, '10.0.0.2:8446');
      expect(i.ca, [0x30, 0x82]);
      expect(i.names, ['gw.plant', '10.0.0.1']);
      expect(i.devices.enabled, isTrue);
      expect(i.devices.idleLockMaxMin, 15);
      expect(i.devices.stepUp, StepUp.config);
    });

    test('optional fields may be absent; required ones may not', () {
      final minimal = VMap({..._info.v})
        ..v.remove('ca_fp')
        ..v.remove('ca')
        ..v.remove('pair')
        ..v.remove('names');
      final i = GatewayInfo.fromValue(minimal);
      expect((i.caFp, i.ca, i.pair), (null, null, null));
      expect(i.names, isEmpty);
      for (final k in [
        'site',
        'version',
        'tls',
        'role',
        'devices',
        'min_studio',
        'up',
      ]) {
        expect(
          () => GatewayInfo.fromValue(VMap({...minimal.v}..remove(k))),
          throwsA(_decodeError('GatewayInfo.$k')),
          reason: k,
        );
      }
      expect(
        () => GatewayInfo.fromValue(
          VMap({
            ...minimal.v,
            'devices': VMap({'enabled': const VBool(true)}),
          }),
        ),
        throwsA(_decodeError('GatewayInfo.devices.max_per_user')),
      );
      // a gateway that sends no policy: the defaults (device keys off)
      expect(
        const GatewayInfo(site: 's', version: '1', tls: false).devices,
        const DevicePolicy(),
      );
    });

    test('a malformed reply names the field', () {
      expect(
        () => GatewayInfo.fromValue(
          VMap({..._info.v, 'role': const VStr('primary')}),
        ),
        throwsA(_decodeError('GatewayInfo.role')),
      );
      expect(
        () => GatewayInfo.fromValue(VMap({..._info.v}..remove('site'))),
        throwsA(_decodeError('GatewayInfo.site')),
      );
      expect(
        () =>
            GatewayInfo.fromValue(VMap({..._info.v, 'tls': const VStr('yes')})),
        throwsA(_decodeError('GatewayInfo.tls')),
      );
      expect(
        () => GatewayInfo.fromValue(
          VMap({
            ..._info.v,
            'devices': VMap({
              ...switch (_info.v['devices']) {
                VMap(:final v) => v,
                _ => const <String, Value>{},
              },
              'step_up': const VStr('always'),
            }),
          }),
        ),
        throwsA(_decodeError('GatewayInfo.devices.step_up')),
      );
      expect(
        () => GatewayInfo.fromValue(const VStr('not a map')),
        throwsA(_decodeError('GatewayInfo')),
      );
    });

    test('freezed: equal by value, copyWith', () {
      final a = GatewayInfo.fromValue(_info);
      expect(GatewayInfo.fromValue(_info), a);
      expect(a.copyWith(role: GatewayRole.standby).role, GatewayRole.standby);
    });
  });

  group('GatewayDevice', () {
    test('decodes a record', () {
      final d = GatewayDevice.fromValue(_device());
      expect(d.platform, DevicePlatform.macos);
      expect(d.alg, DeviceAlg.es256);
      expect(d.state, GatewayDeviceState.active);
      expect(d.thisSession, isTrue);
      expect(d.passwordDueAt, 150 + 30 * 86400);
      final r = GatewayDevice.fromValue(
        VMap({
          ..._device(state: 'removed', alg: 'rs256', platform: 'windows').v,
          'removed_by': const VStr('user:admin'),
          'removed_at': const VInt(300),
        }),
      );
      expect(r.state, GatewayDeviceState.removed);
      expect(r.platform, DevicePlatform.windows);
      expect(r.alg, DeviceAlg.rs256);
      expect((r.removedBy, r.removedAt), ('user:admin', 300));
      expect(
        GatewayDevice.fromValue(_device(state: 'signed_out')).state,
        GatewayDeviceState.signedOut,
      );
    });

    test('a platform this client does not know is null, not an error', () {
      final d = GatewayDevice.fromValue(_device(platform: 'web'));
      expect(d.platform, isNull);
      final list = GatewayDevice.listFromValue(
        VArray([_device(), _device(platform: 'web')]),
      );
      expect(list.map((d) => d.platform), [DevicePlatform.macos, null]);
    });

    test('an unknown alg or state, or a missing id, is an error', () {
      expect(
        () => GatewayDevice.fromValue(_device(alg: 'ed25519')),
        throwsA(_decodeError('GatewayDevice.alg')),
      );
      expect(
        () => GatewayDevice.fromValue(
          VMap({..._device().v}..remove('last_used')),
        ),
        throwsA(_decodeError('GatewayDevice.last_used')),
      );
      expect(
        () => GatewayDevice.fromValue(_device(state: 'gone')),
        throwsA(_decodeError('GatewayDevice.state')),
      );
      expect(
        () => GatewayDevice.listFromValue(
          VArray([
            _device(),
            VMap({..._device().v}..remove('id')),
          ]),
        ),
        throwsA(_decodeError('GatewayDevice[1].id')),
      );
    });

    test('enums carry their wire names', () {
      expect(DevicePlatform.macos.wire, 'macos');
      expect(DevicePlatform.fromWire('mac'), isNull);
      expect(GatewayDeviceState.signedOut.wire, 'signed_out');
    });
  });

  group('GatewayUser and GatewayIdentity', () {
    test('users', () {
      final u = GatewayUser.listFromValue(
        VArray([
          VMap({
            'name': const VStr('ann'),
            'roles': VArray([const VStr('viewer')]),
            'disabled': const VBool(false),
            'devices': const VInt(1),
          }),
        ]),
      );
      expect(u.single, const GatewayUser('ann', ['viewer'], devices: 1));
      expect(
        () => GatewayUser.fromValue(
          VMap({
            'name': const VStr('ann'),
            'roles': VArray([const VInt(1)]),
          }),
        ),
        throwsA(_decodeError('GatewayUser.roles[0]')),
      );
    });

    test('identity: levels by name (the gateway) or by code', () {
      final me = GatewayIdentity.fromValue(
        VMap({
          'sub': const VStr('olena'),
          'roles': VArray([const VStr('operator')]),
          'grants': VArray([
            VMap({
              'k': const VStr('wy/plant/downstream/**'),
              'p': const VStr('write'),
            }),
            VMap({'k': const VStr('wy/plant/storage/**'), 'p': const VInt(2)}),
          ]),
          'max': const VStr('write'),
          'exp': const VInt(1000),
          'site': const VStr('plant'),
        }),
      );
      expect(me.max, Perm.write);
      expect(me.grants, [
        const Grant('wy/plant/downstream/**', Perm.write),
        const Grant('wy/plant/storage/**', Perm.read),
      ]);
      expect(
        () => GatewayIdentity.fromValue(
          VMap({
            'sub': const VStr('olena'),
            'roles': VArray(const []),
            'grants': VArray([
              VMap({'k': const VStr('x'), 'p': const VStr('mac')}),
            ]),
            'max': const VStr('write'),
            'exp': const VInt(1),
            'site': const VStr('plant'),
          }),
        ),
        throwsA(_decodeError('GatewayIdentity.grants[0].p')),
      );
    });

    test('a session never prints its token', () {
      final s = GatewaySession.fromValue(
        VMap({'session': const VStr('secret-token'), 'exp': const VInt(9)}),
      );
      expect(s.session, 'secret-token');
      expect('$s', isNot(contains('secret-token')));
    });
  });

  test('WyrmException.refusal is typed; an unknown code keeps its text', () {
    WyrmException err(String code) => WyrmException.fromError(
      VMap({
        'status': VInt(Status.permissionDenied.code),
        'message': const VStr('refused'),
        'code': VStr(code),
      }),
    );
    expect(err('password_due').refusal, GatewayRefusal.passwordDue);
    expect(err('confirm_required').refusal, GatewayRefusal.confirmRequired);
    expect(err('new_code').refusal, isNull);
    expect(err('new_code').code, 'new_code');
    expect(WyrmException.of(Status.timeout, 'slow').refusal, isNull);
  });

  group('WyrmGateway over a fake gateway', () {
    late HttpServer server;
    final bodies = <String, Value>{};
    final answers = <String, Value>{};

    setUp(() async {
      bodies.clear();
      answers.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final b = BytesBuilder();
        await for (final chunk in req) {
          b.add(chunk);
        }
        final bytes = b.takeBytes();
        final path = req.uri.path;
        bodies[path] = bytes.isEmpty ? const VNull() : Value.fromCbor(bytes);
        final answer = switch (path) {
          '/api/login' => VMap({
            'session': const VStr('s1'),
            'exp': const VInt(9),
          }),
          '/api/device/challenge' => VMap({
            'nonce': VBytes(Uint8List(56)),
            'exp': const VInt(60),
          }),
          '/api/devices' when req.method == 'POST' => VMap({
            'device': const VStr('d1'),
          }),
          _ => answers[path] ?? const VNull(),
        };
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'cbor')
          ..add(answer.toCbor());
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<WyrmGateway> login() => WyrmGateway.login(
      Uri.parse('http://127.0.0.1:${server.port}'),
      user: 'olena',
      password: 'pw',
    );

    test(
      'addDevice sends the platform and the alg by their wire names',
      () async {
        final gw = await login();
        final id = await gw.addDevice(
          site: 'plant',
          user: 'olena',
          name: 'Mac',
          platform: DevicePlatform.macos,
          alg: DeviceAlg.es256,
          publicKey: Uint8List(65),
          sign: (m) async => Uint8List(64),
        );
        gw.dispose();
        expect(id, 'd1');
        expect(bodies['/api/devices']?['platform'], const VStr('macos'));
        expect(bodies['/api/devices']?['alg'], const VStr('es256'));
      },
    );

    test(
      'devices and identity decode; a malformed list is invalid_message',
      () async {
        final gw = await login();
        answers['/api/devices'] = VArray([_device()]);
        expect((await gw.devices()).single.platform, DevicePlatform.macos);
        answers['/api/devices'] = VArray([_device(alg: 'nope')]);
        await expectLater(
          gw.devices(),
          throwsA(_malformed('GatewayDevice[0].alg')),
        );
        answers['/api/me'] = VMap({'sub': const VStr('olena')});
        await expectLater(
          gw.identity(),
          throwsA(_malformed('GatewayIdentity.roles')),
        );
        gw.dispose();
      },
    );

    test('info decodes; a reply that is not one is invalid_message', () async {
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      answers['/api/info'] = _info;
      expect((await WyrmGateway.gatewayInfo(base)).site, 'plant');
      answers['/api/info'] = VMap({'site': const VStr('plant')});
      await expectLater(
        WyrmGateway.gatewayInfo(base),
        throwsA(_malformed('GatewayInfo.version')),
      );
    });

    test('a login reply without a session is invalid_message', () async {
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        req.response
          ..statusCode = 200
          ..add(VMap({'exp': const VInt(1)}).toCbor());
        await req.response.close();
      });
      await expectLater(
        WyrmGateway.login(
          base.replace(port: server.port),
          user: 'u',
          password: 'p',
        ),
        throwsA(_malformed('GatewaySession.session')),
      );
    });
  });
}
