import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

/// Calls [onShow] while the workspace tab that holds it is the active one
/// and [onHide] when it stops being (or leaves the tree).
///
/// The tabs shell keeps every visited tab mounted, so a connector's
/// `onInit`/`onDispose` would keep a hidden tab's values subscribed; screens
/// watch their keys through this instead (ADR 0037 rule 5: only keys on
/// screen are subscribed).
class TabVisibility extends StatefulWidget {
  const TabVisibility({
    required this.onShow,
    required this.onHide,
    required this.child,
    super.key,
  });

  final VoidCallback onShow;
  final VoidCallback onHide;
  final Widget child;

  @override
  State<TabVisibility> createState() => _TabVisibilityState();
}

class _TabVisibilityState extends State<TabVisibility> {
  TabsRouter? _tabs;
  String? _route;
  var _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = TabsRouterScope.of(context)?.controller;
    if (tabs == null) {
      // No tabs shell around it (a page pumped on its own): on screen for
      // as long as it is in the tree.
      if (!_shown) {
        _shown = true;
        widget.onShow();
      }
      return;
    }
    _route = RouteData.of(context).name;
    if (!identical(tabs, _tabs)) {
      _tabs?.removeListener(_update);
      _tabs = tabs..addListener(_update);
    }
    _update();
  }

  void _update() {
    final active = _tabs?.current.name == _route;
    if (active && !_shown) {
      _shown = true;
      widget.onShow();
    } else if (!active && _shown) {
      _shown = false;
      widget.onHide();
    }
  }

  @override
  void dispose() {
    _tabs?.removeListener(_update);
    if (_shown) {
      widget.onHide();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
