import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/links_page.dart';

import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

@RoutePage()
class LinksPageConnector extends StatelessWidget {
  const LinksPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => LinksPage(
      onTapLinkInstall: vm.onTapLinkInstall,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LinksPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    onTapLinkInstall: () => dispatch(GoAction.push(const LinkInstallRoute())),
  );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({required this.onTapLinkInstall}) : super(equals: const []);

  final void Function() onTapLinkInstall;
}
