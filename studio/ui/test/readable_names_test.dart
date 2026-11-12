import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/overlays/node_menu.dart';
import 'package:ui/pages/explorer_page.dart';

import 'frames/explorer.dart';
import 'frames/harness.dart';

/// Names in words with the raw name in reach (owner 2026-11-11).
void main() {
  testWidgets('a field label in words keeps the parameter name as tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      frame(
        Padding(
          padding: const EdgeInsets.all(20),
          child: ParamField(
            vm: ParamFieldVm(
              id: 'a_ab',
              label: 'A ab',
              kind: .text,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('A ab'), findsOneWidget);
    expect(find.byTooltip('a_ab'), findsOneWidget);
  });

  testWidgets('a label that is the name has no tooltip', (tester) async {
    await tester.pumpWidget(
      frame(
        ParamField(
          vm: ParamFieldVm(
            id: 'host',
            label: 'host',
            kind: .text,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('a choice reads in words, the value sent is the raw one', (
    tester,
  ) async {
    Object? sent;
    await tester.pumpWidget(
      frame(
        Padding(
          padding: const EdgeInsets.all(20),
          child: ParamField(
            vm: ParamFieldVm(
              id: 'on',
              label: 'On',
              kind: .choice,
              choices: const ['read_back', 'holding'],
              choiceLabels: const {'read_back': 'Read back'},
              onChanged: (v) => sent = v,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('read_back'), findsNothing);
    await tester.tap(find.text('Read back').last);
    await tester.pumpAndSettle();
    expect(sent, 'read_back');
  });

  testWidgets('a menu item in words keeps the action name as tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      frame(
        Center(
          child: NodeMenu(
            vm: const NodeMenuVm(
              title: 'plc1',
              subtitle: '',
              groups: [
                NodeMenuGroupVm(
                  label: 'Operate',
                  items: [
                    NodeMenuItemVm(
                      id: 'add_watch_path',
                      label: 'Add watch path…',
                      code: 'add_watch_path',
                    ),
                  ],
                ),
              ],
            ),
            onPick: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Add watch path…'), findsOneWidget);
    expect(find.byTooltip('add_watch_path'), findsOneWidget);
  });

  testWidgets('a node with a display name: the title, its name under it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      frame(explorerTitled(title: 'Boiler PLC', titleName: 'plc1')),
    );
    expect(find.text('Boiler PLC'), findsOneWidget);
    final name = tester.widget<Text>(find.byKey(const ValueKey('title-name')));
    expect(name.data, 'plc1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a display name the title is the name alone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(explorerTitled(title: 'plc1')));
    expect(find.byKey(const ValueKey('title-name')), findsNothing);
    expect(find.byType(ExplorerPage), findsOneWidget);
  });
}
