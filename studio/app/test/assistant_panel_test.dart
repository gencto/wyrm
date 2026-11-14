import 'package:app/connectors/assistant_page_connector.dart';
import 'package:app/connectors/explorer_page_connector.dart';
import 'package:app/navigation/app_router.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/rights_panel.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/assistant_app.dart';

const String _agent = AssistantApp.agent;
const _links = 'wy/central/sys/links/agent';
const _sp = 'wy/central/downstream/modbus/tcp/ahu2/sp';

/// The agent's root as *What it may do* reads it.
void _cfg(AssistantApp app) {
  app.api
    ..metas[_agent] = NodeMeta(
      cfg: {
        'model': const VStr('claude-sonnet-5-5'),
        'require_approval': const VStr('write'),
        'allowed_prefixes': Value.from([
          'wy/central/downstream/modbus',
          'wy/central/storage',
        ]),
        'budget_tokens_day': const VInt(1000000),
        'api_key_ref': const VStr('anthropic_api_key'),
        'api_base': const VStr('https://api.anthropic.com'),
      },
    )
    ..invokes['$_links ▸ secrets'] = [
      Value.from(['anthropic_api_key']),
    ]
    ..invokes['$_links ▸ history'] = [
      Value.from([
        {
          'rev': 2,
          'params': {'require_approval': 'write'},
        },
      ]),
    ];
}

/// The drawer over a plain screen, as Explorer puts it (⌘J). Wider than
/// Explorer's 420: the test font draws every glyph a full em wide.
Future<void> _drawer(
  WidgetTester tester,
  AssistantApp app, {
  String? selected,
}) async {
  await app.pump(tester, selected: selected);
  await tester.pumpWidget(
    StoreProvider<AppState>(
      store: app.store,
      child: MaterialApp(
        theme: darkTheme(),
        localizationsDelegates: const [S.delegate],
        home: const Scaffold(
          body: Row(
            children: [
              Spacer(),
              SizedBox(width: 640, child: AssistantDrawerConnector()),
            ],
          ),
        ),
      ),
    ),
  );
  await app.settle(tester);
}

const Map<String, Object> _askIvan = {
  'id': 's1',
  'label': 'Ask ivan first',
  'detail': 'Ivan, did you move valve to offset 12 at 03:05?',
  'changes': 0,
};

/// Spec `assistant.md` §2 step 6: *What it may do* and the Explorer drawer,
/// and the Trend of the Result card.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  testWidgets('What it may do: the modes with the corrected Never, the '
      'prefixes, today, the key set or not, where it goes', (tester) async {
    final app = AssistantApp();
    _cfg(app);
    await app.pump(tester);
    await tester.tap(find.text('What it may do'));
    await app.settle(tester);
    app.api.subs['$_agent/budget_used_today']!.add(
      const ValSample(
        '$_agent/budget_used_today',
        Sample(VInt(182000), t: 1),
      ),
    );
    await app.settle(tester);

    final vm = tester.widget<RightsPanel>(find.byType(RightsPanel)).vm;
    expect(
      [for (final m in vm.modes) (m.id, m.selected)],
      [
        ('write', true),
        ('config', false),
        ('never', false),
      ],
    );
    expect(
      vm.modes.last.label,
      'Never — write steps run at once; config steps still wait for a person',
    );
    expect(vm.prefixes, [
      ('wy/central/downstream/modbus', 'downstream/modbus'),
      ('wy/central/storage', 'storage'),
    ]);
    expect(
      [for (final f in vm.facts) (f.label, f.value)],
      [
        ('Model', 'claude-sonnet-5-5'),
        ('Today', '182 k of 1 M tokens'),
        ('API key secret', 'set · never shown'),
        ('Sent to', 'api.anthropic.com'),
      ],
    );
    expect(vm.editReason, isNull);
  });

  testWidgets('a mode and a prefix are staged as an update of the agent '
      'link; nothing is sent before Review', (tester) async {
    final app = AssistantApp();
    _cfg(app);
    await app.pump(tester);
    await tester.tap(find.text('What it may do'));
    await app.settle(tester);

    await tester.tap(find.text('Only config steps'));
    await app.settle(tester);
    // the remove mark of the second prefix chip
    await tester.tap(
      find
          .descendant(
            of: find.byType(RightsPanel),
            matching: find.byType(InkWell),
          )
          .at(4),
    );
    await app.settle(tester);

    final c = app.store.state.changes.table['params:agent']!;
    expect(c.args['params'], {
      'require_approval': 'config',
      'allowed_prefixes': ['wy/central/downstream/modbus'],
    });
    expect(app.calls('update'), isEmpty);
    expect(
      tester.widget<RightsPanel>(find.byType(RightsPanel)).vm.staged,
      isNotNull,
    );
  });

  testWidgets('without config on the agent link the modes are shown, '
      'locked with the reason, and the key is not known', (tester) async {
    final app = AssistantApp(
      grants: const [('wy/central/**', 'write')],
      max: 'write',
    );
    _cfg(app);
    await app.pump(tester);
    await tester.tap(find.text('What it may do'));
    await app.settle(tester);

    final vm = tester.widget<RightsPanel>(find.byType(RightsPanel)).vm;
    expect(vm.editReason, 'needs config on sys/links/agent/~act/update');
    expect(
      vm.facts.firstWhere((f) => f.label == 'API key secret').value,
      'not known: needs config on sys/links/agent',
    );
    await tester.tap(find.text('Only config steps'));
    await app.settle(tester);
    expect(app.store.state.changes.table, isEmpty);
    expect(app.calls('secrets'), isEmpty);
  });

  testWidgets('the drawer: while the plan waits, the second button is a '
      'draft to copy and sends nothing', (tester) async {
    final app = AssistantApp()
      ..task('t-1', planRecord()..['suggestions'] = [_askIvan]);
    await _drawer(tester, app, selected: 't-1');

    expect(find.text('tasks/t-1'), findsOneWidget);
    expect(find.text('Approve 2 changes and run'), findsOneWidget);
    await tester.tap(find.text('Ask ivan first'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Ivan, did you move valve to offset 12'),
      findsOneWidget,
    );
    expect(find.textContaining('nothing is sent to anyone'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await app.settle(tester);
    expect(app.calls('ask'), isEmpty);
    expect(app.store.state.tasks.table['t-1']!.replacedBy, isNull);
  });

  testWidgets('the drawer: after a done task the second button is a '
      'follow-up ask', (tester) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(
          state: 'done',
          step: 3,
          results: const {
            1: {'status': 'ok', 'message': 'added ahu2'},
            2: {'status': 'ok', 'message': 'ok'},
            3: {'status': 'ok', 'message': '21.5'},
          },
        )..['suggestions'] = [_askIvan],
      );
    app.api.invokes['$_agent ▸ ask'] = [
      Value.from({'task': 't-2', 'state': 'planning'}),
    ];
    app.store.dispatchSync(SetDrawerAction(open: true));
    await _drawer(tester, app, selected: 't-1');

    await tester.tap(find.text('Ask ivan first'));
    await app.settle(tester);
    expect(
      app.calls('ask').single.args?['parent'],
      const VStr('t-1'),
    );
    // with require_approval write, no caution on the card
    expect(find.textContaining('without a person'), findsNothing);
    // the follow-up is on screen, and the tab is one press away
    expect(app.store.state.tasks.selectedTask, 't-2');
    expect(find.text('tasks/t-2'), findsOneWidget);
    expect(find.text('Open full'), findsOneWidget);
  });

  testWidgets('Trend of the Result card opens the point in Explorer', (
    tester,
  ) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(
          state: 'done',
          step: 3,
          results: const {
            1: {'status': 'ok', 'message': 'added ahu2'},
            2: {'status': 'ok', 'message': 'ok'},
            3: {'status': 'ok', 'message': '21.5'},
          },
        ),
      );
    await app.pump(tester, selected: 't-1');
    // the tab goes to Explorer through the app's router
    createAppRouter(app.store);

    await tester.tap(find.text('Trend sp'));
    await app.settle(tester);
    expect(app.store.state.nodes.point, _sp);
    expect(app.store.state.nodes.tab, 'history');
    expect(find.byType(FactGrid), findsWidgets);
  });

  testWidgets('Cmd+J opens the drawer over Explorer and closes it', (
    tester,
  ) async {
    final app = AssistantApp();
    app.api.children_['wy/central'] = [];
    await app.pump(tester);
    await tester.pumpWidget(
      StoreProvider<AppState>(
        store: app.store,
        child: MaterialApp(
          theme: darkTheme(),
          localizationsDelegates: const [S.delegate],
          home: const Scaffold(body: ExplorerPageConnector()),
        ),
      ),
    );
    await app.settle(tester);
    expect(find.byType(AssistantDrawerConnector), findsNothing);

    Future<void> cmdJ() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await app.settle(tester);
    }

    await cmdJ();
    expect(find.byType(AssistantDrawerConnector), findsOneWidget);
    expect(find.text('Open full'), findsNothing);
    await cmdJ();
    expect(find.byType(AssistantDrawerConnector), findsNothing);
  });

  testWidgets('the drawer: with require_approval config the second button '
      'of a done task says its plan may write without a person', (
    tester,
  ) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(
          state: 'done',
          step: 3,
          results: const {
            1: {'status': 'ok', 'message': 'added ahu2'},
            2: {'status': 'ok', 'message': 'ok'},
            3: {'status': 'ok', 'message': '21.5'},
          },
        )..['suggestions'] = [_askIvan],
      );
    app.api.metas[_agent] = NodeMeta(
      cfg: {'require_approval': const VStr('config')},
    );
    await _drawer(tester, app, selected: 't-1');

    expect(find.text('Ask ivan first'), findsOneWidget);
    expect(find.textContaining('without a person'), findsOneWidget);
  });
}
