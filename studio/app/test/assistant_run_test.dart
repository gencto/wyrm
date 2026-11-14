import 'dart:convert';
import 'dart:io';

import 'package:app/common/files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/assistant/result_card.dart';
import 'package:ui/assistant/run_card.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/assistant_app.dart';

List<(int, RunStatus, String)> _rows(WidgetTester tester) => [
  for (final r in tester.widget<RunCard>(find.byType(RunCard)).vm.rows)
    (r.n, r.status, r.text),
];

const Map<String, Object> _ok = {
  'status': 'ok',
  'message': 'ok',
  'time': 1794108760,
};

/// Boards *AssistantRun*, *AssistantDone*, *AssistantFailed* (spec
/// `assistant.md` §2 step 3): the run from the public `~val` and the
/// record, what a finished plan left, where a stopped one stopped.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  const agent = AssistantApp.agent;
  const sp = 'wy/central/downstream/modbus/tcp/ahu2/sp';

  testWidgets('a run follows ~val: each step reads the record again', (
    tester,
  ) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(state: 'running', step: 1, log: const ['approved by olena']),
      );
    await app.pump(tester, selected: 't-1');

    // the plan folds to its header; the run tells the story
    expect(find.text('Show steps'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(
      tester.widget<RunCard>(find.byType(RunCard)).vm.title,
      'Run · step 1 of 3',
    );
    expect(_rows(tester), [
      (1, RunStatus.running, 'running…'),
      (2, RunStatus.waiting, 'waiting'),
      (3, RunStatus.waiting, 'waiting'),
    ]);
    expect(find.text('stops at the first step that fails'), findsOneWidget);

    // step 1 ended and step 2 runs: the public value has numbers only, the
    // text comes from the record
    app.api.docs['$agent/tasks/t-1 ~state'] = Value.from(
      planRecord(
        state: 'running',
        step: 2,
        results: const {
          1: {'status': 'ok', 'message': 'added ahu2', 'time': 1794108760},
        },
      ),
    );
    final docs = app.calls('~state').length;
    app.api.subs['$agent/tasks/*']!.add(
      ValSample(
        '$agent/tasks/t-1',
        Sample(
          Value.from({
            'state': 'running',
            'step': 2,
            'of': 3,
            'last': {'n': 1, 'ok': true, 'result': 'ok'},
          }),
          t: 1,
        ),
      ),
    );
    await app.settle(tester);

    expect(app.calls('~state').length, docs + 1);
    expect(
      tester.widget<RunCard>(find.byType(RunCard)).vm.title,
      'Run · step 2 of 3',
    );
    expect(_rows(tester), [
      (1, RunStatus.ok, 'added ahu2'),
      (2, RunStatus.running, 'running…'),
      (3, RunStatus.waiting, 'waiting'),
    ]);
  });

  testWidgets('Show steps opens the plan of a run', (tester) async {
    final app = AssistantApp()
      ..task('t-1', planRecord(state: 'running', step: 1));
    await app.pump(tester, selected: 't-1');
    expect(find.text('why: the device the operator asked for'), findsNothing);

    await tester.tap(find.text('Show steps'));
    await tester.pump();

    expect(find.text('why: the device the operator asked for'), findsOneWidget);
    expect(find.text('Hide steps'), findsOneWidget);
    expect(find.byType(PlanCard), findsOneWidget);
  });

  testWidgets('a done plan shows its result with the values now', (
    tester,
  ) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(
          state: 'done',
          step: 3,
          results: const {
            1: _ok,
            2: _ok,
            3: {'status': 'ok', 'message': '21.5', 'time': 1794108801},
          },
        ),
      );
    await app.pump(tester, selected: 't-1');

    expect(find.text('all steps passed · 41 s'), findsOneWidget);
    // the key the plan set and proved is watched while the tab shows it
    expect(app.store.state.live.watched.keys, contains(sp));
    var result = tester.widget<ResultCard>(find.byType(ResultCard)).vm;
    expect(result.facts, [('modbus/tcp/ahu2/sp', '—')]);

    app.api.subs[sp]!.add(const ValSample(sp, Sample(VFloat(21.5), t: 1)));
    await app.settle(tester);
    result = tester.widget<ResultCard>(find.byType(ResultCard)).vm;
    expect(result.facts, [('modbus/tcp/ahu2/sp', '21.5')]);

    // leaving the tab's tree stops the watch
    await tester.pumpWidget(const SizedBox());
    expect(app.store.state.live.watched.keys, isNot(contains(sp)));
  });

  testWidgets('Save as a plan writes the wyrm-agent run format', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('wyrm-plan');
    addTearDown(() {
      directoryPicker = null;
      dir.deleteSync(recursive: true);
    });
    directoryPicker = (_) async => dir.path;
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(
          state: 'done',
          step: 3,
          results: const {1: _ok, 2: _ok, 3: _ok},
        ),
      );
    await app.pump(tester, selected: 't-1');

    await tester.tap(find.text('Save as a plan'));
    await app.settle(tester);

    final file = File('${dir.path}/task-t-1.plan.json');
    final plan = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(plan['steps'], [
      {
        'invoke': 'wy/central/downstream/modbus/tcp',
        'action': 'add_device',
        'args': {'name': 'ahu2', 'unit': 3},
      },
      {'set': sp, 'value': 21.5},
      {'expect': sp, 'equals': 21.5, 'timeout_s': 10.0},
    ]);
  });

  testWidgets('Open in Explorer selects the node the plan changed', (
    tester,
  ) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(
          state: 'done',
          step: 3,
          results: const {1: _ok, 2: _ok, 3: _ok},
        ),
      );
    await app.pump(tester, selected: 't-1');

    expect(find.text('Open sp in Explorer'), findsOneWidget);
  });

  testWidgets('a stopped run says where it stopped and what stays done', (
    tester,
  ) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(
          state: 'failed',
          step: 2,
          results: const {
            1: _ok,
            2: {
              'status': 'failed',
              'message': 'out_of_range: 21.5 is above max 21',
              'time': 1794108770,
            },
          },
        )..['error'] = 'step 2 (set …/sp): out_of_range',
      );
    await app.pump(tester, selected: 't-1');

    expect(_rows(tester), [
      (1, RunStatus.ok, 'ok'),
      (2, RunStatus.failed, 'out_of_range: 21.5 is above max 21'),
      (3, RunStatus.waiting, 'not run'),
    ]);
    expect(find.text('stopped · steps 1–1 stay done'), findsOneWidget);
    expect(find.text('STOPPED AT STEP 2'), findsOneWidget);
    expect(
      find.textContaining('out_of_range: 21.5 is above max 21\nWhat was done'),
      findsOneWidget,
    );
    expect(find.byType(ResultCard), findsNothing);
  });

  testWidgets('a rejected plan has no run', (tester) async {
    final app = AssistantApp()
      ..task(
        't-1',
        planRecord(state: 'failed')..['error'] = 'rejected by user:olena',
      );
    await app.pump(tester, selected: 't-1');

    expect(find.byType(RunCard), findsNothing);
    expect(find.text('rejected by user:olena'), findsOneWidget);
  });
}
