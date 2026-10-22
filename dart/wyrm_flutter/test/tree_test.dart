import 'dart:async';

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
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WyrmTree(api: api, rootKey: 'wy/s/down/mock'))));

    // One list on the root, nothing else yet.
    expect(api.lists.keys, ['wy/s/down/mock']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    api.lists['wy/s/down/mock']!.add(ListRefreshed([folder('g0'), folder('g1')]));
    await tester.pump();
    expect(find.text('g0'), findsOneWidget);
    expect(find.text('g1'), findsOneWidget);
    expect(api.lists.keys, ['wy/s/down/mock']); // collapsed: no list below

    // Expand g0: its own list.
    await tester.tap(find.text('g0'));
    await tester.pump();
    expect(api.lists.keys, contains('wy/s/down/mock/g0'));
    api.lists['wy/s/down/mock/g0']!.add(ListRefreshed([point('p0')]));
    await tester.pump();
    expect(find.text('p0'), findsOneWidget);

    // The visible leaf subscribes its exact key.
    expect(api.subs.keys, ['wy/s/down/mock/g0/p0']);
    expect(find.text('—'), findsOneWidget);
    api.subs['wy/s/down/mock/g0/p0']!
        .add(const ValSample('wy/s/down/mock/g0/p0', Sample(VFloat(21.456), t: 1)));
    await tester.pump();
    expect(find.text('21.46 °C'), findsOneWidget);

    api.subs['wy/s/down/mock/g0/p0']!.add(
        const ValSample('wy/s/down/mock/g0/p0', Sample(VFloat(3), q: Quality.bad, t: 2), qual: 'bad/comm_fail'));
    await tester.pump();
    expect(find.text('3.00 °C (bad/comm_fail)'), findsOneWidget);

    // Added / removed children.
    api.lists['wy/s/down/mock']!.add(ChildAdded(folder('g2')));
    await tester.pump();
    expect(find.text('g2'), findsOneWidget);
    api.lists['wy/s/down/mock']!.add(const ChildRemoved('g1'));
    await tester.pump();
    expect(find.text('g1'), findsNothing);

    // Collapse g0: its list and the leaf subscription end.
    await tester.tap(find.text('g0'));
    await tester.pump();
    expect(api.listCancels, ['wy/s/down/mock/g0']);
    expect(api.subCancels, ['wy/s/down/mock/g0/p0']);
    expect(find.text('p0'), findsNothing);

    // Removing the tree cancels the rest.
    await tester.pumpWidget(const SizedBox());
    expect(api.lists, isEmpty);
    expect(api.subs, isEmpty);
  });

  testWidgets('list error is shown', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WyrmTree(api: api, rootKey: 'wy/s/down'))));
    api.lists['wy/s/down']!.addError(WyrmException.of(Status.permissionDenied, 'permission denied'));
    await tester.pump();
    expect(find.textContaining('permission denied'), findsOneWidget);
  });

  test('formatValue', () {
    final e = NodeMeta(ty: TypeCode.enum_, enumValues: ['off', 'on']);
    expect(formatValue(const VInt(1), e), 'on');
    expect(formatValue(const VBool(true), null), 'true');
    expect(formatValue(const VFloat(1.5), NodeMeta(cfg: {'precision': const VInt(1)})), '1.5');
  });
}
