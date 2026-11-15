import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  // CI's macOS runner draws text with slightly different anti-aliasing than
  // a developer's Mac (measured 2026-11-15: at most 0.34 % of the pixels of
  // a golden, macOS 26 runner against macOS 27). `GOLDEN_TOLERANCE` (a
  // fraction, set only by the `studio-goldens` CI job) lets that noise pass
  // while a broken layout — a missing panel, a moved block — still fails.
  // Without it, as on a developer's machine, goldens compare exactly.
  final tolerance = double.tryParse(
    Platform.environment['GOLDEN_TOLERANCE'] ?? '',
  );
  if (tolerance != null && goldenFileComparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      (goldenFileComparator as LocalFileComparator).basedir,
      tolerance,
    );
  }
  await testMain();
}

/// Passes a golden whose pixels differ by at most [tolerance] (a fraction).
final class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(Uri basedir, this.tolerance)
    : super(basedir.resolve('golden_test.dart'));

  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
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
