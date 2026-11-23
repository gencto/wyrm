import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/barrier_overlay.dart';
import 'package:ui/overlays/no_internet_overlay.dart';

import '../common/blocking_actions.dart';

enum _Overlay { barrier, noInternetConnection }

class TopLevelPageConnector extends StatelessWidget {
  const TopLevelPageConnector({required this.child, this.blocking, super.key});

  final Widget? child;

  /// The actions the barrier covers the app for, in a test of the barrier;
  /// null (the app): [blockingActions].
  final List<Type>? blocking;

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => Stack(
      children: [
        child ?? const SizedBox.shrink(),
        if (vm.overlay == .barrier) const BarrierOverlay(),
        if (vm.overlay == .noInternetConnection) const NoInternetOverlay(),
      ],
    ),
  );
}

class _Factory extends VmFactory<AppState, TopLevelPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    overlay: waiting.any(connector.blocking ?? blockingActions)
        ? .barrier
        : (connectivity.isConnected ? null : .noInternetConnection),
  );
}

class _Vm extends Vm {
  _Vm({this.overlay}) : super(equals: [overlay]);

  final _Overlay? overlay;
}
