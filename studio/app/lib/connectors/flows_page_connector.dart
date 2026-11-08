import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/flows_page.dart';

import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

@RoutePage()
class FlowsPageConnector extends StatelessWidget {
  const FlowsPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => FlowsPage(
      onTapFlowEditor: vm.onTapFlowEditor,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, FlowsPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    onTapFlowEditor: (id) => dispatch(GoAction.push(FlowEditorRoute(id: id))),
  );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({required this.onTapFlowEditor}) : super(equals: const []);

  final void Function(String) onTapFlowEditor;
}
