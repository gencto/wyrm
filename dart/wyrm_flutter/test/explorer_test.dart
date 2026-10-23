import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

/// `m` holds only a point until an action adds a folder under it (as
/// `sys/history` ▸ Add Watch Group); the broker then publishes `m`'s meta.
class GrowingApi extends ActApi {
  var grown = false;

  @override
  Future<List<Child>> children(String key) async => key == 'wy/s/downstream/m' && grown
      ? [Child('temp', ActApi.metaT), Child('g', NodeMeta(hasChildren: true))]
      : super.children(key);
}

Future<void> rightClick(WidgetTester t, Finder f) async {
  await t.tap(f, buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await t.pumpAndSettle();
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

  testWidgets('a triangle only where the tree has children; points in Metrics have a menu', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    // m holds only a point: not expandable; c holds a device: expandable
    await t.tap(find.text('m'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('m'));
    await t.pumpAndSettle();
    expect(api.lists.keys, isNot(contains('wy/s/downstream/m')));
    await t.tap(find.text('c'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('c'));
    await t.pumpAndSettle();
    expect(api.lists.keys, contains('wy/s/downstream/c'));
    // select c (one click): Metrics shows its point; a right click opens its menu
    await t.tap(find.text('c'));
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('temp'), findsOneWidget);
    await rightClick(t, find.text('temp'));
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Copy Path'), findsOneWidget);
  });

  testWidgets('a folder added under a node of values makes it expandable', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = GrowingApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    Future<void> doubleTap(String name) async {
      await t.tap(find.text(name));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.text(name));
      await t.pumpAndSettle();
    }

    await doubleTap('m');
    expect(api.lists.keys, isNot(contains('wy/s/downstream/m')), reason: 'only a point yet');
    // an action adds g under m: the broker publishes m's new meta
    api.grown = true;
    api.lists['wy/s/downstream']!.add(ChildChanged(Child('m', ActApi.metaM)));
    await t.pumpAndSettle();
    await doubleTap('m');
    expect(api.lists.keys, contains('wy/s/downstream/m'));
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
    await t.tap(find.text('c'));
    await t.pumpAndSettle();
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

  testWidgets('Metrics: config values are set with a switch and a list; a refusal shows', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = SettableApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    await t.tap(find.text('c'));
    await t.pumpAndSettle();
    // bool: a switch
    await t.tap(find.byType(Switch));
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
    await t.tap(find.text('c'));
    await t.pumpAndSettle();
    expect(find.text('21.50 °C'), findsOneWidget);
    expect(find.text('7 kWh'), findsOneWidget);
  });

  testWidgets('a recorded point has a history mark; it opens its history from the store', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    final api = RecordedApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/downstream'))));
    await t.pumpAndSettle();
    await t.tap(find.text('c'));
    await t.pumpAndSettle();
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
