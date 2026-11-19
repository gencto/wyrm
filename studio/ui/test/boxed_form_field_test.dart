import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/inputs/boxed_form_field.dart';
import 'package:ui/models/value_changed.dart';

import 'frames/harness.dart';

/// A value set from outside (a gateway chip picked, a field filled by the
/// store) reaches a field inside a `Form` while the tree is being built. The
/// field takes it without marking the `Form` dirty in that build: before, it
/// did (`FormFieldState.didChange`), the frame threw "setState() or
/// markNeedsBuild() called during build" and the log-in page kept the pixels
/// of earlier frames (the gateway field drawn three times).
void main() {
  setUpAll(() => S.load(const Locale('en')));

  testWidgets('a value from outside is taken without a build error', (
    tester,
  ) async {
    final value = ValueNotifier<String?>('http://127.0.0.1:8445');
    final form = GlobalKey<FormState>();
    String? validated;
    await tester.pumpWidget(
      frame(
        Form(
          key: form,
          child: ValueListenableBuilder<String?>(
            valueListenable: value,
            builder: (context, v, _) => BoxedFormField(
              vm: FieldVm<String?>(
                value: v,
                onChanged: (_) {},
                validator: (s) {
                  validated = s;
                  return null;
                },
              ),
              label: 'Gateway',
            ),
          ),
        ),
      ),
    );

    value.value = 'http://127.0.0.1:8446';
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('http://127.0.0.1:8446'), findsOneWidget);
    // the form validates the value the field shows
    form.currentState!.validate();
    expect(validated, 'http://127.0.0.1:8446');
  });

  testWidgets('an error is judged again when a value comes from outside', (
    tester,
  ) async {
    final value = ValueNotifier<String?>(null);
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      frame(
        Form(
          key: form,
          child: ValueListenableBuilder<String?>(
            valueListenable: value,
            builder: (context, v, _) => BoxedFormField(
              vm: FieldVm<String?>(
                value: v,
                onChanged: (_) {},
                validator: (s) => s == null ? 'Required' : null,
              ),
              label: 'User',
            ),
          ),
        ),
      ),
    );
    form.currentState!.validate();
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);

    value.value = 'olena';
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('olena'), findsOneWidget);
    expect(find.text('Required'), findsNothing);
  });

  testWidgets('what is judged is the text shown, before the view-model', (
    tester,
  ) async {
    // The view-model never follows the text here: the `Form` of the page
    // validates in its own build, before the field takes its new one.
    final form = GlobalKey<FormState>();
    String? validated;
    await tester.pumpWidget(
      frame(
        Form(
          key: form,
          child: BoxedFormField(
            vm: FieldVm<String?>(
              value: null,
              onChanged: (_) {},
              validator: (s) {
                validated = s;
                return null;
              },
            ),
            label: 'Password',
          ),
        ),
      ),
    );

    tester
        .state<EditableTextState>(find.byType(EditableText))
        .autofill(const TextEditingValue(text: 'wyrm-demo-1'));
    await tester.pump();
    form.currentState!.validate();

    expect(validated, 'wyrm-demo-1');
  });
}
