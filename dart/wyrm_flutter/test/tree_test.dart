import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_flutter/wyrm_flutter.dart';

/// A [WyrmApi] driven by the test: one controller per open stream.
class FakeApi implements WyrmApi {
  final lists = <String, StreamController<ListUpdate>>{};
  final subs = <String, StreamController<ValEvent>>{};
  final listCancels = <String>[];
  final subCancels = <String>[];

  @override
  Stream<ListUpdate> list(String key) {
    final c = StreamController<ListUpdate>(onCancel: () {
      listCancels.add(key);
      lists.remove(key);
    });
    lists[key] = c;
    return c.stream;
  }

  @override
  Stream<ValEvent> subscribe(String pattern) {
    final c = StreamController<ValEvent>(onCancel: () {
      subCancels.add(pattern);
      subs.remove(pattern);
    });
    subs[pattern] = c;
    return c.stream;
  }

  @override
  Future<void> set(String key, Value value) async {}
  @override
  Stream<Value> invoke(String key, String action, [Value? args]) => const Stream.empty();
  @override
  Future<NodeMeta> meta(String key) async => NodeMeta();
  @override
  Future<List<Child>> children(String key) async => [];
  @override
  Future<List<HistRow>> history(String key,
          {required String from, String to = '', String? agg, String? window, int? limit}) async =>
      [];
  @override
  Future<void> close() async {}
}

Child folder(String n) => Child(n, NodeMeta(is_: const TCode(1), hasChildren: true));
Child point(String n) => Child(n, NodeMeta(is_: const TCode(2), ty: TypeCode.number, unit: const TText('°C'), hasChildren: false));

void main() {
  testWidgets('lazy children, live values, cancel on collapse', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WyrmTree(api: api, rootKey: 'wy/s/downstream/mock'))));

    // One list on the root, nothing else yet.
    expect(api.lists.keys, ['wy/s/downstream/mock']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    api.lists['wy/s/downstream/mock']!.add(ListRefreshed([folder('g0'), folder('g1')]));
    await tester.pump();
    expect(find.text('g0'), findsOneWidget);
    expect(find.text('g1'), findsOneWidget);
    expect(api.lists.keys, ['wy/s/downstream/mock']); // collapsed: no list below

    // Expand g0: its own list.
    await tester.tap(find.text('g0'));
    await tester.pump();
    expect(api.lists.keys, contains('wy/s/downstream/mock/g0'));
    api.lists['wy/s/downstream/mock/g0']!.add(ListRefreshed([point('p0')]));
    await tester.pump();
    expect(find.text('p0'), findsOneWidget);

    // The visible leaf subscribes its exact key.
    expect(api.subs.keys, ['wy/s/downstream/mock/g0/p0']);
    expect(find.text('—'), findsOneWidget);
    api.subs['wy/s/downstream/mock/g0/p0']!
        .add(const ValSample('wy/s/downstream/mock/g0/p0', Sample(VFloat(21.456), t: 1)));
    await tester.pump();
    expect(find.text('21.46 °C'), findsOneWidget);

    api.subs['wy/s/downstream/mock/g0/p0']!.add(
        const ValSample('wy/s/downstream/mock/g0/p0', Sample(VFloat(3), q: Quality.bad, t: 2), qual: 'bad/comm_fail'));
    await tester.pump();
    expect(find.text('3.00 °C (bad/comm_fail)'), findsOneWidget);

    // Added / removed children.
    api.lists['wy/s/downstream/mock']!.add(ChildAdded(folder('g2')));
    await tester.pump();
    expect(find.text('g2'), findsOneWidget);
    api.lists['wy/s/downstream/mock']!.add(const ChildRemoved('g1'));
    await tester.pump();
    expect(find.text('g1'), findsNothing);

    // Collapse g0: its list and the leaf subscription end.
    await tester.tap(find.text('g0'));
    await tester.pump();
    expect(api.listCancels, ['wy/s/downstream/mock/g0']);
    expect(api.subCancels, ['wy/s/downstream/mock/g0/p0']);
    expect(find.text('p0'), findsNothing);

    // Removing the tree cancels the rest.
    await tester.pumpWidget(const SizedBox());
    expect(api.lists, isEmpty);
    expect(api.subs, isEmpty);
  });

  testWidgets('list error is shown', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WyrmTree(api: api, rootKey: 'wy/s/downstream'))));
    api.lists['wy/s/downstream']!.addError(WyrmException.of(Status.permissionDenied, 'permission denied'));
    await tester.pump();
    expect(find.textContaining('permission denied'), findsOneWidget);
  });

  test('editText and parseValueText: maps, arrays, binary and numbers round-trip', () {
    final m = VMap({'a': const VInt(1), 'b': VArray([const VStr('x'), const VBool(true), const VFloat(0.5)])});
    expect(editText(m, null), '{"a":1,"b":["x",true,0.5]}');
    expect(parseValueText(editText(m, null), TypeCode.map), m);
    expect(parseValueText('[1, "two", null]', TypeCode.array),
        const VArray([VInt(1), VStr('two'), VNull()]));
    final bin = VBytes(Uint8List.fromList([0x0a, 0x1b]));
    expect(editText(bin, null), '0x0a1b');
    expect(parseValueText('0x0A1B', TypeCode.binary), bin);
    expect(parseValueText('', TypeCode.binary), VBytes(Uint8List(0)));
    // a number is edited without its unit; one typed with a unit keeps the number
    final temp = NodeMeta(ty: TypeCode.number, unit: const TText('°C'));
    expect(formatValue(const VFloat(21.5), temp), '21.50 °C');
    expect(editText(const VFloat(21.5), temp), '21.5');
    expect(parseValueText('21.50 °C', TypeCode.number), const VFloat(21.5));
    expect(parseValueText('7', TypeCode.number), const VInt(7));
    // dynamic: JSON when it is JSON, else text
    expect(parseValueText('{"on": true}', TypeCode.dynamic_), VMap({'on': const VBool(true)}));
    expect(parseValueText('hello', TypeCode.dynamic_), const VStr('hello'));
    expect(parseValueText(' text ', TypeCode.string), const VStr('text'));
    // what is not such a value is refused, never sent as 0 or as text
    for (final (t, ty) in [
      ('abc', TypeCode.number),
      ('[1]', TypeCode.map),
      ('{"a": 1', TypeCode.map),
      ('{}', TypeCode.array),
      ('0x1', TypeCode.binary),
      ('zz', TypeCode.binary),
      ('yes', TypeCode.bool_),
    ]) {
      expect(() => parseValueText(t, ty), throwsFormatException, reason: '$t as $ty');
    }
  });

  test('formatValue', () {
    final e = NodeMeta(ty: TypeCode.enum_, enumValues: ['off', 'on']);
    expect(formatValue(const VInt(1), e), 'on');
    expect(formatValue(const VBool(true), null), 'true');
    expect(formatValue(const VFloat(1.5), NodeMeta(cfg: {'precision': const VInt(1)})), '1.5');
  });
}
