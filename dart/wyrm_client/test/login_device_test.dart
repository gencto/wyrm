// `loginAny` names the device key of this computer (ADR 0050 decision 6):
// a password login after a device fallback clears its `password_due`.
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

void main() {
  late HttpServer server;
  final bodies = <Value>[];

  setUp(() async {
    bodies.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final b = BytesBuilder();
      await for (final chunk in req) {
        b.add(chunk);
      }
      final bytes = b.takeBytes();
      bodies.add(bytes.isEmpty ? const VNull() : Value.fromCbor(bytes));
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('application', 'cbor')
        ..add(VMap(const {'session': VStr('s1'), 'exp': VInt(9)}).toCbor());
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri base() => Uri.parse('http://127.0.0.1:${server.port}');

  test('loginAny sends the device when one is named', () async {
    final gw = await WyrmGateway.loginAny(
      [base()],
      user: 'olena',
      password: 'pw',
      device: 'd1',
    );
    gw.dispose();
    expect(bodies.single['device'], const VStr('d1'));
    expect(bodies.single['user'], const VStr('olena'));
  });

  test('loginAny sends no device field without one', () async {
    final gw = await WyrmGateway.loginAny(
      [base()],
      user: 'olena',
      password: 'pw',
    );
    gw.dispose();
    expect(bodies.single['device'], isNull);
  });
}
