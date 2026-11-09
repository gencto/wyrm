import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/link_install/actions/check_package_action.dart';
import 'package:business/redux/link_install/actions/choose_install_source_action.dart';
import 'package:business/redux/link_install/actions/install_link_action.dart';
import 'package:business/redux/link_install/actions/retrieve_install_catalog_action.dart';
import 'package:business/redux/link_install/actions/set_accept_rights_action.dart';
import 'package:business/redux/link_install/actions/set_broker_action.dart';
import 'package:business/redux/link_install/actions/set_category_action.dart';
import 'package:business/redux/link_install/actions/set_item_action.dart';
import 'package:business/redux/link_install/actions/set_method_action.dart';
import 'package:business/redux/link_install/actions/set_mode_action.dart';
import 'package:business/redux/link_install/actions/set_name_action.dart';
import 'package:business/redux/link_install/actions/set_query_action.dart';
import 'package:business/redux/link_install/actions/set_source_action.dart';
import 'package:business/redux/link_install/actions/set_step_action.dart';
import 'package:business/redux/nodes/actions/set_selected_node_action.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:models/catalog_item.dart';
import 'package:models/install_source.dart';
import 'package:models/link_mode.dart';
import 'package:ui/alerts/notice.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/catalog_card.dart';
import 'package:ui/containers/choice_card.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/check_list.dart';
import 'package:ui/indicators/step_rail.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/link_install_page.dart';

import '../navigation/go_action.dart';

/// A link name: a key segment of letters, digits, `.`, `_`, `-`.
final _segment = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

@RoutePage()
class LinkInstallPageConnector extends StatelessWidget {
  const LinkInstallPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    onInit: (store) {
      store.dispatchSync(ChooseInstallSourceAction('official'));
      unawaited(store.dispatchAndWait(RetrieveInstallCatalogAction()));
    },
    builder: (context, vm) => LinkInstallPage(
      labels: vm.labels,
      steps: vm.steps,
      step: vm.step,
      answers: vm.answers,
      onClose: vm.onClose,
      sources: vm.sources,
      onSource: vm.onSource,
      catalog: vm.catalog,
      onCategory: vm.onCategory,
      onItem: vm.onItem,
      bring: vm.bring,
      onMethod: vm.onMethod,
      onPickFile: vm.onPickFile,
      checks: vm.checks,
      manifest: vm.manifest,
      target: vm.target,
      onBroker: vm.onBroker,
      onMode: vm.onMode,
      result: vm.result,
      resultActions: vm.resultActions,
      onResultAction: vm.onResultAction,
      installing: vm.installing,
      onStep: vm.onStep,
      onBack: vm.onBack,
      onNext: vm.onNext,
      nextReason: vm.nextReason,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LinkInstallPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  bool get _official => linkInstall.path == 'official';

  /// The step keys of the path: official Choose → Where → Install, custom
  /// Bring → Check → Where → Install.
  List<String> get _keys => _official
      ? const ['choose', 'run', 'result']
      : const ['choose', 'check', 'run', 'result'];

  CatalogItem? get _item =>
      linkInstall.catalog.where((c) => c.id == linkInstall.item).firstOrNull;

  @override
  _Vm fromStore() {
    final li = linkInstall;
    final step = li.step.clamp(1, _keys.length);
    final key = _keys[step - 1];
    final viewed = site.viewed ?? '';
    final item = _item;
    final failedCheck = li.checks.any((c) => c.result == 'failed');
    final broker = li.broker ?? viewed;
    final name = li.name ?? '';
    final nameError = name.isEmpty
        ? null
        : (!_segment.hasMatch(name)
              ? S.current.nameRule
              : (broker == viewed && links.table.containsKey(name)
                    ? S.current.nameTaken
                    : null));
    final needsRights = li.rights != null || (item != null && !item.builtIn);
    final configReason = site.needs('config', 'wy/$broker/sys/links');
    final installing = li.phase == 'installing';
    String? nextReason;
    switch (key) {
      case 'choose' when _official && item == null:
        nextReason = S.current.pickOne;
      case 'choose' when !_official && li.source == null:
        nextReason = S.current.bringOne;
      case 'check' when failedCheck:
        nextReason = S.current.checkFailed;
      case 'run' when name.isEmpty || nameError != null:
        nextReason = nameError ?? S.current.nameIt;
      case 'run' when needsRights && !li.acceptRights:
        nextReason = S.current.acceptFirst;
      case 'run' when configReason != null:
        nextReason = configReason;
    }
    final last = key == 'result';
    return _Vm(
      labels: InstallLabels(
        crumb: S.current.linksOn(viewed),
        title: S.current.addALink,
        needs: S.current.needsConfigOnSys,
        railLabel: _official
            ? S.current.fromTheOfficialList
            : S.current.aCustomPackage,
        railNote: S.current.installRailNote,
        stepOf: S.current.stepOf(step, _keys.length),
        question: _question(key, item, name, failedCheck),
        why: _why(key),
        answersTitle: S.current.yourAnswers,
        answersNote: S.current.yourAnswersNote,
        back: S.current.back,
        next: key == 'run' ? S.current.install : S.current.continueLabel,
        onBroker: S.current.onWhichBroker,
        howItRuns: S.current.howItRunsThere,
        linkName: S.current.linkName,
        accept: S.current.acceptRequestedRights,
        checkedHere: S.current.checkedHere,
        manifest: S.current.manifest,
      ),
      step: step,
      steps: [
        for (final (i, k) in _keys.indexed)
          StepVm(
            title: _stepTitle(k),
            sub: i + 1 == step
                ? S.current.now
                : (i + 1 < step ? _answerOf(k, item) : ''),
          ),
      ],
      answers: [
        (
          S.current.answerFrom,
          _official ? S.current.officialList : S.current.customPackage,
        ),
        (
          S.current.answerLink,
          item?.name ?? (li.source == null ? '—' : _sourceName(li.source!)),
        ),
        (
          S.current.answerBroker,
          step >= _keys.indexOf('run') + 1 ? broker : '—',
        ),
        (
          S.current.answerRuns,
          step >= _keys.indexOf('run') + 1 ? _modeWord(li.mode) : '—',
        ),
        (S.current.answerName, name.isEmpty ? '—' : name),
        (
          S.current.answerRights,
          needsRights
              ? (li.acceptRights ? S.current.accepted : S.current.toAccept)
              : S.current.noneAsked,
        ),
      ],
      sources: key == 'choose'
          ? [
              ChoiceCardVm(
                id: 'official',
                title: S.current.officialList,
                detail: S.current.officialListNote,
                selected: _official,
              ),
              ChoiceCardVm(
                id: 'custom',
                title: S.current.customPackage,
                detail: S.current.customPackageNote,
                selected: !_official,
              ),
            ]
          : const [],
      catalog: key == 'choose' && _official ? _catalog() : null,
      bring: key == 'choose' && !_official ? _bring() : null,
      checks: key == 'check'
          ? [
              for (final c in li.checks)
                CheckRowVm(
                  title: c.title,
                  detail: c.detail,
                  result: switch (c.result) {
                    'failed' => CheckResult.failed,
                    'skipped' => CheckResult.skipped,
                    _ => CheckResult.ok,
                  },
                ),
            ]
          : null,
      manifest: key == 'check' ? li.manifest : null,
      target: key == 'run' ? _target(item, broker, viewed, nameError) : null,
      result: last && li.phase != null && !installing
          ? NoticeVm(
              tone: li.phase == 'done' ? Tone.good : Tone.bad,
              message: li.phase == 'done'
                  ? S.current.installedOn(name, broker)
                  : S.current.notInstalled,
              detail: li.message,
            )
          : null,
      resultActions: last && li.phase == 'done'
          ? [
              ('explorer', S.current.openInExplorer),
              ('links', S.current.backToLinks),
              ('again', S.current.addAnother),
            ]
          : (last && li.phase == 'failed'
                ? [
                    ('back', S.current.changeAnswers),
                    ('links', S.current.backToLinks),
                  ]
                : const []),
      installing: installing,
      nextReason: last ? null : nextReason,
      onClose: () => dispatch(GoAction.pop()),
      onSource: (p) => dispatch(ChooseInstallSourceAction(p)),
      onCategory: (c) => dispatch(SetCategoryAction(c)),
      onItem: (id) => dispatch(SetItemAction(id)),
      onMethod: (m) {
        dispatchSync(SetMethodAction(m));
        dispatchSync(SetSourceAction(null));
      },
      onPickFile: _pick,
      onBroker: (b) => dispatch(SetBrokerAction(b)),
      onMode: (m) => dispatch(SetModeAction(LinkMode.values.byName(m))),
      onStep: last ? null : (n) => dispatch(SetStepAction(n)),
      onBack: step == 1
          ? () => dispatch(GoAction.pop())
          : (last && li.phase == 'done'
                ? null
                : () => dispatch(
                    SetStepAction(
                      _keys.indexOf('run') + 1 < step
                          ? _keys.indexOf('run') + 1
                          : step - 1,
                    ),
                  )),
      onNext: last
          ? null
          : () async {
              if (key == 'run') {
                dispatch(SetStepAction(step + 1));
                await dispatchAndWait(InstallLinkAction());
                return;
              }
              if (!_official && key == 'choose') {
                await dispatchAndWait(CheckPackageAction());
              }
              dispatch(SetStepAction(step + 1));
            },
      onResultAction: (a) {
        switch (a) {
          case 'explorer':
            dispatchSync(SetSelectedNodeAction('wy/$broker/downstream/$name'));
            dispatchSync(GoAction.pop());
          case 'links':
            dispatchSync(GoAction.pop());
          case 'again':
            dispatchSync(ChooseInstallSourceAction('official'));
          case 'back':
            dispatchSync(SetStepAction(_keys.indexOf('run') + 1));
        }
      },
    );
  }

  CatalogPartVm _catalog() {
    final li = linkInstall;
    final q = (li.query ?? '').toLowerCase();
    final cats = [
      'All',
      ...{for (final c in li.catalog) c.category},
    ];
    return CatalogPartVm(
      categories: cats,
      category: li.category,
      query: FieldVm(
        value: li.query,
        onChanged: (v) => dispatch(SetQueryAction(v)),
      ),
      note: S.current.catalogNote,
      searchHint: S.current.searchLinks,
      cards: [
        for (final c in li.catalog)
          if ((li.category == 'All' || c.category == li.category) &&
              (q.isEmpty ||
                  '${c.name} ${c.code} ${c.description}'.toLowerCase().contains(
                    q,
                  )))
            CatalogCardVm(
              id: c.id,
              tag: c.tag,
              name: c.name,
              description: c.description,
              source: c.builtIn ? S.current.builtIn : S.current.package,
              builtIn: c.builtIn,
              modes: c.modes.join(' · '),
              note: c.existing == 0 ? null : S.current.linksAlready(c.existing),
              selected: c.id == li.item,
            ),
      ],
    );
  }

  BringPartVm _bring() {
    final li = linkInstall;
    final m = li.method;
    String? url;
    String? ref;
    String? file;
    switch (li.source) {
      case InstallSourceUrl(url: final u):
        url = u;
      case InstallSourceGit(url: final u, ref: final r):
        url = u;
        ref = r;
      case InstallSourceZip(:final fileName) ||
          InstallSourceWasm(:final fileName):
        file = fileName;
      default:
        break;
    }
    return BringPartVm(
      methods: [
        TabItemVm(id: 'zip', label: S.current.zipFile),
        const TabItemVm(id: 'url', label: 'URL'),
        const TabItemVm(id: 'git', label: 'Git'),
        const TabItemVm(id: 'wasm', label: '.wasm'),
      ],
      method: m,
      file: file,
      fileHint: switch (m) {
        'zip' => S.current.chooseZip,
        'wasm' => S.current.chooseWasm,
        _ => null,
      },
      fields: switch (m) {
        'url' => [
          ParamFieldVm(
            id: 'url',
            label: S.current.packageUrl,
            kind: .text,
            value: url,
            hint: 'https://example.com/link.zip',
            onChanged: (v) => dispatch(
              SetSourceAction(
                v == null ? null : InstallSource.url(url: v as String),
              ),
            ),
          ),
        ],
        'git' => [
          ParamFieldVm(
            id: 'git',
            label: S.current.gitRepository,
            kind: .text,
            value: url,
            hint: 'https://git.example.com/link.git',
            onChanged: (v) => dispatch(
              SetSourceAction(
                v == null
                    ? null
                    : InstallSource.git(url: v as String, ref: ref),
              ),
            ),
          ),
          ParamFieldVm(
            id: 'ref',
            label: S.current.gitRef,
            kind: .text,
            value: ref,
            hint: S.current.branchOrTag,
            onChanged: (v) {
              if (url != null) {
                dispatchSync(
                  SetSourceAction(
                    InstallSource.git(url: url, ref: v as String?),
                  ),
                );
              }
            },
          ),
        ],
        _ => const [],
      },
    );
  }

  TargetPartVm _target(
    CatalogItem? item,
    String broker,
    String viewed,
    String? nameError,
  ) {
    final li = linkInstall;
    final modes = _official
        ? (item?.modes.unlock ?? const ['embedded'])
        : [if (li.mode == LinkMode.wasm) 'wasm' else 'process'];
    final mode = li.mode?.name ?? modes.first;
    return TargetPartVm(
      summary: item == null
          ? null
          : ChoiceCardVm(
              id: item.id,
              title: item.name,
              detail: item.builtIn
                  ? S.current.builtInSummary
                  : S.current.packageSummary,
            ),
      brokers: [
        for (final t in li.targets)
          ChoiceCardVm(
            id: t.site,
            title: t.site,
            badge: t.site == viewed
                ? S.current.thisBroker
                : S.current.downstream,
            detail: t.host,
            note: t.site == viewed
                ? S.current.studioSignedInHere
                : S.current.configAllowed,
            refused: t.refused,
            selected: t.site == broker,
            monoTitle: true,
            dot: true,
          ),
      ],
      modes: [
        for (final m in modes)
          ChoiceCardVm(
            id: m,
            title: _modeWord(LinkMode.values.byName(m)),
            detail: _modeNote(m),
            selected: m == mode,
            radio: true,
          ),
      ],
      name: FieldVm(
        value: li.name,
        error: nameError,
        onChanged: (v) => dispatch(SetNameAction(v)),
      ),
      keyPreview: ('wy/$broker/downstream/', li.name ?? ''),
      nameRule: S.current.nameRule,
      rightsTitle: S.current.rightsTitle,
      rights: [
        if (li.rights case final r?)
          for (final part in r.split('; '))
            FactVm(
              label: part.split(' ').first,
              value: part.substring(part.indexOf(' ') + 1),
              mono: true,
            )
        else if (li.message case final m? when li.phase == 'failed')
          FactVm(label: S.current.brokerSays, value: m),
      ],
      accept: (li.rights != null || (item != null && !item.builtIn))
          ? FieldVm(
              value: li.acceptRights,
              onChanged: (v) => dispatch(SetAcceptRightsAction(v)),
            )
          : null,
      rightsNote: S.current.rightsNote,
    );
  }

  Future<void> _pick() async {
    final wasm = linkInstall.method == 'wasm';
    final r = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: [if (wasm) 'wasm' else 'zip'],
    );
    final f = r?.files.single;
    final bytes = f?.bytes;
    if (f == null || bytes == null) {
      return;
    }
    dispatch(
      SetSourceAction(
        wasm
            ? InstallSource.wasm(bytes: bytes, fileName: f.name)
            : InstallSource.zip(bytes: bytes, fileName: f.name),
      ),
    );
  }

  String _question(String key, CatalogItem? item, String name, bool failed) =>
      switch (key) {
        'choose' => S.current.qChoose,
        'check' => failed ? S.current.qCheckFailed : S.current.qCheckOk,
        'run' => S.current.qRun,
        _ => switch (linkInstall.phase) {
          'installing' => S.current.qInstalling(name),
          'failed' => S.current.qFailed,
          _ => S.current.qInstalled(name),
        },
      };

  String _why(String key) => switch (key) {
    'choose' => _official ? S.current.whyChoose : S.current.whyBring,
    'check' => S.current.whyCheck,
    'run' => _official ? S.current.whyRunOfficial : S.current.whyRunCustom,
    _ => switch (linkInstall.phase) {
      'installing' => S.current.whyInstalling,
      'failed' => S.current.whyFailed,
      _ => S.current.whyInstalled,
    },
  };

  String _stepTitle(String k) => switch (k) {
    'choose' => _official ? S.current.stepChoose : S.current.stepBring,
    'check' => S.current.stepCheck,
    'run' => S.current.stepWhere,
    _ => S.current.stepInstall,
  };

  String _answerOf(String k, CatalogItem? item) => switch (k) {
    'choose' =>
      item?.name ??
          (linkInstall.source == null ? '' : _sourceName(linkInstall.source!)),
    'check' =>
      linkInstall.checks.any((c) => c.result == 'failed')
          ? S.current.failed
          : S.current.passed,
    'run' => '${linkInstall.broker ?? ''} · ${_modeWord(linkInstall.mode)}',
    _ => '',
  };

  String _sourceName(InstallSource s) => switch (s) {
    InstallSourceZip(:final fileName) ||
    InstallSourceWasm(:final fileName) => fileName,
    InstallSourceUrl(:final url) || InstallSourceGit(:final url) => url,
    InstallSourceBuiltIn(:final driver) => driver,
    InstallSourceRepository(:final package) => package,
  };

  String _modeWord(LinkMode? m) => switch (m) {
    LinkMode.process => S.current.modeProcess,
    LinkMode.external => S.current.modeExternal,
    LinkMode.wasm => 'WASM',
    _ => S.current.modeEmbedded,
  };

  String _modeNote(String m) => switch (m) {
    'process' => S.current.modeProcessNote,
    'external' => S.current.modeExternalNote,
    'wasm' => S.current.modeWasmNote,
    _ => S.current.modeEmbeddedNote,
  };
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.labels,
    required this.steps,
    required this.step,
    required this.answers,
    required this.sources,
    required this.catalog,
    required this.bring,
    required this.checks,
    required this.manifest,
    required this.target,
    required this.result,
    required this.resultActions,
    required this.installing,
    required this.nextReason,
    required this.onClose,
    required this.onSource,
    required this.onCategory,
    required this.onItem,
    required this.onMethod,
    required this.onPickFile,
    required this.onBroker,
    required this.onMode,
    required this.onStep,
    required this.onBack,
    required this.onNext,
    required this.onResultAction,
  }) : super(
         equals: [
           labels,
           steps,
           step,
           answers,
           sources,
           catalog,
           bring,
           checks,
           manifest,
           target,
           result,
           resultActions,
           installing,
           nextReason,
           onBack != null,
           onNext != null,
           onStep != null,
         ],
       );

  final InstallLabels labels;
  final List<StepVm> steps;
  final int step;
  final List<(String, String)> answers;
  final List<ChoiceCardVm> sources;
  final CatalogPartVm? catalog;
  final BringPartVm? bring;
  final List<CheckRowVm>? checks;
  final String? manifest;
  final TargetPartVm? target;
  final NoticeVm? result;
  final List<(String, String)> resultActions;
  final bool installing;
  final String? nextReason;
  final VoidCallback onClose;
  final ValueChanged<String> onSource;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onItem;
  final ValueChanged<String> onMethod;
  final VoidCallback onPickFile;
  final ValueChanged<String> onBroker;
  final ValueChanged<String> onMode;
  final ValueChanged<int>? onStep;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final ValueChanged<String> onResultAction;
}
