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

void dragWindow() => appWindow.startDragging();

void minimizeWindow() => appWindow.minimize();

void closeWindow() => appWindow.close();

/// Maximizes the window, or restores it (macOS: zoom).
void zoomWindow() => appWindow.zoom();

/// The app's desktop window as the top bars and the window buttons use it.
abstract class AppWindow {
  bool get isMaximized;
  void maximize();
  void unmaximize();
  void minimize();
  void close();
  void startDragging();

  void zoom() => isMaximized ? unmaximize() : maximize();
}

/// The window the buttons act on: the native one, or what a test records.
@visibleForTesting
AppWindow appWindow = _native;

final _native = _NativeWindow();

/// The native window, from the moment [setUpWindow] or [setUpPlainWindow]
/// finds it; before that (the web, tests) every call does nothing.
final class _NativeWindow extends AppWindow {
  Window? _window;

  /// The `NSWindow`, `HWND` or `GtkWindow` behind [_window]. macOS gives a
  /// window closed with its red button and brought back from the Dock a new
  /// id (`AppDelegate`, nativeapi 0.6): the native object is what stays.
  int? _object;

  void attach(Window window) {
    _window = window;
    _object = window.nativeObject.address;
  }

  /// Whether [id] is the app's window; the one shown again under a new id
  /// becomes [_window]. Panels the app opens (a file picker) are windows of
  /// the app too and are not.
  bool owns(WindowId id) {
    if (id == _window?.id) {
      return true;
    }
    final w = WindowManager.instance.get(id);
    if (w == null || w.nativeObject.address != _object) {
      return false;
    }
    _window = w;
    return true;
  }

  @override
  bool get isMaximized => _window?.isMaximized ?? false;

  @override
  void maximize() => _window?.maximize();

  @override
  void unmaximize() => _window?.unmaximize();

  @override
  void minimize() => _window?.minimize();

  @override
  void close() => _window?.close();

  @override
  void startDragging() => _window?.startDragging();
}

/// Opens the desktop window without a title bar, where the user left it
/// and as large, and keeps the store's `window` slice in step with it.
void setUpWindow(Store<AppState> store) =>
    _whenShown((window) => _setUpFrameless(window, store));

void _setUpFrameless(Window window, Store<AppState> store) {
  _native.attach(window);
  // The style first: it sets the buttons back to its own default.
  window
    ..titleBarStyle = .hidden
    // macOS keeps its buttons; elsewhere the app draws them.
    ..isWindowControlButtonsVisible = windowFrame == .macos;
  _toNormal(window);
  final saved = _savedBounds(store.state);
  window
    ..minimumSize = minimumWindowSize.toNative()
    ..bounds = (saved ?? _centred(_firstSize())).toNative()
    ..title = 'WYRM Studio'
    ..show()
    ..focus();
  WindowManager.instance.addListener(_WindowWatcher(store).onEvent);
  store.dispatchSync(
    SetWindowModeAction(
      maximized: window.isMaximized,
      fullScreen: window.isFullScreen,
    ),
  );
}

/// Opens the desktop window for the start screen shown when the settings do
/// not open (docs/design/specs/errors.md §6): centred, with the system's
/// own title bar and buttons, since no store is there to keep a frame or to
/// draw them.
void setUpPlainWindow() => _whenShown(_setUpPlain);

void _setUpPlain(Window window) {
  _native.attach(window);
  _toNormal(window);
  window
    ..bounds = _centred(const Size(960, 720)).toNative()
    ..title = 'WYRM Studio'
    ..show()
    ..focus();
}

/// Runs [setUp] on the app's window: at once where nativeapi finds it
/// before it is shown (macOS: the nib's window; Linux: a realized
/// toplevel), else when it is first shown. The Windows runner shows its
/// window on the first frame, and nativeapi finds a window there only as
/// the active one.
void _whenShown(void Function(Window window) setUp) {
  const windows = WindowManager.instance;
  final window = windows.getCurrent();
  if (window != null) {
    setUp(window);
    return;
  }
  late final ListenerId waiting;
  waiting = windows.addListener((event) {
    if (event is! WindowCreatedEvent) {
      return;
    }
    final shown = windows.get(event.windowId);
    if (shown == null) {
      return;
    }
    windows.removeListener(waiting);
    setUp(shown);
  });
}

/// A window the platform restored full screen, maximized or minimized
/// comes back to a plain frame before it is given one.
void _toNormal(Window window) {
  if (window.isFullScreen) {
    window.isFullScreen = false;
  }
  if (window.isMaximized) {
    window.unmaximize();
  }
  if (window.isMinimized) {
    window.restore();
  }
}

/// The stored frame, when a screen still shows enough of it to find and
/// move the window (a second monitor may be gone since).
Rect? _savedBounds(AppState state) {
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
  for (final d in DisplayManager.instance.getAll()) {
    final seen = d.workArea.toRect().intersect(frame);
    if (seen.width >= 200 && seen.height >= 80) {
      return frame;
    }
  }
  return null;
}

/// 1440 × 900, or what the screen has room for.
Size _firstSize() {
  final d = DisplayManager.instance.getPrimary();
  if (d == null) {
    return _firstWindowSize;
  }
  final room = d.workArea.toRect().size;
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
}

/// A frame of [size] in the middle of the work area of the screen the
/// pointer is on (the primary one when none holds it).
Rect _centred(Size size) {
  const displays = DisplayManager.instance;
  final pointer = displays.getCursorPosition().toOffset();
  final d =
      displays.getAll().where((d) {
        final whole = d.position.toOffset() & d.size.toSize();
        return whole.contains(pointer);
      }).firstOrNull ??
      displays.getPrimary();
  if (d == null) {
    return Offset.zero & size;
  }
  return Alignment.center.inscribe(size, d.workArea.toRect());
}

/// Window events to the store: the mode at once, the frame when the user
/// stops moving or resizing.
final class _WindowWatcher {
  _WindowWatcher(this._store);

  final Store<AppState> _store;
  Timer? _settle;

  void onEvent(WindowEvent event) {
    if (!_native.owns(event.windowId)) {
      return;
    }
    switch (event) {
      case WindowMaximizedEvent():
        _store.dispatchSync(SetWindowModeAction(maximized: true));
      // One event for "no longer maximized" and "no longer minimized": the
      // window says which.
      case WindowRestoredEvent():
        _store.dispatchSync(
          SetWindowModeAction(maximized: _native.isMaximized),
        );
      case WindowEnteredFullScreenEvent():
        _store.dispatchSync(SetWindowModeAction(fullScreen: true));
      case WindowExitedFullScreenEvent():
        _store.dispatchSync(SetWindowModeAction(fullScreen: false));
      case WindowResizedEvent() || WindowMovedEvent():
        _later();
      default:
        break;
    }
  }

  void _later() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 400), _keep);
  }

  void _keep() {
    final window = _native._window;
    // A maximized or full screen frame is not the one to come back to.
    if (window == null ||
        window.isMaximized ||
        window.isFullScreen ||
        window.isMinimized) {
      return;
    }
    final b = window.bounds.toRect();
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
