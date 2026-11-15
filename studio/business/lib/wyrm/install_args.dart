import 'package:models/install_request.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// The arguments of [r] as `sys/links` takes them (docs/links.md §5): the
/// one place an install is put on the wire. `accept` goes only when given.
Value installArgsOf(InstallRequest r) => Value.from(switch (r) {
  InstallBuiltIn(:final id, :final driver, :final mode) => {
    'id': id,
    'driver': driver,
    'mode': mode.wire,
  },
  InstallRepository(:final name, :final package, :final accept) => {
    'name': name,
    'package': package,
    if (accept) 'accept': true,
  },
  InstallZip(:final name, :final zip, :final accept) => {
    'name': name,
    'zip': zip,
    if (accept) 'accept': true,
  },
  InstallUrl(:final name, :final url, :final accept) => {
    'name': name,
    'url': url,
    if (accept) 'accept': true,
  },
  InstallGit(:final name, :final url, :final ref, :final accept) => {
    'name': name,
    'url': url,
    'ref': ?ref,
    if (accept) 'accept': true,
  },
  InstallWasm(:final name, :final wasm, :final accept) => {
    'name': name,
    'wasm': wasm,
    if (accept) 'accept': true,
  },
  InstallBackup(:final upload, :final id, :final accept, :final passphrase) => {
    'upload': upload,
    'id': id,
    if (accept) 'accept': true,
    if (passphrase case final p? when p.isNotEmpty) 'passphrase': p,
  },
});
