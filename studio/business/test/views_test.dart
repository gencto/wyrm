import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/services/view_bridge/view_bridge.dart';
import 'package:business/redux/views/actions/apply_view_refine_action.dart';
import 'package:business/redux/views/actions/back_view_page_action.dart';
import 'package:business/redux/views/actions/close_views_lab_action.dart';
import 'package:business/redux/views/actions/open_view_page_action.dart';
import 'package:business/redux/views/actions/open_views_lab_action.dart';
import 'package:business/redux/views/actions/pick_view_sample_action.dart';
import 'package:business/redux/views/actions/run_view_action.dart';
import 'package:business/redux/views/actions/set_view_project_action.dart';
import 'package:business/wyrm/session.dart';
import 'package:business/wyrm/views/view_check.dart';
import 'package:business/wyrm/views/view_doc.dart';
import 'package:business/wyrm/views/view_now.dart';
import 'package:business/wyrm/views/view_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';
import 'support/view_samples.dart';

const _sim = 'wy/plant/downstream/bacnet/sim';
const _cpu = 'wy/plant/downstream/s7/plc1/cpu';

class _Heard implements ViewBridgeServiceListener {
  final data = <String, Object?>{};
  final keys = <String, String>{};
  final children = <String, List<String>>{};
  var batches = 0;

  @override
  void onData(Map<String, Object?> changed) {
    batches++;
    for (final e in changed.entries) {
      if (e.value == null) {
        data.removeWhere((k, _) => k == e.key || k.startsWith('${e.key}/'));
      } else {
        data[e.key] = e.value;
      }
    }
  }

  @override
  void onKeys(Map<String, String> states) => keys.addAll(states);

  @override
  void onChildren(String key, List<String> names) => children[key] = names;
}

ValSample _sample(String key, Object v) => ValSample(
  key,
  Sample(Value.from(v), t: DateTime.now().microsecondsSinceEpoch),
);

Child _node(String name) => Child(name, NodeMeta());
Child _point(String name) => Child(name, NodeMeta(ty: TypeCode.number));

void main() {
  group('documents', () {
    test('every sample reads without a fault', () {
      for (final f in viewSampleFiles.where((f) => f.endsWith('.jsonl'))) {
        final doc = parseViewDoc(viewSample(f));
        expect(doc.faults, isEmpty, reason: f);
        if (!f.contains('refine')) {
          expect(doc.catalogId, viewCatalogId, reason: f);
          expect(doc.components, contains('root'), reason: f);
        }
        // genui's parser takes this exact text and no other.
        expect(doc.messages.map((m) => m['version']), everyElement('v0.9'));
      }
    });

    test('demo-plant reads five keys and one template', () {
      final b = bindingsOf(parseViewDoc(viewSample('demo-plant.a2ui.jsonl')));

      expect(b.keys, {
        '$_cpu/temp',
        '$_cpu/counter',
        '$_sim/d1/temp',
        '$_sim/d1/sp',
      });
      expect(b.templates.single.listKey, _sim);
      expect(b.templates.single.path, '/$_sim/~children');
      expect(b.templates.single.rel, {'temp', 'sp'});
      expect(b.templates.single.targets, {'sp'});
      expect(b.actions.map((a) => a.name).toSet(), {'wyrm.open', 'wyrm.set'});
      expect(
        b.actions.where((a) => a.key != null).single.key,
        '$_cpu/mw',
      );
      expect(b.faults, isEmpty);
    });

    test('a page parameter becomes a full key in every path', () {
      final doc = parseViewDoc(
        viewSample('demo-device.a2ui.jsonl'),
        params: {'device': '$_sim/d1'},
      );
      final b = bindingsOf(doc);

      expect(b.keys, {'$_sim/d1/temp', '$_sim/d1/sp'});
      expect(b.actions.single.key, '$_sim/d1/sp');
      expect(b.faults, isEmpty);
    });

    test('the refine turn replaces and adds components of one surface', () {
      final base = parseViewDoc(viewSample('pump-station.a2ui.jsonl'));
      final doc = parseViewDoc(
        viewSample('pump-station.a2ui.jsonl'),
        refine: viewSample('pump-station.refine.a2ui.jsonl'),
      );

      expect(doc.lines.sublist(0, base.lines.length), base.lines);
      expect(doc.lines.length, base.lines.length + 1);
      expect(doc.components.keys, containsAll(['lamps', 'l_v1', 'l_v2']));
      expect((doc.components['trend']!['series']! as List).length, 3);
    });

    test('what is not a stored view is a fault', () {
      final doc = parseViewDoc('''
{"version":"v0.8","createSurface":{"surfaceId":"a","catalogId":"x"}}
not json
{"version":"v0.9","updateDataModel":{"surfaceId":"a","path":"/x","value":1}}
''');

      expect(doc.faults, hasLength(3));
      expect(doc.messages, isEmpty);
    });
  });

  group('checks', () {
    const catalog = <String, Object?>{
      'Column': {
        'type': 'object',
        'properties': {
          'children': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['children'],
        'additionalProperties': false,
      },
      'Value': {
        'type': 'object',
        'properties': {
          'label': {'type': 'string'},
          'value': {
            'anyOf': [
              {'type': 'number'},
              {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                },
                'required': ['path'],
                'additionalProperties': false,
              },
            ],
          },
          'size': {
            'type': 'string',
            'enum': ['s', 'm', 'l'],
          },
        },
        'required': ['value'],
        'additionalProperties': false,
      },
    };

    ViewDoc doc(String value) => parseViewDoc('''
{"version":"v0.9.1","createSurface":{"surfaceId":"t","catalogId":"wyrm:views/0.1"}}
{"version":"v0.9.1","updateComponents":{"surfaceId":"t","components":[{"id":"root","component":"Column","children":["v"]},$value]}}
''');

    test('a valid part with a readable key passes', () {
      final checks = checkView(
        doc('{"id":"v","component":"Value","value":{"path":"/wy/a/x"}}'),
        catalog,
        {'wy/a/x': 'ok'},
        [('wy/a/**', 'read')],
      );

      expect(checks.map((c) => c.level), everyElement('ok'));
    });

    test('a colour, a font or a pixel size fails the check', () {
      for (final extra in [
        '"color":"#ff0000"',
        '"fontFamily":"Comic Sans"',
        '"width":320',
        '"style":{"color":"red"}',
      ]) {
        final checks = checkView(
          doc('{"id":"v","component":"Value","value":1,$extra}'),
          catalog,
          const {},
          const [],
        );

        expect(
          checks.where((c) => c.level == 'bad').single.text,
          contains('is not one a document may set'),
          reason: extra,
        );
      }
    });

    test('a variant outside the set fails; a theme is only a warning', () {
      final checks = checkView(
        parseViewDoc('''
{"version":"v0.9","createSurface":{"surfaceId":"t","catalogId":"wyrm:views/0.1","theme":{"primaryColor":"#f00"}}}
{"version":"v0.9","updateComponents":{"surfaceId":"t","components":[{"id":"root","component":"Column","children":["v"]},{"id":"v","component":"Value","value":1,"size":"huge"}]}}
'''),
        catalog,
        const {},
        const [],
      );

      expect(
        checks.where((c) => c.level == 'bad').single.text,
        contains('size'),
      );
      expect(
        checks.where((c) => c.level == 'warn').single.text,
        contains('theme'),
      );
    });

    test(
      'an unknown part, a missing key and a missing right are told apart',
      () {
        final unknown = checkView(
          doc('{"id":"v","component":"Gauge","value":1}'),
          catalog,
          const {},
          const [],
        );
        expect(
          unknown.where((c) => c.level == 'warn').single.text,
          contains('placeholder'),
        );
        expect(unknown.where((c) => c.level == 'bad'), isEmpty);

        final missing = checkView(
          doc('{"id":"v","component":"Value","value":{"path":"/wy/a/x"}}'),
          catalog,
          {'wy/a/x': 'not_found'},
          [('wy/**', 'config')],
        );
        expect(
          missing.where((c) => c.level == 'bad').single.text,
          '`wy/a/x` does not exist.',
        );

        final unread = checkView(
          doc('{"id":"v","component":"Value","value":{"path":"/wy/a/x"}}'),
          catalog,
          {'wy/a/x': 'ok'},
          [('wy/b/**', 'read')],
        );
        expect(
          unread.where((c) => c.level == 'bad').single.text,
          'You may not read `wy/a/x`.',
        );
      },
    );

    test('an action target needs the write right', () {
      final d = parseViewDoc(viewSample('demo-plant.a2ui.jsonl'));
      final b = bindingsOf(d);
      // Only the action checks: an empty catalog makes every part a
      // placeholder warning.
      final reader = checkView(d, const {}, const {}, [
        ('wy/plant/**', 'read'),
      ]);
      final writer = checkView(
        d,
        const {},
        const {},
        [('wy/plant/**', 'write')],
      );

      expect(b.actions, isNotEmpty);
      expect(
        reader.where((c) => c.level == 'bad').map((c) => c.key),
        ['$_cpu/mw', '$_sim/*/sp'],
      );
      expect(writer.where((c) => c.level == 'bad'), isEmpty);
    });
  });

  group('project', () {
    final project = ViewProject.parse(viewSample('demo-plant.project.json'));

    test('the manifest gives pages, a menu and the kiosk rotation', () {
      expect(project.home, 'overview');
      expect(project.pages.map((p) => p.id), ['overview', 'device']);
      expect(project.page('device')!.params, {'device': _sim});
      expect(project.nav.first.page, 'overview');
      expect(project.nav.last.label, 'BACnet devices');
      expect(project.nav.last.each, 'device');
      expect(project.listed, {_sim});
      expect(project.rotate, hasLength(2));
      expect(
        project.page('device')!.titleFor({'device': '$_sim/d1'}),
        'Device d1',
      );
    });

    test('a page none of whose keys the viewer may read is not shown', () {
      final docs = {
        for (final f in viewSampleFiles) f: viewSample(f),
      };
      final keys = pageKeys(project, 'device', docs, {'device': '$_sim/d1'});

      expect(keys, {'$_sim/d1/temp', '$_sim/d1/sp'});
      expect(
        pageShown(keys, [('wy/plant/downstream/bacnet/**', 'read')]),
        true,
      );
      expect(pageShown(keys, [('wy/plant/downstream/s7/**', 'config')]), false);
      expect(pageShown(const {}, const []), true);
    });
  });

  group('bridge', () {
    late FakeWyrmApi api;
    late _Heard heard;
    late ViewBridgeService bridge;

    setUp(() {
      api = FakeWyrmApi();
      api.metas['$_cpu/temp'] = NodeMeta(unit: const TText('°C'));
      heard = _Heard();
      bridge = ViewBridgeService(listener: heard, flushEvery: Duration.zero)
        ..attach(api);
    });

    tearDown(() => bridge.detach());

    // Lets the fake streams deliver, then takes what the bridge buffered.
    Future<void> settle() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bridge.flush();
    }

    test(
      'a value is written at the path of its key, its unit beside it',
      () async {
        bridge.sync(
          bindingsOf(parseViewDoc(viewSample('demo-plant.a2ui.jsonl'))),
        );
        await settle();
        api.subs['$_cpu/temp']!.add(_sample('$_cpu/temp', 21.5));
        await settle();

        expect(heard.data['/$_cpu/temp'], 21.5);
        expect(
          heard.data['/$viewMetaRoot/${escapeKey('$_cpu/temp')}/unit'],
          '°C',
        );
        expect(heard.keys['$_cpu/temp'], 'ok');
        // A key the broker does not have is said so, and marked unreadable.
        expect(heard.keys['$_cpu/counter'], 'not_found');
        expect(
          heard.data['/$viewQualityRoot/${escapeKey('$_cpu/counter')}'],
          'none',
        );
      },
    );

    test('a template gets one instance per child node, kept live', () async {
      bridge.sync(
        bindingsOf(parseViewDoc(viewSample('demo-plant.a2ui.jsonl'))),
      );
      await settle();
      api.lists[_sim]!.add(
        ListRefreshed([_point('status'), _point('requests'), _node('d1')]),
      );
      await settle();

      // The value children of the folder are not devices.
      expect(heard.data['/$_sim/~children/d1/\$name'], 'd1');
      expect(heard.data['/$_sim/~children/d1/\$key'], '$_sim/d1');
      expect(heard.data.keys.where((k) => k.contains('status')), isEmpty);
      expect(api.subs.keys, contains('$_sim/d1/temp'));

      api.subs['$_sim/d1/temp']!.add(_sample('$_sim/d1/temp', 22.0));
      await settle();
      // One key bound twice: by its own path and inside the template.
      expect(heard.data['/$_sim/d1/temp'], 22.0);
      expect(heard.data['/$_sim/~children/d1/temp'], 22.0);

      api.lists[_sim]!.add(ChildAdded(_node('d2')));
      await settle();
      expect(heard.data['/$_sim/~children/d2/\$name'], 'd2');
      expect(bridge.subscribed, contains('$_sim/d2/sp'));

      api.lists[_sim]!.add(const ChildRemoved('d2'));
      await settle();
      expect(heard.data.keys.where((k) => k.contains('/d2')), isEmpty);
      expect(bridge.subscribed, isNot(contains('$_sim/d2/sp')));
    });

    test(
      'another document closes what it no longer reads and keeps the rest',
      () async {
        bridge.sync(
          bindingsOf(parseViewDoc(viewSample('demo-plant.a2ui.jsonl'))),
        );
        await settle();
        api.subs['$_sim/d1/temp']!.add(_sample('$_sim/d1/temp', 20.5));
        await settle();
        heard.data.clear();

        bridge.sync(
          bindingsOf(
            parseViewDoc(
              viewSample('demo-device.a2ui.jsonl'),
              params: {'device': '$_sim/d1'},
            ),
          ),
          root: {r'$name': 'd1'},
        );
        await settle();

        expect(bridge.subscribed, {'$_sim/d1/temp', '$_sim/d1/sp'});
        // What the bridge still holds is written again for the new surface.
        expect(heard.data['/$_sim/d1/temp'], 20.5);
        expect(heard.data[r'/$name'], 'd1');
      },
    );

    test('fifty values a second reach the listener in batches', () async {
      bridge.detach();
      // The bridge's own pace: a batch every 100 ms.
      bridge = ViewBridgeService(listener: heard)
        ..attach(api)
        ..sync(bindingsOf(parseViewDoc(viewSample('demo-plant.a2ui.jsonl'))));
      await settle();
      heard.batches = 0;
      final watch = Stopwatch()..start();

      for (var i = 0; i < 50; i++) {
        api.subs['$_cpu/temp']!.add(_sample('$_cpu/temp', 20 + i / 10));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(heard.data['/$_cpu/temp'], 24.9);
      // One batch per 100 ms at most, however many values came.
      expect(heard.batches, greaterThan(3));
      expect(
        heard.batches,
        lessThanOrEqualTo(watch.elapsedMilliseconds ~/ 100 + 1),
      );
    });
  });

  group('lab', () {
    late FakeWyrmApi api;

    Future<Store<AppState>> open() async {
      api = FakeWyrmApi();
      final session = FakeSession(
        api: api,
        who: const WhoAmI(
          subject: 'user:admin',
          site: 'plant',
          roles: ['admin'],
          max: 'config',
          grants: [('wy/plant/**', 'config')],
        ),
      );
      final store = fakeStore(login: FakeLogin(session: session));
      await depsOf(store).attach(session);
      await store.dispatchAndWait(
        OpenViewsLabAction(catalog: const {}, bundle: SampleBundle()),
      );
      return store;
    }

    test('opening shows demo-plant and subscribes what it reads', () async {
      final store = await open();

      expect(store.state.views.open, isTrue);
      expect(store.state.views.sample, 'demo-plant');
      expect(viewNow(store.state.views).doc.surfaceId, 'demo-plant');
      expect(
        api.calls.where((c) => c.op == 'subscribe').map((c) => c.key),
        containsAll(['$_cpu/temp', '$_sim/d1/sp']),
      );
      expect(api.calls.where((c) => c.op == 'list').single.key, _sim);

      store.dispatchSync(CloseViewsLabAction());
      expect(depsOf(store).viewBridge.subscribed, isEmpty);
    });

    test('wyrm.set writes with the session; a refusal is an error', () async {
      final store = await open();

      await store.dispatchAndWait(
        RunViewAction('wyrm.set', {'key': '$_sim/d1/sp', 'value': 22.5}),
      );
      final set = api.calls.where((c) => c.op == 'set').single;
      expect(set.key, '$_sim/d1/sp');
      expect(set.value, const VFloat(22.5));
      expect(store.state.views.result, 'Wrote 22.5 to $_sim/d1/sp');

      api.errors['$_cpu/mw'] = WyrmException.of(
        Status.permissionDenied,
        'no write grant',
      );
      final status = await store.dispatchAndWait(
        RunViewAction('wyrm.set', {'key': '$_cpu/mw', 'value': 0}),
      );
      expect(status.originalError, isNotNull);
      expect(store.state.problems.items.last.key, '$_cpu/mw');
    });

    test('wyrm.invoke runs the action', () async {
      final store = await open();
      api.invokes['wy/plant/downstream/modbus/plc1/pumps/p1 ▸ start'] = [];

      await store.dispatchAndWait(
        RunViewAction('wyrm.invoke', {
          'key': 'wy/plant/downstream/modbus/plc1/pumps/p1',
          'action': 'start',
        }),
      );

      expect(api.calls.where((c) => c.op == 'invoke').single.action, 'start');
    });

    test('wyrm.open keeps a back stack; the menu starts it again', () async {
      final store = await open();
      store.dispatchSync(SetViewProjectAction(on: true));
      expect(viewNow(store.state.views).page!.id, 'overview');

      await store.dispatchAndWait(
        RunViewAction('wyrm.open', {
          'page': 'device',
          'params': {'device': '$_sim/d1'},
        }),
      );
      var now = viewNow(store.state.views);
      expect(now.page!.id, 'device');
      expect(store.state.views.stack.map((p) => p.page), [
        'overview',
        'device',
      ]);
      expect(now.bindings.keys, {'$_sim/d1/temp', '$_sim/d1/sp'});
      expect(now.root, {r'$name': 'd1', r'$key': '$_sim/d1'});
      expect(depsOf(store).viewBridge.subscribed, now.bindings.keys);

      store.dispatchSync(BackViewPageAction());
      now = viewNow(store.state.views);
      expect(now.page!.id, 'overview');

      store.dispatchSync(
        OpenViewPageAction(
          'device',
          params: {'device': '$_sim/d2'},
          root: true,
        ),
      );
      expect(store.state.views.stack.map((p) => p.page), [
        'overview',
        'device',
      ]);
      expect(store.state.views.stack.last.params['device'], '$_sim/d2');
    });

    test('the refine turn adds lines to the same surface', () async {
      final store = await open();
      store.dispatchSync(PickViewSampleAction('pump-station'));
      final before = viewNow(store.state.views).doc.lines;

      store.dispatchSync(ApplyViewRefineAction());
      final after = viewNow(store.state.views).doc.lines;

      expect(after.sublist(0, before.length), before);
      expect(after.length, before.length + 1);
      expect(
        depsOf(store).viewBridge.subscribed,
        contains('wy/plant/downstream/modbus/plc1/v1/open'),
      );
    });
  });
}
