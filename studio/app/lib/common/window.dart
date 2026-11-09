import 'dart:async';
import 'dart:math' as math;

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/window/actions/set_window_bounds_action.dart';
import 'package:business/redux/window/actions/set_window_mode_action.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:ui/shell/window_bar.dart';
import 'package:ui/shell/window_controls.dart';
import 'package:window_manager/window_manager.dart';

/// Who draws the window's frame (owner decision 2026-11-09: no native
/// title bar on the desktop, docs/studio.md §7.1).
enum WindowFrame {
  /// The platform's own frame or none at all: the web, mobile, tests.
  native,

  /// macOS: the content runs under a transparent title bar and the native
  /// close, minimize and zoom buttons stay at the top left.
  macos,

  /// Windows and Linux: no title bar; the app draws the three buttons.
  controls,
}

WindowFrame get windowFrame => kIsWeb
    ? .native
    : switch (defaultTargetPlatform) {
        .macOS => .macos,
        .windows || .linux => .controls,
        _ => .native,
      };

/// The room macOS needs at the left of a top bar for its three buttons:
/// in the 52 pt title bar of `MainFlutterWindow` they end at x = 79.
const macosButtonsInset = 92.0;

/// The smallest window. Under 1176 wide the Explorer drops its inspector
/// (rail 76 + a workspace of 1100), and with it the action forms and the
/// point's settings; the log-in page keeps its hero beside the form from
/// 1080 and the link wizard its three columns from 1100.
const minimumWindowSize = Size(1180, 680);

/// The first window (the canvas boards are 1440 wide).
const _firstWindowSize = Size(1440, 900);

/// What a page's top bar keeps free and does for the window; the connector
/// of every page with a top area hands it to the page.
WindowBarVm windowBar({required bool fullScreen}) => switch (windowFrame) {
  .native => const WindowBarVm(),
  // Full screen has no buttons and nothing to move.
  .macos =>
    fullScreen
        ? const WindowBarVm()
        : const WindowBarVm(
            leading: macosButtonsInset,
            onDrag: dragWindow,
            onZoom: zoomWindow,
          ),
  .controls => WindowBarVm(
    trailing: WindowControls.width,
    onDrag: fullScreen ? null : dragWindow,
    onZoom: fullScreen ? null : zoomWindow,
  ),
};

/// The edges that resize a window without a title bar. Linux draws no
/// border at all then; Windows keeps its own at the left, right and bottom.
List<ResizeEdge>? get windowResizeEdges => defaultTargetPlatform == .windows
    ? const [.topLeft, .top, .topRight]
    : null;

void dragWindow() => unawaited(windowManager.startDragging());

void minimizeWindow() => unawaited(windowManager.minimize());

void closeWindow() => unawaited(windowManager.close());

/// Maximizes the window, or restores it (macOS: zoom).
void zoomWindow() => unawaited(_zoom());

Future<void> _zoom() async => await windowManager.isMaximized()
    ? windowManager.unmaximize()
    : windowManager.maximize();

/// Opens the desktop window without a title bar, where the user left it
/// and as large, and keeps the store's `window` slice in step with it.
Future<void> setUpWindow(Store<AppState> store) async {
  await windowManager.ensureInitialized();

  final saved = await _savedBounds(store.state);
  final options = WindowOptions(
    size: saved?.size ?? await _firstSize(),
    center: saved == null,
    minimumSize: minimumWindowSize,
    title: 'WYRM Studio',
    titleBarStyle: .hidden,
    // macOS keeps its buttons; elsewhere the app draws them.
    windowButtonVisibility: windowFrame == .macos,
  );

  unawaited(
    windowManager.waitUntilReadyToShow(options, () async {
      if (saved != null) {
        await windowManager.setBounds(saved);
      }
      await windowManager.show();
      await windowManager.focus();
      windowManager.addListener(_WindowWatcher(store));
      store.dispatchSync(
        SetWindowModeAction(
          maximized: await windowManager.isMaximized(),
          fullScreen: await windowManager.isFullScreen(),
        ),
      );
    }),
  );
}

/// The stored frame, when a screen still shows enough of it to find and
/// move the window (a second monitor may be gone since).
Future<Rect?> _savedBounds(AppState state) async {
  final w = SelectWindow(state);
  if (w.left == null || w.top == null || w.width == null || w.height == null) {
    return null;
  }
  final frame = Rect.fromLTWH(
    w.left!,
    w.top!,
    math.max(w.width!, minimumWindowSize.width),
    math.max(w.height!, minimumWindowSize.height),
  );
  try {
    for (final d in await screenRetriever.getAllDisplays()) {
      final origin = d.visiblePosition ?? Offset.zero;
      final seen = (origin & (d.visibleSize ?? d.size)).intersect(frame);
      if (seen.width >= 200 && seen.height >= 80) {
        return frame;
      }
    }
  } on Object {
    // No screen list: the default size, centred.
  }
  return null;
}

/// 1440 × 900, or what the screen has room for.
Future<Size> _firstSize() async {
  try {
    final d = await screenRetriever.getPrimaryDisplay();
    final room = d.visibleSize ?? d.size;
    return Size(
      math.max(
        minimumWindowSize.width,
        math.min(_firstWindowSize.width, room.width),
      ),
      math.max(
        minimumWindowSize.height,
        math.min(_firstWindowSize.height, room.height),
      ),
    );
  } on Object {
    return _firstWindowSize;
  }
}

/// Window events to the store: the mode at once, the frame when the user
/// stops moving or resizing.
final class _WindowWatcher with WindowListener {
  _WindowWatcher(this._store);

  final Store<AppState> _store;
  Timer? _settle;

  @override
  void onWindowMaximize() =>
      _store.dispatchSync(SetWindowModeAction(maximized: true));

  @override
  void onWindowUnmaximize() =>
      _store.dispatchSync(SetWindowModeAction(maximized: false));

  @override
  void onWindowEnterFullScreen() =>
      _store.dispatchSync(SetWindowModeAction(fullScreen: true));

  @override
  void onWindowLeaveFullScreen() =>
      _store.dispatchSync(SetWindowModeAction(fullScreen: false));

  @override
  void onWindowResize() => _later();

  @override
  void onWindowMove() => _later();

  void _later() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 400), () {
      unawaited(_keep());
    });
  }

  Future<void> _keep() async {
    // A maximized or full screen frame is not the one to come back to.
    if (await windowManager.isMaximized() ||
        await windowManager.isFullScreen() ||
        await windowManager.isMinimized()) {
      return;
    }
    final b = await windowManager.getBounds();
    _store.dispatchSync(
      SetWindowBoundsAction(
        left: b.left,
        top: b.top,
        width: b.width,
        height: b.height,
      ),
    );
  }
}
