import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_flutter/wyrm_flutter.dart';

/// A [WyrmApi] with one node `wy/s/downstream/m` that has actions.
class ActApi implements WyrmApi {
  final invoked = <(String, String, Value?)>[];
  final lists = <String, StreamController<ListUpdate>>{};

  /// A value point (goes to Metrics) with its own actions.
  static final metaT = NodeMeta(ty: TypeCode.number, hasChildren: false, actions: {
    'edit': ActionMeta(display: 'Edit', group: 'edit', params: {'scale': ParamMeta(ty: TypeCode.number)}),
  });

  static final metaM = NodeMeta(hasChildren: true, actions: {
    'count': ActionMeta(params: {'n': ParamMeta(ty: TypeCode.number, required: true)}),
    'reset': ActionMeta(),
    'history': ActionMeta(display: 'History', result: const ResultType(TypeCode.array)),
    // a list with nothing in it yet (as sys/quarantine Deauthorize)
    'deauthorize': ActionMeta(display: 'Deauthorize', params: {
      'link': ParamMeta(ty: TypeCode.string, required: true, enumValues: [], placeholder: 'no external links'),
    }),
  });

  /// A driver connection: groups `new` and `edit` (spec 02 0.1.6).
  static final metaC = NodeMeta(hasChildren: true, actions: {
    'add_device': ActionMeta(display: 'Add Device', group: 'new', params: {
      'name': ParamMeta(ty: TypeCode.string, required: true, display: 'Name'),
      'unit': ParamMeta(ty: TypeCode.number, display: 'Slave ID', description: '1..247'),
    }),
    'add_point': ActionMeta(display: 'Add Point', group: 'new', params: {
      'name': ParamMeta(ty: TypeCode.string, required: true),
      'password': ParamMeta(ty: TypeCode.string, editor: 'password', placeholder: 'secret'),
      'table': ParamMeta(ty: TypeCode.enum_, enumValues: ['coil', 'holding'], defaultValue: const VStr('coil')),
      'map': ParamMeta(ty: TypeCode.binary, editor: 'file', display: 'Map file'),
    }),
    'edit': ActionMeta(display: 'Edit', group: 'edit', params: {'host': ParamMeta(ty: TypeCode.string)}),
    'remove': ActionMeta(display: 'Remove', group: 'edit'),
    'restart': ActionMeta(display: 'Restart'),
    'hello': ActionMeta(level: Perm.none, params: {'token': ParamMeta(ty: TypeCode.binary)}),
  });

  @override
  Stream<ListUpdate> list(String key) {
    final c = StreamController<ListUpdate>();
    lists[key] = c;
    if (key == 'wy/s/downstream') c.add(ListRefreshed([Child('m', metaM), Child('c', metaC)]));
    return c.stream;
  }

  @override
  Stream<ValEvent> subscribe(String pattern) => const Stream.empty();
  @override
  Future<void> set(String key, Value value) async {}
  @override
  Stream<Value> invoke(String key, String action, [Value? args]) {
    invoked.add((key, action, args));
    if (action == 'reset') {
      return Stream.error(WyrmException.of(Status.invalidParameter, 'test exists'));
    }
    if (action == 'history') {
      // like the admin's link history: one record per revision
      return Stream.value(VArray([
        VMap({'rev': const VInt(1), 'params': VMap({'points': const VInt(16)})}),
      ]));
    }
    return Stream.value(const VInt(7));
  }

  @override
  Future<NodeMeta> meta(String key) async => switch (key) {
        // as a broker: the links root has no responder
        'wy/s/downstream' => throw WyrmException.of(Status.disconnected, 'wy/s/downstream/~meta is not connected'),
        'wy/s/downstream/m' => metaM,
        'wy/s/downstream/c' => metaC,
        'wy/s/downstream/c/temp' => metaT,
        _ => NodeMeta(),
      };
  /// `m` holds only a point (no tree children); `c` holds a device too.
  @override
  Future<List<Child>> children(String key) async => switch (key) {
        'wy/s/downstream/m' => [Child('temp', metaT)],
        'wy/s/downstream/c' => [Child('dev', NodeMeta(hasChildren: true)), Child('temp', metaT)],
        _ => [],
      };
  final histories = <(String, String, String?, String?)>[];

  /// `temp` has three recorded rows, the last one bad.
  @override
  Future<List<HistRow>> history(String key,
      {required String from, String to = '', String? agg, String? window, int? limit}) async {
    histories.add((key, from, agg, window));
    if (key != 'wy/s/downstream/c/temp') return [];
    if (agg != null) return [const HistRow(1760000000000000, VFloat(21.5))];
    return const [
      HistRow(1760000000000000, VFloat(21.0), Quality.good),
      HistRow(1760000001000000, VFloat(22.0), Quality.good),
      HistRow(1760000002000000, VNull(), Quality.bad),
    ];
  }

  @override
  Future<void> close() async {}
}

/// `c` with two config-level values: a bool and an enum; setting the enum
/// to `warn` is refused.
class SettableApi extends ActApi {
  final sets = <(String, Value)>[];
  static final opt = NodeMeta(ty: TypeCode.bool_, writable: Writable.config, hasChildren: false);
  static final lvl = NodeMeta(
      ty: TypeCode.enum_, writable: Writable.config, enumValues: ['debug', 'info', 'warn'], hasChildren: false);

  /// Units: the node's own, and the DSA `@unit` attribute.
  static final temp = NodeMeta(ty: TypeCode.number, unit: const TText('°C'), hasChildren: false);
  static final energy = NodeMeta(ty: TypeCode.number, attr: {'unit': const VStr('kWh')}, hasChildren: false);

  @override
  Future<List<Child>> children(String key) async => key == 'wy/s/downstream/c'
      ? [Child('opt', opt), Child('lvl', lvl), Child('temp', temp), Child('energy', energy)]
      : super.children(key);

  @override
  Future<NodeMeta> meta(String key) async => switch (key) {
        'wy/s/downstream/c/opt' => opt,
        'wy/s/downstream/c/lvl' => lvl,
        _ => super.meta(key),
      };

  @override
  Stream<ValEvent> subscribe(String pattern) => switch (pattern) {
        'wy/s/downstream/c/opt' => Stream.value(ValSample(pattern, const Sample(VBool(false), t: 1))),
        'wy/s/downstream/c/lvl' => Stream.value(ValSample(pattern, const Sample(VInt(1), t: 1))),
        'wy/s/downstream/c/temp' => Stream.value(ValSample(pattern, const Sample(VFloat(21.5), t: 1))),
        'wy/s/downstream/c/energy' => Stream.value(ValSample(pattern, const Sample(VInt(7), t: 1))),
        _ => const Stream.empty(),
      };

  @override
  Future<void> set(String key, Value value) async {
    sets.add((key, value));
    if (key.endsWith('/lvl') && value == const VInt(2)) {
      throw WyrmException.of(Status.permissionDenied, 'not allowed');
    }
  }
}

/// A recorded point (ADR 0016): `temp` has `has_history` in the list and
/// `attr.history` (the broker's historian, and a link's own store) in its
/// meta.
class RecordedApi extends SettableApi {
  static const store = 'wy/s/sys/history/g/w1';
  static const linkStore = 'wy/s/downstream/rec/temp';

  @override
  Future<List<Child>> children(String key) async => key == 'wy/s/downstream/c'
      ? [
          Child('temp', NodeMeta(ty: TypeCode.number, unit: const TText('°C'), hasChildren: false, hasHistory: true)),
          Child('energy', SettableApi.energy),
        ]
      : super.children(key);

  @override
  Future<NodeMeta> meta(String key) async => key == 'wy/s/downstream/c/temp'
      ? NodeMeta(ty: TypeCode.number, unit: const TText('°C'), attr: {
          'history': const VArray([VStr(store), VStr(linkStore)])
        })
      : super.meta(key);
}

/// A site whose `storage` is empty at first, then holds an empty folder
/// `test` (as `view=list` sends it: `wy:folder`, `has_children` false).
class StorageApi extends ActApi {
  static final emptyFolder = NodeMeta(is_: const TCode(1), hasChildren: false);

  @override
  Stream<ListUpdate> list(String key) {
    if (key != 'wy/s/storage') return super.list(key);
    final c = StreamController<ListUpdate>();
    lists[key] = c;
    c.add(ListRefreshed([]));
    return c.stream;
  }
}

/// A chain as in the demo: central lists edge (`@root wy/edge`), edge lists
/// plant (`@root wy/plant`), plant has `line/g0/p0`.
class ChainApi extends ActApi {
  static NodeMeta ref(String site) => NodeMeta(hasChildren: true, attr: {'root': VStr('wy/$site')});
  static final point = NodeMeta(ty: TypeCode.number, hasChildren: false);

  static List<Child> kids(String key) => switch (key) {
        'wy/central/downstream' => [Child('edge', ref('edge'))],
        'wy/edge/downstream' => [Child('plant', ref('plant'))],
        'wy/plant/downstream' => [Child('line', NodeMeta(hasChildren: true))],
        'wy/plant/downstream/line' => [Child('g0', NodeMeta(hasChildren: true))],
        'wy/plant/downstream/line/g0' => [Child('p0', point)],
        _ => <Child>[],
      };

  @override
  Stream<ListUpdate> list(String key) {
    final c = StreamController<ListUpdate>();
    lists[key] = c;
    c.add(ListRefreshed(kids(key)));
    return c.stream;
  }

  @override
  Future<List<Child>> children(String key) async => kids(key);

  @override
  Future<NodeMeta> meta(String key) async =>
      key.endsWith('/p0') ? point : NodeMeta(hasChildren: true);
}

/// `m` has an action with time params (spec 02 0.2.4): a range, an
/// interval to choose, a duration in seconds.
class TimeApi extends ActApi {
  static final metaTime = NodeMeta(hasChildren: true, actions: {
    'get_history': ActionMeta(params: {
      'timerange': ParamMeta(ty: TypeCode.string, required: true, editor: 'daterange'),
      'interval': ParamMeta(ty: TypeCode.string, enumValues: ['none', '1m', '1h']),
      'flush': ParamMeta(ty: TypeCode.number, editor: 'duration'),
    }),
  });

  @override
  Stream<ListUpdate> list(String key) {
    final c = StreamController<ListUpdate>();
    lists[key] = c;
    if (key == 'wy/s/downstream') c.add(ListRefreshed([Child('m', metaTime)]));
    return c.stream;
  }

  @override
  Future<NodeMeta> meta(String key) async => key == 'wy/s/downstream/m' ? metaTime : super.meta(key);
}

/// A flow `f` (timer t → publish out) under `wy/s/dataflows`, with a small
/// node-type catalog; `validate` answers ok, `deploy` is recorded.
class FlowApi extends ActApi {
  static VMap param(String name, String type, {bool required = false}) =>
      VMap({'name': VStr(name), 'type': VStr(type), 'required': VBool(required), 'description': const VStr('')});
  static VMap type(String ty, List<String> ins, List<String> outs, List<VMap> params) => VMap({
        'type': VStr(ty),
        'category': const VStr('Test'),
        'description': VStr('$ty block'),
        'inputs': VArray([for (final i in ins) VStr(i)]),
        'outputs': VArray([for (final o in outs) VStr(o)]),
        'params': VArray(params),
      });

  static final catalog = VArray([
    type('timer', [], ['out'], [param('period_ms', 'number', required: true)]),
    type('scale', ['in'], ['out'], [param('k', 'number')]),
    type('publish', ['in'], [], [param('node', 'string', required: true)]),
  ]);

  static final def = VMap({
    'id': const VStr('f'),
    'version': const VInt(3),
    'nodes': VMap({
      't': VMap({'type': const VStr('timer'), 'period_ms': const VInt(500)}),
      'out': VMap({'type': const VStr('publish'), 'node': const VStr('ticks')}),
    }),
    'edges': VArray([
      VArray([const VStr('t.out'), const VStr('out.in')])
    ]),
    'layout': VMap({
      't': VArray([const VInt(20), const VInt(20)]),
      'out': VArray([const VInt(400), const VInt(20)]),
    }),
    'policy': VMap({'queue': const VInt(64)}),
  });

  @override
  Stream<ListUpdate> list(String key) {
    final c = StreamController<ListUpdate>();
    lists[key] = c;
    if (key == 'wy/s/dataflows') c.add(ListRefreshed([Child('f', NodeMeta(hasChildren: true))]));
    return c.stream;
  }

  @override
  Future<NodeMeta> meta(String key) async => NodeMeta(hasChildren: true);

  @override
  Stream<Value> invoke(String key, String action, [Value? args]) {
    invoked.add((key, action, args));
    return switch (action) {
      'node_types' => Stream.value(catalog),
      'history' => Stream.value(VArray([def])),
      'validate' => Stream.value(VMap({'ok': const VBool(true)})),
      _ => const Stream.empty(),
    };
  }
}

/// Select a row that expands: one tap counts after the double-tap timeout.
Future<void> select(WidgetTester t, String name) async {
  await t.tap(find.text(name));
  await t.pumpAndSettle(const Duration(milliseconds: 400));
}

Future<void> rightClick(WidgetTester t, Finder f) async {
  await t.tap(f, buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await t.pumpAndSettle();
}

/// One gateway connection of [GatewayFake]: answers `list` with the fake's
/// children; the test drops it, as a broker rebuild closes the socket.
class FakeSocket implements FrameTransport {
  final GatewayFake gw;
  final _in = StreamController<Value>();
  FakeSocket(this.gw);

  @override
  Stream<Value> get incoming => _in.stream;

  void _reply(int id, Map<String, Value> f) => scheduleMicrotask(() {
        if (!_in.isClosed) _in.add(VMap({'id': VInt(id), ...f}));
      });

  @override
  void send(Map<String, Value> frame) {
    final id = (frame['id'] as VInt).v;
    switch ((frame['op'] as VStr).v) {
      case 'list':
        _reply(id, {'ok': const VBool(true)});
        _reply(id, {
          'event': VMap({
            'type': const VStr('refreshed'),
            'children': VArray([
              for (final n in gw.children)
                VMap({'name': VStr(n), 'meta': VBytes(NodeMeta(hasChildren: true).toCbor())}),
            ]),
          }),
        });
      case 'children':
        _reply(id, {'ok': const VBool(true), 'result': const VArray([])});
      default:
        _reply(id, {'ok': const VBool(true)});
    }
  }

  void drop() => _in.close();

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }
}

class GatewayFake {
  var children = ['m1'];
  var refuse = 0;
  FakeSocket? socket;

  Future<FrameClient> connect() async {
    if (refuse > 0) {
      refuse--;
      throw StateError('connection refused');
    }
    return FrameClient(socket = FakeSocket(this));
  }
}

void main() {
  testWidgets('menu: hover shows params, Invoke runs the action', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    expect(find.text('m'), findsOneWidget);

    // One mouse for the whole scenario: right-click the row, then hover.
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.down(t.getCenter(find.text('m')));
    await mouse.up();
    await t.pumpAndSettle();
    expect(find.text('count'), findsOneWidget);
    expect(find.text('reset'), findsOneWidget);

    // Hover over an action with params: its fields appear.
    await mouse.moveTo(t.getCenter(find.text('count')));
    await t.pumpAndSettle();
    expect(find.text('n'), findsOneWidget, reason: 'param field on hover, no required mark');
    await t.enterText(find.byType(TextField).last, '3');
    await t.tap(find.text('Invoke'));
    await t.pumpAndSettle();
    expect(api.invoked.single.$2, 'count');
    expect(api.invoked.single.$3, VMap({'n': const VInt(3)}));
    expect(find.text('output'), findsOneWidget);
    expect(find.text('7'), findsOneWidget, reason: 'result in the output box');

    // The form opens level with the hovered row's panel edge: up by the
    // menu's border and padding (3 px), so on the first row its top is the
    // menu's top, not a few pixels lower.
    bool isType(Widget w, String type) => w.runtimeType.toString() == type;
    final row = t.getRect(find.ancestor(of: find.text('count'), matching: find.byWidgetPredicate((w) => isType(w, '_MenuItem'))));
    final form = t.getRect(find.byWidgetPredicate((w) => isType(w, '_ActionFlyout')));
    expect(form.top, row.top - 3);

    // An error shows its message alone, in an error row.
    await mouse.moveTo(t.getCenter(find.text('reset')));
    await t.pumpAndSettle();
    await t.tap(find.text('Invoke'));
    await t.pumpAndSettle();
    expect(find.text('error'), findsOneWidget);
    expect(find.text('test exists'), findsOneWidget);
    expect(find.textContaining('WyrmException'), findsNothing);
  });

  testWidgets('an action without params also opens its form; Invoke runs it', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    await rightClick(t, find.text('m'));
    await t.tap(find.text('reset'));
    await t.pumpAndSettle();
    expect(api.invoked, isEmpty, reason: 'nothing runs before Invoke');
    expect(find.text('output'), findsNothing, reason: 'no declared result, no output row');
    await t.tap(find.text('Invoke'));
    await t.pumpAndSettle();
    expect(api.invoked.single.$2, 'reset');
  });

  testWidgets('a triangle where the node may hold children; points in Metrics have a menu', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    // m holds only a point, c a device too: both may hold children, both
    // expand; the point stays out of the tree
    await t.tap(find.text('m'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('m'));
    await t.pumpAndSettle();
    expect(api.lists.keys, contains('wy/s/downstream/m'));
    await t.tap(find.text('c'));
    await t.pump(const Duration(milliseconds: 50));
    await select(t, 'c');
    expect(api.lists.keys, contains('wy/s/downstream/c'));
    // select c (one click): Metrics shows its point; a right click opens its menu
    await t.tap(find.text('c'));
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('temp'), findsOneWidget);
    await rightClick(t, find.text('temp'));
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Copy Path'), findsOneWidget);
  });

  testWidgets('an empty site section expands; a folder added to it shows and expands, empty too', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = StorageApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s'))));
    await t.pumpAndSettle();
    Future<void> doubleTap(String name) async {
      await t.tap(find.text(name));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.text(name));
      await t.pumpAndSettle();
    }

    // storage holds nothing yet: it opens all the same (its own meta says
    // it holds children), so a node added later shows
    await doubleTap('storage');
    expect(api.lists.keys, contains('wy/s/storage'));
    api.lists['wy/s/storage']!.add(ChildAdded(Child('test', StorageApi.emptyFolder)));
    await t.pumpAndSettle();
    expect(find.text('test'), findsOneWidget);
    // an empty folder is a folder, not a leaf
    await doubleTap('test');
    expect(api.lists.keys, contains('wy/s/storage/test'));
  });

  testWidgets('Copy Path copies the tree route of a point two brokers down (as DSA)', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    final api = ChainApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/central'))));
    await t.pumpAndSettle();
    Future<void> open(Finder f) async {
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await open(find.text('downstream').first); // central's
    await open(find.text('edge'));
    await open(find.text('downstream').at(1)); // edge's
    await open(find.text('plant'));
    await open(find.text('downstream').at(2)); // plant's
    await open(find.text('line'));
    await t.tap(find.text('g0'));
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    await rightClick(t, find.text('p0'));
    await t.tap(find.text('Copy Path'));
    await t.pumpAndSettle();
    const route = 'wy/central/downstream/edge/downstream/plant/downstream/line/g0';
    expect(copied, '$route/p0');
    // the folder in the tree too
    await rightClick(t, find.text('g0'));
    await t.tap(find.text('Copy Path'));
    await t.pumpAndSettle();
    expect(copied, route);
  });

  testWidgets('time params: a range from the list, a duration in a unit, an interval to choose', (t) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    final api = TimeApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.down(t.getCenter(find.text('m')));
    await mouse.up();
    await t.pumpAndSettle();
    await mouse.moveTo(t.getCenter(find.text('get_history')));
    await t.pumpAndSettle();
    // the range: the calendar button opens the list; Last 24 Hours fills it
    await t.tap(find.byIcon(Icons.calendar_month));
    await t.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    await t.tap(find.text('Last 24 Hours'));
    await t.pumpAndSettle();
    // the duration: 5 in minutes
    final fields = find.byType(TextField);
    await t.enterText(fields.last, '5');
    await t.tap(find.text('s'));
    await t.pumpAndSettle();
    await t.tap(find.text('min'));
    await t.pumpAndSettle();
    await t.tap(find.text('Invoke'));
    await t.pumpAndSettle();
    final args = api.invoked.single.$3! as VMap;
    final range = (args.v['timerange']! as VStr).v.split('/');
    final from = DateTime.parse(range[0]), to = DateTime.parse(range[1]);
    expect(to.difference(from), const Duration(hours: 24));
    expect(range[0], endsWith('Z'));
    expect(args.v['flush'], const VInt(300));
    expect(args.v['interval'], const VStr('none'));
  });

  testWidgets('dataflow editor: load, add from the palette, link, edit, deploy', (t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    final api = FlowApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/dataflows'))));
    await t.pumpAndSettle();
    await rightClick(t, find.text('f'));
    await t.tap(find.text('Edit Dataflow'));
    await t.pumpAndSettle(const Duration(milliseconds: 500));
    // the blocks of the flow, its wire, and the check
    expect(find.text('t  ·  timer'), findsOneWidget);
    expect(find.text('out  ·  publish'), findsOneWidget);
    expect(find.text('✓ checks'), findsOneWidget);
    // a scale from the palette, then a wire t.out → scale1.in
    await t.tap(find.text('scale'));
    await t.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('scale1  ·  scale'), findsOneWidget);
    final from = t.getCenter(find.byKey(const ValueKey('out:t.out')));
    final to = t.getCenter(find.byKey(const ValueKey('in:scale1.in')));
    await t.dragFrom(from, to - from);
    await t.pumpAndSettle(const Duration(milliseconds: 500));
    // edit t's period in its properties
    await t.tap(find.text('t  ·  timer'));
    await t.pumpAndSettle();
    final period = find.ancestor(of: find.text('500'), matching: find.byType(TextField));
    await t.enterText(period, '250');
    await t.pumpAndSettle(const Duration(milliseconds: 500));
    await t.tap(find.text('Deploy *'));
    await t.pumpAndSettle();
    final deploy = api.invoked.lastWhere((c) => c.$2 == 'deploy');
    expect(deploy.$1, 'wy/s/dataflows');
    final d = ((deploy.$3! as VMap).v['def']! as VMap).v;
    expect(d['version'], const VInt(4));
    final nodes = (d['nodes']! as VMap).v;
    expect((nodes['t']! as VMap).v['period_ms'], const VInt(250));
    expect((nodes['scale1']! as VMap).v['type'], const VStr('scale'));
    final edges = [
      for (final e in (d['edges']! as VArray).v) [for (final x in (e as VArray).v) (x as VStr).v].join('→')
    ];
    // the timer now feeds the scale; out keeps its link (an output may feed many)
    expect(edges, containsAll(['t.out→out.in', 't.out→scale1.in']));
    expect((d['layout']! as VMap).v.keys, containsAll(['t', 'out', 'scale1']));
    expect(d['policy'], isNotNull, reason: 'fields the editor does not know are kept');
    expect(find.text('deployed version 4'), findsOneWidget);
  });

  testWidgets('groups: New and Edit submenus, names for people, password field', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.down(t.getCenter(find.text('c')));
    await mouse.up();
    await t.pumpAndSettle();
    // top level: New ▸, Restart, Edit ▸; the handshake is hidden
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
    expect(find.text('hello'), findsNothing);
    expect(find.text('Add Device'), findsNothing, reason: 'inside New');
    final top = [for (final w in ['New', 'Restart', 'Edit']) t.getTopLeft(find.text(w)).dy];
    expect(top, orderedEquals([...top]..sort()), reason: 'New, top level, Edit');

    await mouse.moveTo(t.getCenter(find.text('New')));
    await t.pumpAndSettle();
    expect(find.text('Add Device'), findsOneWidget);
    expect(find.text('Add Point'), findsOneWidget);
    // the form: labels for people, required mark, hint
    await mouse.moveTo(t.getCenter(find.text('Add Device')));
    await t.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Slave ID'), findsOneWidget);
    // a password field hides its text
    await mouse.moveTo(t.getCenter(find.text('Add Point')));
    await t.pumpAndSettle();
    final pw = t.widgetList<TextField>(find.byType(TextField)).where((f) => f.obscureText).toList();
    expect(pw, hasLength(1));
    expect(pw.single.decoration?.hintText, 'secret (optional)');
    // a file param is a picker, not a text field
    expect(find.text('Map file'), findsOneWidget);
    expect(find.text('Choose File…'), findsOneWidget);
    // an enum field opens its options over the menu and takes a pick
    await t.tap(find.text('coil'));
    await t.pumpAndSettle();
    expect(find.text('holding'), findsOneWidget);
    await t.tap(find.text('holding'));
    await t.pumpAndSettle();
    expect(find.text('holding'), findsOneWidget);
    expect(find.text('coil'), findsNothing);
  });

  testWidgets('a result of records is a table with columns', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    await rightClick(t, find.text('m'));
    await t.tap(find.text('History'));
    await t.pumpAndSettle();
    expect(find.text('Null'), findsOneWidget, reason: 'output before Invoke');
    await t.tap(find.text('Invoke'));
    await t.pumpAndSettle();
    // a table result: a "Table.." box that opens the table window
    await t.tap(find.text('Table..'));
    await t.pumpAndSettle();
    // nested records become columns: one value per cell
    expect(find.text('rev'), findsOneWidget);
    expect(find.text('params.points'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.text('rev'), findsNothing);
  });

  testWidgets('View History on a point: rows, a rollup, the window closes', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    // a folder has no "View History"
    await rightClick(t, find.text('c'));
    expect(find.text('View History'), findsNothing);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    // select c: its point temp is in Metrics with a menu
    await select(t, 'c');
    await rightClick(t, find.text('temp').last);
    await t.tap(find.text('View History'));
    await t.pumpAndSettle();
    expect(api.histories.last.$1, 'wy/s/downstream/c/temp');
    expect(find.text('3 rows'), findsOneWidget);
    expect(find.text('2025-10-09T08:53:20.000Z'), findsWidgets, reason: 'UTC time of the first row');
    expect(find.text('bad'), findsOneWidget);
    // a rollup: one row per range
    await t.tap(find.text('none').last);
    await t.pumpAndSettle();
    await t.tap(find.text('avg').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Load'));
    await t.pumpAndSettle();
    expect(api.histories.last.$3, 'avg');
    expect(find.text('1 rows'), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.textContaining('History: '), findsNothing);
  });

  testWidgets('a lost gateway connection: Reconnecting…, then the tree again', (t) async {
    final gw = GatewayFake();
    final api = await ReconnectingClient.open(gw.connect, maxDelay: const Duration(milliseconds: 10));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pump();
    expect(find.text('m1'), findsOneWidget);

    // the broker rebuilds (an Authorize in sys/quarantine): the socket
    // closes, the first connect is refused, the second one is up
    gw
      ..children = ['m1', 'm2']
      ..refuse = 1;
    gw.socket!.drop();
    // the close reaches the client after this frame; the next one shows it
    await t.pump();
    await t.pump();
    expect(find.text('Reconnecting…'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 20));
    await t.pump();
    expect(find.text('Reconnecting…'), findsNothing);
    expect(find.text('m2'), findsOneWidget);
    expect(find.textContaining('closed'), findsNothing);
    // not awaited: an awaited stream close in a widget test hangs its end
    unawaited(api.close());
    await t.pump();
  });

  testWidgets('Metrics of a links root: no ~meta call, no error', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s'))));
    await t.pumpAndSettle();
    await t.tap(find.text('downstream'));
    await t.pumpAndSettle();
    expect(find.textContaining('not connected'), findsNothing);
    expect(find.textContaining('WyrmException'), findsNothing);
  });

  testWidgets('Metrics: config values are set from lists (a bool too, as text); a refusal shows', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = SettableApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    await select(t, 'c');
    // bool: its value as text, then the list true / false
    expect(find.byType(Switch), findsNothing);
    await t.tap(find.text('false'));
    await t.pumpAndSettle();
    await t.tap(find.text('true').last);
    await t.pumpAndSettle();
    expect(api.sets, [('wy/s/downstream/c/opt', const VBool(true))]);
    // enum: the label, then the list; a refused choice shows its message
    await t.tap(find.text('info'));
    await t.pumpAndSettle();
    await t.tap(find.text('warn').last);
    await t.pumpAndSettle();
    expect(api.sets.last, ('wy/s/downstream/c/lvl', const VInt(2)));
    expect(find.text('not allowed'), findsOneWidget);
    expect(find.textContaining('WyrmException'), findsNothing);
  });

  testWidgets('an empty list stays a list: shown dimmed, not typed, not sent', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    await rightClick(t, find.text('m'));
    await t.tap(find.text('Deauthorize'));
    await t.pumpAndSettle();
    expect(find.text('no external links'), findsOneWidget);
    // tapping it opens nothing (no choices)
    await t.tap(find.text('no external links'));
    await t.pumpAndSettle();
    await t.tap(find.text('Invoke'));
    await t.pumpAndSettle();
    final (_, action, args) = api.invoked.last;
    expect(action, 'deauthorize');
    expect((args as VMap).v.containsKey('link'), isFalse);
  });

  testWidgets('Metrics write the unit after numbers: own unit and @unit', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: SettableApi(), rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    await select(t, 'c');
    expect(find.text('21.50 °C'), findsOneWidget);
    expect(find.text('7 kWh'), findsOneWidget);
  });

  testWidgets('a recorded point has a history mark; it opens its history from the store', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    final api = RecordedApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    await select(t, 'c');
    final mark = find.byKey(const ValueKey('history-mark:wy/s/downstream/c/temp'));
    expect(mark, findsOneWidget);
    expect(find.byKey(const ValueKey('history-mark:wy/s/downstream/c/energy')), findsNothing);
    await t.tap(mark);
    await t.pumpAndSettle();
    expect(find.text('History: wy/s/downstream/c/temp'), findsOneWidget);
    // the broker's historian answers at the point itself (rights as the value)
    expect(api.histories.last.$1, 'wy/s/downstream/c/temp');
    // two stores: a choice; the link's store is read at its own key
    await t.tap(find.text(RecordedApi.store));
    await t.pumpAndSettle();
    await t.tap(find.text(RecordedApi.linkStore).last);
    await t.pumpAndSettle();
    expect(api.histories.last.$1, RecordedApi.linkStore);
  });
}
