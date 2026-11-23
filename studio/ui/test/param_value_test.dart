import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/inputs/switch_row.dart';

import 'frames/harness.dart';

/// Each editor of a [ParamForm] reads its own case of [ParamValue] and
/// reports one; a value of another case shows an empty field.
void main() {
  Future<void> show(WidgetTester t, ParamFieldVm vm) => t.pumpWidget(
    frame(
      Padding(
        padding: const EdgeInsets.all(20),
        child: ParamField(vm: vm),
      ),
    ),
  );

  ParamFieldVm field(
    ParamKind kind,
    ParamValue value, {
    List<String> choices = const [],
    ValueChanged<ParamValue>? onChanged,
  }) => ParamFieldVm(
    id: 'p',
    label: 'P',
    kind: kind,
    value: value,
    hint: 'none yet',
    choices: choices,
    onChanged: onChanged ?? (_) {},
  );

  testWidgets('a file field shows a file name and nothing else', (t) async {
    await show(t, field(.file, const FileValue('points.csv')));
    expect(find.text('points.csv'), findsOneWidget);

    for (final v in [
      const NoValue(),
      const TextValue('{a: 1}'),
      const NumberValue(1),
      const FlagValue(on: true),
    ]) {
      await show(t, field(.file, v));
      expect(find.text('none yet'), findsOneWidget, reason: '$v');
    }
  });

  testWidgets('a choice shows one of its choices and nothing else', (t) async {
    await show(t, field(.choice, const TextValue('b'), choices: ['a', 'b']));
    expect(find.text('b'), findsOneWidget);

    for (final v in [
      const TextValue('c'),
      const NumberValue(0),
      const NoValue(),
    ]) {
      await show(t, field(.choice, v, choices: ['a', 'b']));
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        isNull,
        reason: '$v',
      );
    }
  });

  testWidgets('a typed field reports a typed value', (t) async {
    final got = <ParamValue>[];
    await show(t, field(.number, const NumberValue(5), onChanged: got.add));
    expect(find.text('5'), findsOneWidget);
    await t.enterText(find.byType(TextFormField), '12.5');
    await t.enterText(find.byType(TextFormField), '-');
    await t.enterText(find.byType(TextFormField), '');
    expect(got, const [NumberValue(12.5), TextValue('-'), NoValue()]);

    got.clear();
    await show(t, field(.text, const TextValue('plc1'), onChanged: got.add));
    await t.enterText(find.byType(TextFormField), 'plc2');
    expect(got, const [TextValue('plc2')]);

    got.clear();
    await show(
      t,
      field(.toggle, const FlagValue(on: false), onChanged: got.add),
    );
    await t.tap(find.byType(AppSwitch));
    expect(got, const [FlagValue(on: true)]);
  });

  testWidgets('a form submits plain arguments by field id', (t) async {
    Map<String, Object?>? sent;
    await t.pumpWidget(
      frame(
        ActionForm(
          fields: [
            field(.text, const TextValue('plc1')),
            ParamFieldVm(
              id: 'port',
              label: 'Port',
              kind: .number,
              value: const NumberValue(502),
              onChanged: (_) {},
            ),
            ParamFieldVm(
              id: 'on',
              label: 'On',
              kind: .toggle,
              value: const FlagValue(on: true),
              onChanged: (_) {},
            ),
            ParamFieldVm(
              id: 'file',
              label: 'File',
              kind: .file,
              onChanged: (_) {},
            ),
          ],
          submit: 'Send',
          onSubmit: (v) {
            sent = v;
            return null;
          },
        ),
      ),
    );
    await t.tap(find.text('Send'));
    await t.pump();
    expect(sent, {'p': 'plc1', 'port': 502, 'on': true, 'file': null});
  });
}
