import 'package:app/common/window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/shell/window_bar.dart';
import 'package:ui/shell/window_controls.dart';

/// What each platform asks of a page's top bar (docs/studio.md §7.1).
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  WindowBarVm on(TargetPlatform platform, {bool fullScreen = false}) {
    debugDefaultTargetPlatformOverride = platform;
    return windowBar(fullScreen: fullScreen);
  }

  test('macOS keeps room for the native buttons and drags by the bar', () {
    final vm = on(.macOS);

    expect(windowFrame, WindowFrame.macos);
    expect(vm.leading, 92);
    expect(vm.trailing, 0);
    expect(vm.onDrag, isNotNull);
    expect(vm.onZoom, isNotNull);
  });

  test('macOS in full screen has no buttons and nothing to drag', () {
    expect(on(.macOS, fullScreen: true), const WindowBarVm());
  });

  test('Windows and Linux keep room for the buttons the app draws', () {
    for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
      final vm = on(p);

      expect(windowFrame, WindowFrame.controls);
      expect(vm.leading, 0);
      expect(vm.trailing, WindowControls.width);
      expect(vm.onDrag, isNotNull);
      // Full screen: the buttons stay (the way out), the drag goes.
      final full = on(p, fullScreen: true);
      expect(full.trailing, WindowControls.width);
      expect(full.onDrag, isNull);
    }
  });

  test('a phone has a frame of its own: the bar is left alone', () {
    for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(on(p), const WindowBarVm());
      expect(windowFrame, WindowFrame.native);
    }
  });

  test('the smallest window keeps the Explorer inspector', () {
    // Rail 76 + the 1100 from which the Explorer shows its inspector.
    expect(minimumWindowSize.width, greaterThanOrEqualTo(76 + 1100));
    expect(minimumWindowSize.height, greaterThanOrEqualTo(680));
  });
}
