import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/overlays/value_viewer.dart';

import 'frames/harness.dart';

/// The value viewer's Edit mode (flow-editor.md §15, owner decision
/// 2026-11-09): an editor fit for the type, Save and Cancel, ⌘/Ctrl+Enter
/// and Esc; a value that cannot be typed says why.
void main() {
  late List<String> saved;
  var closed = 0;

  setUpAll(() => S.load(const Locale('en')));

  setUp(() {
    saved = [];
    closed = 0;
  });

  Widget viewer(ValueViewerVm vm, {String? Function(String)? validate}) =>
      frame(
        Stack(
          children: [
            Positioned.fill(
              child: ValueViewer(
                vm: vm,
                onClose: () => closed++,
                onSave: saved.add,
                validate: validate,
                saveHint: 'Ctrl+Enter saves',
              ),
            ),
          ],
        ),
      );

  void screen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  ValueViewerVm vm({ViewerEditVm? edit, String? locked}) => ValueViewerVm(
    title: 'avg.size_s',
    type: 'number',
    content: const NumberContentVm('30'),
    copy: '30',
    edit: edit,
    locked: locked,
  );

  final edit = find.byKey(const ValueKey('viewer-edit'));
  final editor = find.byKey(const ValueKey('viewer-editor'));
  final save = find.byKey(const ValueKey('viewer-save'));

  testWidgets('a number: Edit, type, Save writes the text and leaves the '
      'editor', (tester) async {
    screen(tester);
    await tester.pumpWidget(
      viewer(
        vm(
          edit: const ViewerEditVm(kind: .number, text: '30'),
        ),
      ),
    );
    expect(editor, findsNothing);
    await tester.tap(edit);
    await tester.pump();
    expect(tester.widget<TextField>(editor).controller!.text, '30');
    expect(find.text('Ctrl+Enter saves'), findsOneWidget);

    await tester.enterText(editor, '45');
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(saved, ['45']);
    expect(editor, findsNothing, reason: 'back to the value');
    expect(edit, findsOneWidget);
  });

  testWidgets('what cannot be saved is said, and Save is off; Ctrl+Enter '
      'saves once it is right', (tester) async {
    screen(tester);
    await tester.pumpWidget(
      viewer(
        vm(
          edit: const ViewerEditVm(kind: .json, text: '{"a": 1}'),
        ),
        validate: (t) => t.trim().endsWith('}') ? null : 'Not a JSON map',
      ),
    );
    await tester.tap(edit);
    await tester.pump();
    // Text and JSON: a multi-line editor.
    expect(tester.widget<TextField>(editor).maxLines, isNull);

    await tester.enterText(editor, '{"a": 1');
    await tester.pump();
    expect(find.text('Not a JSON map'), findsOneWidget);
    await tester.tap(save, warnIfMissed: false);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(saved, isEmpty);
    expect(editor, findsOneWidget);

    await tester.enterText(editor, '{"a": 2}');
    await tester.pump();
    expect(find.text('Not a JSON map'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(saved, ['{"a": 2}']);
    expect(editor, findsNothing);
  });

  testWidgets('Esc leaves the editor first, and closes the window next', (
    tester,
  ) async {
    screen(tester);
    await tester.pumpWidget(
      viewer(
        vm(
          edit: const ViewerEditVm(kind: .text, text: 'AHU-'),
        ),
      ),
    );
    await tester.tap(edit);
    await tester.pump();
    await tester.pump();
    await tester.enterText(editor, 'changed');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editor, findsNothing);
    expect(closed, 0);
    expect(saved, isEmpty, reason: 'Cancel saves nothing');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, 1);

    // Cancel does the same as the first Esc; the editor starts over from
    // the value.
    await tester.tap(edit);
    await tester.pump();
    expect(tester.widget<TextField>(editor).controller!.text, 'AHU-');
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(editor, findsNothing);
  });

  testWidgets('a bool is a toggle, a choice a dropdown', (tester) async {
    screen(tester);
    await tester.pumpWidget(
      viewer(
        vm(
          edit: const ViewerEditVm(kind: .toggle, text: 'false'),
        ),
      ),
    );
    await tester.tap(edit);
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(saved, ['true']);

    await tester.pumpWidget(
      viewer(
        vm(
          edit: const ViewerEditVm(
            kind: .choice,
            text: 'avg',
            choices: ['avg', 'min', 'max'],
          ),
        ),
      ),
    );
    await tester.tap(edit);
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('max').last);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();
    expect(saved.last, 'max');
  });

  testWidgets('a value that cannot be typed has no Edit and says why', (
    tester,
  ) async {
    screen(tester);
    await tester.pumpWidget(
      viewer(vm(locked: 'Read only: a wire feeds this field.')),
    );
    expect(edit, findsNothing);
    expect(find.text('Read only: a wire feeds this field.'), findsOneWidget);

    // A point of the Explorer: read only, and nothing said.
    await tester.pumpWidget(viewer(vm()));
    expect(edit, findsNothing);
  });

  testWidgets('a field that gets a wire while it is edited closes the '
      'editor', (tester) async {
    screen(tester);
    await tester.pumpWidget(
      viewer(
        vm(
          edit: const ViewerEditVm(kind: .number, text: '30'),
        ),
      ),
    );
    await tester.tap(edit);
    await tester.pump();
    expect(editor, findsOneWidget);
    await tester.pumpWidget(viewer(vm(locked: 'Read only: bound.')));
    expect(editor, findsNothing);
    expect(find.text('Read only: bound.'), findsOneWidget);
  });
}
