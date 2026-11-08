import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled fonts under the family names `ui` uses, so a golden
/// shows the real type instead of the test font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = _fontsDir();
  final families = {
    'packages/ui/IBM Plex Sans': [
      'IBMPlexSans-Regular.ttf',
      'IBMPlexSans-Medium.ttf',
      'IBMPlexSans-SemiBold.ttf',
    ],
    'packages/ui/IBM Plex Mono': [
      'IBMPlexMono-Regular.ttf',
      'IBMPlexMono-Medium.ttf',
      'IBMPlexMono-SemiBold.ttf',
    ],
    'packages/ui/Unbounded': ['Unbounded.ttf'],
    // Material widgets that name no family fall back to Roboto.
    'Roboto': ['IBMPlexSans-Regular.ttf'],
  };
  for (final MapEntry(:key, :value) in families.entries) {
    final loader = FontLoader(key);
    for (final f in value) {
      final bytes = File('${dir.path}/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  await testMain();
}

/// `ui/assets/fonts`, from the package or from the workspace root.
Directory _fontsDir() {
  for (final p in ['assets/fonts', 'ui/assets/fonts']) {
    final d = Directory(p);
    if (d.existsSync()) {
      return d;
    }
  }
  throw StateError('ui/assets/fonts not found from ${Directory.current.path}');
}
