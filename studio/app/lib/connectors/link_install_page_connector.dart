import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/link_install/actions/back_install_step_action.dart';
import 'package:business/redux/link_install/actions/change_install_answers_action.dart';
import 'package:business/redux/link_install/actions/choose_install_source_action.dart';
import 'package:business/redux/link_install/actions/continue_install_action.dart';
import 'package:business/redux/link_install/actions/open_link_install_action.dart';
import 'package:business/redux/link_install/actions/set_accept_rights_action.dart';
import 'package:business/redux/link_install/actions/set_broker_action.dart';
import 'package:business/redux/link_install/actions/set_category_action.dart';
import 'package:business/redux/link_install/actions/set_git_ref_action.dart';
import 'package:business/redux/link_install/actions/set_item_action.dart';
import 'package:business/redux/link_install/actions/set_method_action.dart';
import 'package:business/redux/link_install/actions/set_mode_action.dart';
import 'package:business/redux/link_install/actions/set_name_action.dart';
import 'package:business/redux/link_install/actions/set_package_url_action.dart';
import 'package:business/redux/link_install/actions/set_query_action.dart';
import 'package:business/redux/link_install/actions/set_step_action.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/install_path.dart';
import 'package:models/install_phase.dart';
import 'package:models/install_step.dart';
import 'package:ui/models/link_run_mode.dart';
import 'package:ui/pages/link_install_page.dart';

import '../common/install_file_actions.dart';
import '../common/window.dart';
import '../mappers/link_install_mappers.dart';
import '../navigation/go_action.dart';
import '../navigation/show_installed_link_action.dart';

/// Add a link (docs/studio.md §7.3): the connector reads the selectors of
/// `LinkInstallScreen`, maps the domain through
/// `app/lib/mappers/link_install_mappers.dart` into typed values
/// (`LinkInstallPage` words them) and starts one action per intent.
///
/// A link backup's file and its passphrase are this widget's own
/// ([HeldBackup]): they go to the actions that read them, never to the
/// store.
@RoutePage()
class LinkInstallPageConnector extends StatefulWidget {
  const LinkInstallPageConnector({super.key});

  @override
  State<LinkInstallPageConnector> createState() =>
      _LinkInstallPageConnectorState();
}

class _LinkInstallPageConnectorState extends State<LinkInstallPageConnector> {
  final _held = HeldBackup();

  @override
  void dispose() {
    unawaited(_held.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: widget,
    vm: () => _Factory(widget, _held),
    onInit: (store) => store.dispatch(OpenLinkInstallAction()),
    builder: (context, vm) => LinkInstallPage(
      vm: vm.page,
      onClose: vm.onClose,
      onFrom: vm.onFrom,
      onCategory: vm.onCategory,
      onQuery: vm.onQuery,
      onItem: vm.onItem,
      onMethod: vm.onMethod,
      onPickFile: vm.onPickFile,
      onUrl: vm.onUrl,
      onRef: vm.onRef,
      onBroker: vm.onBroker,
      onMode: vm.onMode,
      onName: vm.onName,
      onAccept: vm.onAccept,
      onSecret: vm.onSecret,
      onResult: vm.onResult,
      onStep: vm.onStep,
      onBack: vm.onBack,
      onNext: vm.onNext,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LinkInstallPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector, this._held);

  final HeldBackup _held;

  @override
  _Vm fromStore() {
    final li = linkInstall;
    final step = installStep;
    final first = step == installSteps.first;
    final last = step == InstallStep.result;
    final item = installItem;
    return _Vm(
      page: LinkInstallVm(
        window: windowBar(fullScreen: window.fullScreen),
        site: site.viewed ?? '',
        from: li.path.ui,
        steps: [for (final s in installSteps) s.ui],
        step: step.ui,
        itemName: item?.name,
        itemBuiltIn: item?.builtIn ?? true,
        sourceName: installSourceName,
        broker: installBroker,
        mode: installMode.ui,
        name: li.name,
        checkFailed: installCheckFailed,
        needsRights: installNeedsRights,
        offersAccept: installOffersAccept,
        accepted: li.acceptRights,
        categories: installCategories,
        category: li.category,
        query: li.query,
        cards: [
          for (final c in installShownCatalog)
            c.card(selected: c.id == li.item),
        ],
        method: li.method.ui,
        file: installFileName,
        url: installUrl,
        ref: installRef,
        refused: li.refusedField?.ui,
        refusedSaid: li.refusedSaid,
        checks: [for (final c in li.checks) c.row],
        manifest: li.manifest,
        brokers: [
          for (final t in li.targets) t.broker(here: t.site == site.viewed),
        ],
        modes: [for (final m in installModes) m.ui],
        nameError: installNameProblem?.ui,
        replaces: installReplaces,
        rights: [...?li.rights?.map((r) => r.ui)],
        result: li.phase?.ui,
        message: li.message,
        hold: installBlock?.ui,
        configReason: installConfigReason,
        canPickStep: !last,
      ),
      onClose: () => dispatch(GoAction.pop()),
      onFrom: (f) => dispatch(ChooseInstallSourceAction(f.domain)),
      onCategory: (c) => dispatch(SetCategoryAction(c)),
      onQuery: (q) => dispatch(SetQueryAction(q)),
      onItem: (id) => dispatch(SetItemAction(id)),
      onMethod: (m) => dispatch(SetMethodAction(m.domain)),
      onPickFile: li.path == InstallPath.backup
          ? () => dispatch(PickLinkBackupAction(_held))
          : () => dispatch(PickPackageFileAction(li.method)),
      onUrl: (u) => dispatch(SetPackageUrlAction(u)),
      onRef: (r) => dispatch(SetGitRefAction(r)),
      onBroker: (b) => dispatch(SetBrokerAction(b)),
      onMode: (m) => dispatch(SetModeAction(m.domain)),
      onName: (n) => dispatch(SetNameAction(n)),
      onAccept: (on) => dispatch(SetAcceptRightsAction(on)),
      onSecret: (p) => _held.passphrase = p,
      onResult: (a) => dispatch(switch (a) {
        InstallResultAction.explorer => ShowInstalledLinkAction(
          installedLinkKey,
        ),
        InstallResultAction.links => GoAction.pop(),
        InstallResultAction.again => ChooseInstallSourceAction(
          InstallPath.official,
        ),
        InstallResultAction.back => ChangeInstallAnswersAction(),
      }),
      onStep: last ? null : (s) => dispatch(SetStepAction(s.domain)),
      onBack: first
          ? () => dispatch(GoAction.pop())
          : (last && li.phase == InstallPhase.done
                ? null
                : () => dispatch(BackInstallStepAction())),
      onNext: last
          ? null
          : () => dispatch(
              ContinueInstallAction(
                passphrase: _held.passphrase,
                file: _held.file,
              ),
            ),
    );
  }
}

/// What Add a link draws ([page], compared) and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.page,
    required this.onClose,
    required this.onFrom,
    required this.onCategory,
    required this.onQuery,
    required this.onItem,
    required this.onMethod,
    required this.onPickFile,
    required this.onUrl,
    required this.onRef,
    required this.onBroker,
    required this.onMode,
    required this.onName,
    required this.onAccept,
    required this.onSecret,
    required this.onResult,
    required this.onStep,
    required this.onBack,
    required this.onNext,
  }) : super(
         equals: [page, onStep != null, onBack != null, onNext != null],
       );

  final LinkInstallVm page;
  final VoidCallback onClose;
  final ValueChanged<InstallFrom> onFrom;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onQuery;
  final ValueChanged<String> onItem;
  final ValueChanged<InstallMethod> onMethod;
  final VoidCallback onPickFile;
  final ValueChanged<String?> onUrl;
  final ValueChanged<String?> onRef;
  final ValueChanged<String> onBroker;
  final ValueChanged<LinkRunMode> onMode;
  final ValueChanged<String?> onName;
  final ValueChanged<bool> onAccept;
  final ValueChanged<String> onSecret;
  final ValueChanged<InstallResultAction> onResult;
  final ValueChanged<InstallStepKey>? onStep;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
}
