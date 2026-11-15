// `WyrmGateway.invoke` (`POST /api/invoke`) when the connection is cut while
// the body goes: a WyrmException that says so, not a SocketException.
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wyrm_client/wyrm_client.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/api/invoke') {
        // goes before it reads the body, as a gateway that refuses a
        // session that ended
        final s = await req.response.detachSocket(writeHeaders: false);
        s.destroy();
        return;
      }
      await req.drain<void>();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('application', 'cbor')
        ..add(VMap(const {'session': VStr('s1'), 'exp': VInt(9)}).toCbor());
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('a cut upload is a WyrmException with the reason', () async {
    final gw = await WyrmGateway.login(
      Uri.parse('http://127.0.0.1:${server.port}'),
      user: 'u',
      password: 'pw',
    );
    final big = VMap({'data': VBytes(Uint8List(8 << 20))});
    await expectLater(
      gw.invoke('wy/s/sys/backups', 'restore_part', big),
      throwsA(
        isA<WyrmException>()
            .having(
              (e) => e.status,
              'status',
              StatusCode.of(Status.disconnected),
            )
            .having((e) => e.message, 'message', contains('restore_part')),
      ),
    );
    gw.dispose();
  });
}
