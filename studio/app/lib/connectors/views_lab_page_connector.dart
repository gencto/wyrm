import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/theme/actions/set_theme_mode_action.dart';
import 'package:business/redux/views/actions/apply_view_refine_action.dart';
import 'package:business/redux/views/actions/back_view_page_action.dart';
import 'package:business/redux/views/actions/close_views_lab_action.dart';
import 'package:business/redux/views/actions/go_view_crumb_action.dart';
import 'package:business/redux/views/actions/open_view_page_action.dart';
import 'package:business/redux/views/actions/open_views_lab_action.dart';
import 'package:business/redux/views/actions/pick_view_sample_action.dart';
import 'package:business/redux/views/actions/run_view_action.dart';
import 'package:business/redux/views/actions/set_density_action.dart';
import 'package:business/redux/views/actions/set_draft_action.dart';
import 'package:business/redux/views/actions/set_tab_action.dart';
import 'package:business/redux/views/actions/set_view_project_action.dart';
import 'package:business/redux/views/actions/set_view_source_action.dart';
import 'package:business/redux/views/actions/set_width_action.dart';
import 'package:business/wyrm/views/view_now.dart';
import 'package:business/wyrm/views/view_project.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/view_check.dart';
import 'package:ui/buttons/pill_tabs.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/views_lab_page.dart';
import 'package:ui/views/catalog/wyrm_catalog.dart';
import 'package:ui/views/view_checks.dart';
import 'package:ui/views/view_project_shell.dart';
import 'package:ui/views/view_style.dart';
import 'package:ui/views/view_surface.dart';

import '../common/trend.dart';
import '../navigation/go_action.dart';

/// The views lab (docs/design/specs/genui-views.md §4), reached from
/// System. While it is on screen the view bridge keeps the document's keys
/// subscribed; leaving it closes them.
@RoutePage()
class ViewsLabPageConnector extends StatelessWidget {
  const ViewsLabPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    onInit: (store) => unawaited(
      store.dispatchAndWait(
        OpenViewsLabAction(catalog: wyrmCatalogSchemas()),
      ),
    ),
    onDispose: (store) => store.dispatchSync(CloseViewsLabAction()),
    builder: (context, vm) => ViewsLabPage(
      onBack: vm.onBack,
      theme: vm.theme,
      samples: vm.samples,
      sample: vm.sample,
      onRefine: vm.onRefine,
      project: vm.project,
      draft: vm.draft,
      onShowDraft: vm.onShowDraft,
      result: vm.result,
      width: vm.width,
      density: vm.density,
      surfaceId: vm.surfaceId,
      messages: vm.messages,
      data: vm.data.unlockView,
      format: vm.format,
      onAction: vm.onAction,
      shell: vm.shell,
      onItem: vm.onItem,
      onCrumb: vm.onCrumb,
      onPageBack: vm.onPageBack,
      tab: vm.tab,
      checks: vm.checks,
      problems: vm.problems,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ViewsLabPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final now = viewNow(state.views);
    final sample = viewSamples[views.sample];
    final checks = [
      if (now.fault case final f?) ViewCheck(level: 'bad', text: f),
      ...views.checks,
    ];
    final draft = views.draft;
    return _Vm(
      theme: FieldVm(
        value: theme.mode == .light ? .light : .dark,
        onChanged: (m) => dispatchSync(SetThemeModeAction(m)),
      ),
      samples: [
        for (final name in viewSamples.keys) PillTabVm(id: name, label: name),
        if (views.sample == 'pasted')
          PillTabVm(id: 'pasted', label: S.current.viewsPasted),
      ],
      sample: FieldVm(
        value: views.sample,
        onChanged: (name) => dispatchSync(PickViewSampleAction(name)),
      ),
      onRefine: sample?.refine != null && views.refine.isEmpty
          ? () => dispatchSync(ApplyViewRefineAction())
          : null,
      project: FieldVm(
        value: views.project,
        enabled: sample?.project != null,
        onChanged: (on) => dispatchSync(SetViewProjectAction(on: on)),
      ),
      draft: FieldVm(
        value: draft,
        onChanged: (text) => dispatchSync(SetDraftAction(text ?? '')),
      ),
      onShowDraft: draft.trim().isEmpty
          ? null
          : () => dispatchSync(SetViewSourceAction(draft)),
      result: views.result ?? '',
      width: FieldVm(
        value: views.width,
        onChanged: (w) => dispatchSync(SetWidthAction(w)),
      ),
      density: FieldVm(
        value: views.density ?? '',
        onChanged: (d) => dispatchSync(SetDensityAction(d.isEmpty ? null : d)),
      ),
      surfaceId: now.doc.surfaceId ?? '',
      messages: now.doc.lines,
      data: views.data,
      format: trendFormat(),
      shell: _shell(now),
      tab: FieldVm(
        value: views.tab,
        onChanged: (t) => dispatchSync(SetTabAction(t)),
      ),
      checks: [
        for (final c in checks)
          ViewCheckVm(
            tone: switch (c.level) {
              'ok' => Tone.good,
              'warn' => Tone.warn,
              _ => Tone.bad,
            },
            text: c.text,
            where: c.part ?? c.key ?? '',
          ),
      ],
      problems: checks.where((c) => c.level != 'ok').length,
      onBack: () => dispatch(GoAction.pop()),
      onAction: (a) => dispatch(RunViewAction(a.name, a.context)),
      onItem: (id) {
        final uri = Uri.parse(id);
        dispatchSync(
          OpenViewPageAction(
            uri.path,
            params: uri.queryParameters,
            root: true,
          ),
        );
      },
      onCrumb: (i) => dispatchSync(GoViewCrumbAction(i)),
      onPageBack: views.stack.length > 1
          ? () => dispatchSync(BackViewPageAction())
          : null,
    );
  }

  /// The frame and the menu around the page; null with *Project* off.
  ViewProjectVm? _shell(ViewNow now) {
    final project = now.project;
    final place = now.place;
    if (project == null || place == null) {
      return null;
    }
    final docs = views.docs.unlockView;
    final grants = views.grants.unlockView;

    // A badge counts the active alarms whose source is a key the page
    // reads, or lies under one.
    (int, ViewState) badge(Set<String> keys) {
      var n = 0;
      var worst = ViewState.warn;
      for (final MapEntry(key: source, value: level) in views.alarms.entries) {
        if (keys.any((k) => source == k || source.startsWith('$k/'))) {
          n++;
          if (level == 'bad') {
            worst = .alarm;
          }
        }
      }
      return (n, worst);
    }

    ViewNavItemVm? item(String page, [Map<String, String> params = const {}]) {
      final def = project.page(page);
      final keys = pageKeys(project, page, docs, params);
      // A page none of whose keys the viewer may read is not in the menu.
      if (def == null || !pageShown(keys, grants)) {
        return null;
      }
      final (n, worst) = badge(keys);
      return ViewNavItemVm(
        id: Uri(
          path: page,
          queryParameters: params.isEmpty ? null : params,
        ).toString(),
        label: params.isEmpty
            ? def.titleFor(params)
            : params.values.first.split('/').last,
        selected:
            place.page == page && mapEquals(place.params.unlockView, params),
        badge: n,
        badgeState: worst,
      );
    }

    ViewNavItemVm? entry(ViewNavDef n) {
      final each = n.each;
      final page = n.page;
      if (page != null && each != null) {
        final under = project.page(page)?.params[each];
        return ViewNavItemVm(
          id: '',
          label: n.label ?? page,
          children: [
            for (final name in views.children[under ?? ''] ?? const <String>[])
              ?item(page, {each: '$under/$name'}),
          ],
        );
      }
      if (page != null) {
        return item(page);
      }
      return ViewNavItemVm(
        id: '',
        label: n.label ?? '',
        children: [for (final c in n.children) ?entry(c)],
      );
    }

    final t = DateTime.now();
    final stack = views.stack.isEmpty ? [place] : views.stack.unlockView;
    final rotate = project.rotate;
    return ViewProjectVm(
      title: project.title,
      items: [for (final n in project.nav) ?entry(n)],
      crumbs: [
        for (final p in stack)
          switch (project.page(p.page)) {
            final def? => [
              for (final n in project.nav)
                if (n.page == p.page && n.each != null) ?n.label,
              def.titleFor(p.params.unlockView),
            ].join(' › '),
            null => p.page,
          },
      ],
      clock:
          '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}',
      alarms: views.alarms.length,
      alarmText: views.alarms.keys.take(3).join(' · '),
      rotation: rotate.length,
      rotationAt: rotate
          .indexOf(
            Uri(
              path: place.page,
              queryParameters: place.params.isEmpty
                  ? null
                  : place.params.unlockView,
            ).toString(),
          )
          .clamp(0, rotate.isEmpty ? 0 : rotate.length - 1),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.theme,
    required this.samples,
    required this.sample,
    required this.onRefine,
    required this.project,
    required this.draft,
    required this.onShowDraft,
    required this.result,
    required this.width,
    required this.density,
    required this.surfaceId,
    required this.messages,
    required this.data,
    required this.format,
    required this.shell,
    required this.tab,
    required this.checks,
    required this.problems,
    required this.onBack,
    required this.onAction,
    required this.onItem,
    required this.onCrumb,
    required this.onPageBack,
  }) : super(
         equals: [
           theme,
           samples,
           sample,
           onRefine != null,
           project,
           draft,
           onShowDraft != null,
           result,
           width,
           density,
           surfaceId,
           messages,
           data,
           format,
           shell,
           tab,
           checks,
           problems,
           onPageBack != null,
         ],
       );

  final FieldVm<ThemeMode> theme;
  final List<PillTabVm> samples;
  final FieldVm<String> sample;
  final VoidCallback? onRefine;
  final FieldVm<bool> project;
  final FieldVm<String?> draft;
  final VoidCallback? onShowDraft;
  final String result;
  final FieldVm<String> width;
  final FieldVm<String> density;
  final String surfaceId;
  final List<String> messages;
  final IMap<String, Object> data;
  final TrendFormat format;
  final ViewProjectVm? shell;
  final FieldVm<String> tab;
  final List<ViewCheckVm> checks;
  final int problems;
  final VoidCallback onBack;
  final ValueChanged<ViewActionVm> onAction;
  final ValueChanged<String> onItem;
  final ValueChanged<int> onCrumb;
  final VoidCallback? onPageBack;
}
