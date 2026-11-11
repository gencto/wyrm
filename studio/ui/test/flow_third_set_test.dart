import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/rows_editor.dart';
import 'package:ui/flows/suggest_field.dart';
import 'package:ui/overlays/value_viewer.dart';

import 'frames/harness.dart';

/// The editors of the third set of blocks (ADR 0044, flow-editor.md §6): a
/// list of maps as rows, a text with its usual values, a command drawn as
/// a button, and a table in the value viewer.
void main() {
  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(child));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<List<String>> inspector(
    WidgetTester tester,
    List<InspectorRowVm> rows,
  ) async {
    final changed = <String>[];
    await show(
      tester,
      SizedBox(
        width: 340,
        child: FieldInspector(
          footer: const [],
          rows: rows,
          onChanged: (id, v) => changed.add('$id=$v'),
          onUnbind: (_) {},
          onBind: (_, _) {},
          onProblem: (_) {},
        ),
      ),
    );
    return changed;
  }

  const aggregates = RowsEditorVm(
    id: 'p:aggregates',
    columns: [
      RowsColumnVm('column', 'Column'),
      RowsColumnVm('method', 'Method', choices: ['max', 'min', 'count']),
      RowsColumnVm('as', 'As'),
    ],
    rows: [
      {'column': 'v', 'method': 'max', 'as': 't_max'},
    ],
  );

  testWidgets('a list of maps is rows: type, add, remove, each a JSON list', (
    tester,
  ) async {
    final changed = await inspector(tester, const [
      InspectorRowVm(
        id: 'p:aggregates',
        name: 'Aggregates',
        editor: FieldEditorVm.rows,
        rows: aggregates,
      ),
    ]);
    expect(find.text('Column'), findsOneWidget);
    expect(find.text('t_max'), findsOneWidget);
    // The list takes the inspector's width, under its label.
    final editor = find.byKey(const ValueKey('rows-editor-p:aggregates'));
    expect(tester.getSize(editor).width, greaterThan(280));

    await tester.enterText(
      find.byKey(const ValueKey('rows-p:aggregates-0-as')),
      'peak',
    );
    expect(jsonDecode(changed.last.split('=').skip(1).join('=')), [
      {'column': 'v', 'method': 'max', 'as': 'peak'},
    ]);

    await tester.tap(find.byKey(const ValueKey('rows-p:aggregates-add')));
    await tester.pump();
    expect(jsonDecode(changed.last.substring('p:aggregates='.length)), [
      {'column': 'v', 'method': 'max', 'as': 'peak'},
      {'column': '', 'method': '', 'as': ''},
    ]);

    await tester.tap(find.byKey(const ValueKey('rows-p:aggregates-remove-0')));
    await tester.pump();
    expect(jsonDecode(changed.last.substring('p:aggregates='.length)), [
      {'column': '', 'method': '', 'as': ''},
    ]);
  });

  testWidgets('a time zone is typed or picked from its menu', (tester) async {
    final changed = await inspector(tester, const [
      InspectorRowVm(
        id: 'p:time_zone',
        name: 'Time zone',
        editor: FieldEditorVm.suggest,
        value: 'UTC',
        choices: ['auto', 'UTC', 'Europe/Kyiv'],
      ),
    ]);
    await tester.tap(find.byKey(const ValueKey('suggest-menu-p:time_zone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/Kyiv').last);
    await tester.pumpAndSettle();
    expect(changed, ['p:time_zone=Europe/Kyiv']);
    expect(find.text('Europe/Kyiv'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('suggest-p:time_zone')),
      '+02:00',
    );
    expect(changed.last, 'p:time_zone=+02:00', reason: 'any text is taken');
  });

  testWidgets('a suggest field follows its value, not while it is typed in', (
    tester,
  ) async {
    Widget field(String v) => SizedBox(
      width: 300,
      child: SuggestField(
        vm: SuggestFieldVm(id: 'r', value: v, choices: const ['today']),
        decoration: const BoxDecoration(),
        onChanged: (_) {},
      ),
    );
    await show(tester, field('today'));
    await tester.pumpWidget(frame(field('lastWeek')));
    expect(find.text('lastWeek'), findsOneWidget);
  });

  testWidgets('a command is a button on the block, with no value', (
    tester,
  ) async {
    await show(
      tester,
      Center(
        child: FlowBlockView(
          vm: const FlowBlockVm(
            id: 'page',
            title: 'page',
            x: 0,
            y: 0,
            type: 'table_page',
            rows: [
              FieldRowVm(
                id: 'in:next',
                label: 'Next',
                name: 'next',
                inPort: 'next',
                inMark: PortMark.free,
                command: true,
              ),
              FieldRowVm(
                id: 'p:page',
                label: 'Page',
                value: '0',
                inPort: 'in.page',
                outPort: 'page',
                inMark: PortMark.free,
                outMark: PortMark.free,
              ),
            ],
          ),
          actions: FlowBlockActions(
            onSelect: (_) {},
            onBind: (_, _, _) {},
            onRebind: (_, _, _, _) {},
            onUnbind: (_, _) {},
            onDropEntry: (_, _, _) {},
            onResize: (_, {required add}) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('command-page-in:next')), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.byKey(const ValueKey('command-page-p:page')), findsNothing);
  });

  testWidgets('a table in the viewer: a header, its rows, the count', (
    tester,
  ) async {
    await show(
      tester,
      Stack(
        children: [
          Positioned.fill(
            child: ValueViewer(
              vm: const ValueViewerVm(
                title: 'h.out',
                type: 'table',
                size: '3 rows · 2 columns',
                content: TableContentVm(
                  columns: ['t', 'v'],
                  rows: [
                    ['2026-11-11 12:00:00', '20.5'],
                    ['2026-11-11 12:00:01', '20.6'],
                  ],
                  note: 'The first 2 of 3 rows',
                ),
                copy: '[]',
              ),
              onClose: () {},
            ),
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('viewer-table')), findsOneWidget);
    expect(find.text('t'), findsOneWidget);
    expect(find.text('20.6'), findsOneWidget);
    expect(find.text('The first 2 of 3 rows'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
