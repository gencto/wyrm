import 'dart:typed_data';

import 'package:business/wyrm/install_args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/install_request.dart';
import 'package:models/link_install_call.dart';
import 'package:models/link_mode.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// Each install of Add a link is one typed request: its action of
/// `sys/links` and its arguments, put on the wire in one place.
void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  test('each request names its action', () {
    expect(
      [
        const InstallRequest.builtIn(
          id: 'a',
          driver: 'modbus',
          mode: LinkMode.embedded,
        ),
        const InstallRequest.repository(name: 'a', package: 'p', accept: false),
        InstallRequest.zip(name: 'a', zip: bytes, accept: false),
        const InstallRequest.url(name: 'a', url: 'https://x', accept: false),
        const InstallRequest.git(name: 'a', url: 'https://x', accept: false),
        InstallRequest.wasm(name: 'a', wasm: bytes, accept: false),
        const InstallRequest.backup(upload: 'u', id: 'a', accept: false),
      ].map((r) => r.call.wire),
      [
        'install',
        'install_repo',
        'install_zip',
        'install_url',
        'install_git',
        'install_wasm',
        'install_backup',
      ],
    );
    expect(LinkInstallCall.values, hasLength(7));
  });

  test('the arguments: accept only when given, the mode by its name', () {
    expect(
      installArgsOf(
        const InstallRequest.builtIn(
          id: 'modbus-2',
          driver: 'modbus',
          mode: LinkMode.process,
        ),
      ),
      Value.from({'id': 'modbus-2', 'driver': 'modbus', 'mode': 'process'}),
    );
    expect(
      installArgsOf(
        const InstallRequest.git(
          name: 'acme',
          url: 'https://git.example.com/acme.git',
          ref: 'v1.2.0',
          accept: true,
        ),
      ),
      Value.from({
        'name': 'acme',
        'url': 'https://git.example.com/acme.git',
        'ref': 'v1.2.0',
        'accept': true,
      }),
    );
    expect(
      installArgsOf(
        const InstallRequest.backup(
          upload: 'u1',
          id: 'meter',
          accept: false,
          passphrase: '',
        ),
      ),
      Value.from({'upload': 'u1', 'id': 'meter'}),
    );
  });
}
