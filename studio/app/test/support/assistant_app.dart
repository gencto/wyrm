import 'package:app/connectors/assistant_page_connector.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:business/wyrm/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../business/test/support/fake_wyrm.dart';

export '../../../business/test/support/fake_wyrm.dart';

/// The Assistant tab over a fake gateway: a site `central` with the agent
/// link `agent` and its tasks, as the connector reads them when the tab is
/// shown.
class AssistantApp {
  AssistantApp({
    String user = 'olena',
    List<String> roles = const ['engineer'],
    List<(String, String)> grants = const [('wy/central/**', 'config')],
    String max = 'config',
  }) : login = FakeLogin(
         session: FakeSession(
           who: WhoAmI(
             subject: user,
             site: 'central',
             roles: roles,
             max: max,
             grants: grants,
           ),
         ),
       ) {
    store = fakeStore(login: login);
    api
      ..children_['wy/central/sys/links'] = [Child('agent', NodeMeta())]
      ..metas['wy/central/sys/links/agent'] = NodeMeta(
        attr: {'driver': const VStr('agent'), 'mode': const VStr('embedded')},
      )
      ..metas[agent] = NodeMeta(cfg: {'model': const VStr('claude-opus-5-5')})
      // the schema of the plan's invoke step: its arguments are shown
      ..metas['wy/central/downstream/modbus/tcp'] = NodeMeta(
        actions: {
          'add_device': ActionMeta(
            params: {'name': ParamMeta(), 'unit': ParamMeta()},
          ),
        },
      )
      ..children_['$agent/tasks'] = [];
  }

  static const agent = 'wy/central/downstream/agent';

  final FakeLogin login;
  late final Store<AppState> store;

  FakeWyrmApi get api => login.session.api;

  /// Puts the task [id] with its record on the fake broker.
  void task(String id, Map<String, Object?> record) {
    api.children_['$agent/tasks'] = [
      ...?api.children_['$agent/tasks'],
      Child(id, NodeMeta()),
    ];
    api.docs['$agent/tasks/$id ~state'] = Value.from(record);
  }

  /// The calls of [action] (for a document: its suffix) made so far.
  List<Call> calls(String action) => [
    for (final c in api.calls)
      if (c.action == action) c,
  ];

  /// Logs in, selects [selected] and shows the tab.
  Future<void> pump(WidgetTester tester, {String? selected}) async {
    tester.view.physicalSize = const Size(1364, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await store.dispatchAndWait(SetGatewayAction('http://g'));
      await store.dispatchAndWait(SetUserAction('olena'));
      await store.dispatchAndWait(SetPasswordAction('pw'));
      await store.dispatchAndWait(LogInAction());
    });
    store.dispatchSync(SetSelectedTaskAction(selected));
    await tester.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: MaterialApp(
          theme: darkTheme(),
          localizationsDelegates: const [S.delegate],
          home: const Scaffold(body: AssistantPageConnector()),
        ),
      ),
    );
    await settle(tester);
  }

  /// Lets the fake broker's answers arrive and the screen follow them.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      // a read may wait for the broker's version (2 s) before it goes on
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

/// A record (`~state`) of a task with a plan of three steps: a `config`
/// invoke, a `write` set that needs it, and a proof step.
Map<String, Object?> planRecord({
  String state = 'awaiting_approval',
  String owner = 'user:olena',
  int step = 0,
  Map<int, Map<String, Object?>> results = const {},
  List<String> log = const ['asked by user:olena'],
}) => {
  'state': state,
  'owner': owner,
  'ask': 'add ahu2',
  'plan': [
    {
      'n': 1,
      'invoke': 'wy/central/downstream/modbus/tcp',
      'action': 'add_device',
      'args': {'name': 'ahu2', 'unit': 3},
      'level': 'config',
      'approval': true,
      'check': 'now',
      'reason': 'the device the operator asked for',
      'result': ?results[1],
    },
    {
      'n': 2,
      'set': 'wy/central/downstream/modbus/tcp/ahu2/sp',
      'value': 21.5,
      'level': 'write',
      'after': [1],
      'approval': true,
      'check': 'at_run',
      'result': ?results[2],
    },
    {
      'n': 3,
      'expect': 'wy/central/downstream/modbus/tcp/ahu2/sp',
      'equals': 21.5,
      'timeout_s': 10.0,
      'level': 'read',
      'after': [2],
      'approval': false,
      'check': 'now',
      'result': ?results[3],
    },
  ],
  'step': step,
  'log': log,
  'tokens': 12,
};

/// A record of a task that asked the person two questions: which unit
/// (one option) and which points (several). [answers] by question id are
/// the answers the record already holds.
Map<String, Object?> askRecord({
  String state = 'awaiting_answer',
  Map<String, Object?> answers = const {},
}) => {
  'state': state,
  'owner': 'user:olena',
  'ask': 'add ahu2',
  'plan': const <Object?>[],
  'questions': [
    {
      'id': 'q1',
      'text': 'Which unit is AHU 2?',
      'options': [
        {'id': 'u3', 'label': 'Slave ID 3', 'detail': 'answers, 14 points'},
        {'id': 'u4', 'label': 'Slave ID 4', 'detail': 'answers, no name'},
      ],
      'multiple': false,
      'free_text': true,
      'answer': ?answers['q1'],
    },
    {
      'id': 'q2',
      'text': 'Which points do you want recorded?',
      'options': [
        {'id': 'supply', 'label': 'Supply temperature', 'detail': ''},
        {'id': 'return', 'label': 'Return temperature', 'detail': ''},
        {'id': 'fan', 'label': 'Fan speed', 'detail': ''},
      ],
      'multiple': true,
      'free_text': false,
      'answer': ?answers['q2'],
    },
  ],
  'log': const ['asked by user:olena', 'asked 2 question(s)'],
  'tokens': 12,
};
