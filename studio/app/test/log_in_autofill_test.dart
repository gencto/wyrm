import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/inputs/boxed_form_field.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/log_in_app.dart';

/// What a field of the log-in page shows, what the store holds and the
/// error under it are the same value, however the text came: typed, or
/// filled by the system's password AutoFill without a key pressed
/// (owner, 2026-11-19: the password shown, "Required field" under it).
///
/// The `Form` validates every field in its own build, before the fields
/// under it take their new view-models: a validator that read the
/// view-model judged the value before the change and kept that error.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  setUpAll(loadFonts);
  setUp(() => S.load(const Locale('en')));

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is BoxedFormField && w.label == label,
  );

  Finder input(String label) =>
      find.descendant(of: field(label), matching: find.byType(EditableText));

  String shown(WidgetTester t, String label) =>
      t.widget<EditableText>(input(label)).controller.text;

  Finder required(String label) => find.descendant(
    of: field(label),
    matching: find.text(S.current.requiredField),
  );

  /// The system fills [label] as AutoFill does: through the platform's
  /// text input, not a key, and not into the focused field.
  void autofill(WidgetTester t, String label, String text) => t
      .state<EditableTextState>(input(label))
      .autofill(TextEditingValue(text: text));

  /// A remembered gateway and user: only the password is left.
  LogInApp remembered() =>
      LogInApp()..put((a) => a.copyWith.login(gateway: gw, user: user));

  testWidgets('AutoFill of the password: shown, held, no error', (t) async {
    final app = remembered();
    await app.pumpLogIn(t);

    autofill(t, 'Password', password);
    await app.settle(t);

    expect(shown(t, 'Password'), password);
    expect(app.store.state.login.password, password);
    expect(find.text(S.current.requiredField), findsNothing);
    await app.leave(t);
  }, variant: mac);

  testWidgets('AutoFill of the user and the password at once', (t) async {
    final app = LogInApp()..put((a) => a.copyWith.login(gateway: gw));
    await app.pumpLogIn(t);

    autofill(t, 'User', user);
    autofill(t, 'Password', password);
    await app.settle(t);

    expect(shown(t, 'User'), user);
    expect(app.store.state.login.user, user);
    expect(shown(t, 'Password'), password);
    expect(app.store.state.login.password, password);
    expect(find.text(S.current.requiredField), findsNothing);
    await app.leave(t);
  }, variant: mac);

  testWidgets('a typed password: no error under it', (t) async {
    final app = remembered();
    await app.pumpLogIn(t);

    await t.enterText(input('Password'), password);
    await app.settle(t);

    expect(app.store.state.login.password, password);
    expect(find.text(S.current.requiredField), findsNothing);
    await app.leave(t);
  }, variant: mac);

  testWidgets('a field emptied by the user says so, at once', (t) async {
    final app = remembered();
    await app.pumpLogIn(t);

    await t.enterText(input('Password'), password);
    await t.enterText(input('Password'), '');
    await app.settle(t);

    expect(app.store.state.login.password, isNull);
    expect(required('Password'), findsOneWidget);
    expect(required('User'), findsNothing);
    await app.leave(t);
  }, variant: mac);

  testWidgets('the store empties the focused password: the field too', (
    t,
  ) async {
    final app = remembered();
    await app.pumpLogIn(t);
    await t.enterText(input('Password'), password);
    await app.settle(t);
    expect(
      t.state<EditableTextState>(input('Password')).widget.focusNode.hasFocus,
      isTrue,
    );

    app.put((a) => a.copyWith.login(password: null));
    await app.settle(t);

    expect(shown(t, 'Password'), isEmpty);
    await app.leave(t);
  }, variant: mac);

  testWidgets('the main gateway emptied: the standby stays the standby', (
    t,
  ) async {
    final app = LogInApp()
      ..put(
        (a) => a.copyWith.login(gateway: '$gw, $standbyGw', user: user),
      );
    await app.pumpLogIn(t);
    await t.tap(find.text(S.current.standbyIs('edge.local:8446')));
    await app.settle(t);
    expect(shown(t, 'Standby gateway'), standbyGw);

    await t.enterText(input('Gateway'), '');
    await app.settle(t);

    expect(shown(t, 'Gateway'), isEmpty);
    expect(shown(t, 'Standby gateway'), standbyGw);
    expect(required('Gateway'), findsOneWidget);
    await app.leave(t);
  }, variant: mac);

  testWidgets('Log in after AutoFill sends the password shown', (t) async {
    final app = LogInApp(
      login: FakeLogin(
        error: WyrmException.of(Status.permissionDenied, 'bad credentials'),
      ),
    )..put((a) => a.copyWith.login(gateway: gw, user: user));
    await app.pumpLogIn(t);

    autofill(t, 'Password', password);
    await app.settle(t);
    await t.tap(find.widgetWithText(InkWell, 'Log in').last);
    await app.settle(t);

    expect(app.login.password, shown(t, 'Password'));
    expect(app.login.password, password);
    await app.leave(t);
  }, variant: mac);
}
