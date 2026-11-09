import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:ui/shell/window_controls.dart';
import 'package:window_manager/window_manager.dart';

import '../common/window.dart';

/// The frame of a window that has no native one (Windows, Linux; owner
/// decision 2026-11-09, docs/studio.md §7.1): the minimize, maximize and
/// close buttons in the top right corner, over every page and dialog, and
/// the edges that resize the window. On macOS (native buttons), the web
/// and mobile it is the [child] alone.
class WindowControlsConnector extends StatelessWidget {
  const WindowControlsConnector({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => windowFrame != .controls
      ? child
      : StoreConnector<AppState, _Vm>(
          debug: this,
          vm: () => _Factory(this),
          builder: (context, vm) => Stack(
            children: [
              Positioned.fill(
                child: DragToResizeArea(
                  resizeEdgeSize: 6,
                  // Windows resizes by its own left, right and bottom
                  // borders; a hidden title bar takes the top one away.
                  enableResizeEdges: vm.filling ? const [] : windowResizeEdges,
                  child: child,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: WindowControls(
                  vm: WindowControlsVm(
                    maximized: vm.maximized,
                    minimize: S.current.windowMinimize,
                    maximize: S.current.windowMaximize,
                    restore: S.current.windowRestore,
                    close: S.current.windowClose,
                  ),
                  onMinimize: minimizeWindow,
                  onMaximize: zoomWindow,
                  onClose: closeWindow,
                ),
              ),
            ],
          ),
        );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, WindowControlsConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    maximized: window.maximized,
    filling: window.maximized || window.fullScreen,
    // The tooltips follow the language.
    locale: language.locale,
  );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({required this.maximized, required this.filling, required this.locale})
    : super(equals: [maximized, filling, locale]);

  final bool maximized;

  /// Maximized or full screen: no edge resizes the window.
  final bool filling;
  final String locale;
}
