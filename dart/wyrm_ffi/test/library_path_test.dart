// Without the native library: where it is looked for.

import 'dart:io';

import 'package:test/test.dart';
import 'package:wyrm_ffi/wyrm_ffi.dart';

void main() {
  test('a given path wins, else WYRM_FFI_LIB, else the platform name', () {
    expect(WyrmFfi.libraryPath('/x/libwyrm_ffi.so'), '/x/libwyrm_ffi.so');
    final env = Platform.environment['WYRM_FFI_LIB'];
    final name = WyrmFfi.libraryPath();
    if (env != null) {
      expect(name, env);
    } else {
      expect(name, anyOf('libwyrm_ffi.dylib', 'libwyrm_ffi.so', 'wyrm_ffi.dll'));
    }
  });
}
