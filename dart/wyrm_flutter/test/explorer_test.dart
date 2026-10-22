import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_flutter/wyrm_flutter.dart';

/// A [WyrmApi] with one node `wy/s/down/m` that has actions.
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
    'history': ActionMeta(display: 'History'),
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
    if (key == 'wy/s/down') c.add(ListRefreshed([Child('m', metaM), Child('c', metaC)]));
    return c.stream;
  }

  @override
  Stream<ValEvent> subscribe(String pattern) => const Stream.empty();
  @override
  Future<void> set(String key, Value value) async {}
  @override
  Stream<Value> invoke(String key, String action, [Value? args]) {
    invoked.add((key, action, args));
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
        'wy/s/down/m' => metaM,
        'wy/s/down/c' => metaC,
        'wy/s/down/c/temp' => metaT,
        _ => NodeMeta(),
      };
  /// `m` holds only a point (no tree children); `c` holds a device too.
  @override
  Future<List<Child>> children(String key) async => switch (key) {
        'wy/s/down/m' => [Child('temp', metaT)],
        'wy/s/down/c' => [Child('dev', NodeMeta(hasChildren: true)), Child('temp', metaT)],
        _ => [],
      };
  @override
  Future<void> close() async {}
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
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/down'))));
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
  });

  testWidgets('an action without params also opens its form; Invoke runs it', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/down'))));
    await t.pumpAndSettle();
    await rightClick(t, find.text('m'));
    await t.tap(find.text('reset'));
    await t.pumpAndSettle();
    expect(api.invoked, isEmpty, reason: 'nothing runs before Invoke');
    await t.tap(find.text('Invoke'));
    await t.pumpAndSettle();
    expect(api.invoked.single.$2, 'reset');
  });

  testWidgets('a triangle only where the tree has children; points in Metrics have a menu', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/down'))));
    await t.pumpAndSettle();
    // m holds only a point: not expandable; c holds a device: expandable
    await t.tap(find.text('m'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('m'));
    await t.pumpAndSettle();
    expect(api.lists.keys, isNot(contains('wy/s/down/m')));
    await t.tap(find.text('c'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('c'));
    await t.pumpAndSettle();
    expect(api.lists.keys, contains('wy/s/down/c'));
    // select c (one click): Metrics shows its point; a right click opens its menu
    await t.tap(find.text('c'));
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('temp'), findsOneWidget);
    await rightClick(t, find.text('temp'));
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Copy Path'), findsOneWidget);
  });

  testWidgets('groups: New and Edit submenus, names for people, password field', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    final api = ActApi();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/down'))));
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
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WyExplorer(api: api, rootKey: 'wy/s/down'))));
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
}
