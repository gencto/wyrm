import 'dart:io';

import 'package:business/wyrm/discovery.dart';
import 'package:flutter_test/flutter_test.dart';

/// `/api/info` `min_studio` is compared with `studioRelease` (ADR 0050
/// decision 10): it is this app's version.
void main() {
  test('studioRelease is the version of app/pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(studioRelease, version);
  });
}
