import 'package:app/connectors/access_page_connector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/pages/access_page.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/access_fixture.dart';
import 'support/screen_app.dart';

/// Access as the store makes it (studio-rules, step 1): every word of each
/// tab in its main states, in English and Ukrainian, and what each control
/// does to the gateway's users, the grants and the devices — read from the
/// fake gateway and the state, not from which actions ran.
void main() {
  final words = ScreenWords('access');

  Future<ScreenApp> shown(
    WidgetTester t, {
    bool config = true,
    Locale locale = const Locale('en'),
  }) async {
    final app = ScreenApp(config: config);
    accessBroker(app);
    await app.logIn(t);
    await app.pump(t, const AccessPageConnector(), locale: locale);
    return app;
  }

  List<String> on(WidgetTester t, ScreenApp app) =>
      app.words(t, find.byType(AccessPage));

  Finder onPage(String text) =>
      find.descendant(of: find.byType(AccessPage), matching: find.text(text));

  Future<void> tap(WidgetTester t, ScreenApp app, Finder f) async {
    await t.ensureVisible(f.first);
    await t.tap(f.first);
    await app.settle(t);
  }

  final inDialog = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(Button),
  );

  Future<void> type(WidgetTester t, int field, String text) async {
    await t.enterText(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(TextField))
          .at(field),
      text,
    );
    await t.pump();
  }

  group('every word', () {
    testWidgets('Users, none picked', (t) async {
      final app = await shown(t);
      words.check('users', on(t, app));
      await app.leave(t);
    });
    testWidgets('Users, olena picked', (t) async {
      final app = await shown(t);
      await tap(t, app, onPage('olena'));
      words.check('olena', on(t, app));
      await app.leave(t);
    });
    testWidgets('Users, a disabled user picked', (t) async {
      final app = await shown(t);
      await tap(t, app, onPage('ivan'));
      words.check('ivan', on(t, app));
      await app.leave(t);
    });
    testWidgets('Grants', (t) async {
      final app = await shown(t);
      await tap(t, app, onPage('Grants'));
      words.check('grants', on(t, app));
      await app.leave(t);
    });
    testWidgets('Audit', (t) async {
      final app = await shown(t);
      await tap(t, app, onPage('Audit'));
      words.check('audit', on(t, app));
      await app.leave(t);
    });
    testWidgets('without config on sys', (t) async {
      final app = await shown(t, config: false);
      words.check('no config', on(t, app));
      await tap(t, app, onPage('Grants'));
      words.check('no config grants', on(t, app));
      await app.leave(t);
    });
    testWidgets('in Ukrainian', (t) async {
      final app = await shown(t, locale: const Locale('uk'));
      await tap(t, app, onPage('olena'));
      words.check('uk', on(t, app));
      await tap(t, app, onPage('Дозволи'));
      words.check('uk grants', on(t, app));
      await app.leave(t);
      await S.load(const Locale('en'));
    });
  });

  testWidgets('a tab, a user row, a grant row', (t) async {
    final app = await shown(t);
    expect(app.store.state.access.shown, isTrue);
    await tap(t, app, onPage('ivan'));
    expect(app.store.state.access.selected, 'ivan');
    expect(app.store.state.device.userDevices.keys, contains('ivan'));
    await tap(t, app, onPage('Grants'));
    expect(app.store.state.access.tab, 'grants');
    await tap(t, app, onPage('operator'));
    expect(app.store.state.access.selected, 'ivan');
    await tap(t, app, onPage('Audit'));
    expect(app.store.state.access.tab, 'audit');
    await tap(t, app, onPage('Users'));
    expect(app.store.state.access.tab, 'users');
    await app.leave(t);
    expect(app.store.state.access.shown, isFalse);
  });

  testWidgets('Access reads the users again every 10 s', (t) async {
    final app = await shown(t);
    expect(onPage('petro'), findsNothing);
    app.session.userTable['petro'] = const GatewayUser('petro', ['viewer']);
    await t.pump(const Duration(seconds: 10));
    await app.settle(t);
    expect(onPage('petro'), findsOneWidget);
    await app.leave(t);
  });

  testWidgets('Add user makes the user on the gateway', (t) async {
    final app = await shown(t);
    await tap(t, app, onPage('Add a user'));
    words.check('add user dialog', app.words(t, find.byType(Dialog)));
    await type(t, 0, 'petro');
    await type(t, 1, 'pw-1');
    await type(t, 2, 'viewer, operator');
    await tap(t, app, inDialog.last);
    expect(app.session.userTable['petro']?.roles, ['viewer', 'operator']);
    expect(find.byType(Dialog), findsNothing);
    expect(onPage('petro'), findsOneWidget);
    await app.leave(t);
  });

  testWidgets('Set roles, Set password, Disable, Remove', (t) async {
    final app = await shown(t);
    await tap(t, app, onPage('ivan'));

    await tap(t, app, onPage('Set roles'));
    words.check('roles dialog', app.words(t, find.byType(Dialog)));
    await type(t, 0, 'viewer');
    await tap(t, app, inDialog.last);
    expect(app.session.userTable['ivan']?.roles, ['viewer']);
    expect(find.byType(Dialog), findsNothing);

    await tap(t, app, onPage('Set password'));
    words.check('password dialog', app.words(t, find.byType(Dialog)));
    await type(t, 0, 'new-pw');
    await tap(t, app, inDialog.last);
    expect(find.byType(Dialog), findsNothing);

    // (the fake gateway's roles call keeps no `disabled`)
    expect(app.session.userTable['ivan']?.disabled, isFalse);
    await tap(t, app, onPage('Disable'));
    expect(app.session.userTable['ivan']?.disabled, isTrue);
    await tap(t, app, onPage('Enable'));
    expect(app.session.userTable['ivan']?.disabled, isFalse);

    await tap(t, app, onPage('Remove user'));
    words.check('remove user dialog', app.words(t, find.byType(Dialog)));
    expect(find.byType(Dialog), findsOneWidget);
    await tap(t, app, inDialog.last);
    expect(app.session.userTable.keys, ['olena']);
    expect(app.store.state.access.selected, isNull);
    await app.leave(t);
  });

  testWidgets('a device of the user is removed, then forgotten', (t) async {
    final app = await shown(t);
    await tap(t, app, onPage('ivan'));
    await tap(t, app, onPage('MacBook · Studio'));
    words.check('remove device dialog', app.words(t, find.byType(Dialog)));
    expect(find.byType(Dialog), findsOneWidget);
    await tap(t, app, inDialog.last);
    expect(app.session.gateway.records['d1']?.state, 'removed');

    await tap(t, app, find.textContaining('Pixel · Studio'));
    words.check('forget device dialog', app.words(t, find.byType(Dialog)));
    await tap(t, app, inDialog.last);
    expect(app.session.gateway.records.containsKey('d2'), isFalse);
    await app.leave(t);
  });

  testWidgets('Add grant updates the permissions of a role', (t) async {
    final app = await shown(t);
    await tap(t, app, onPage('Grants'));
    await tap(t, app, onPage('Add a grant'));
    words.check('add grant dialog', app.words(t, find.byType(Dialog)));
    await tap(t, app, find.byKey(const ValueKey('role/choice')));
    await tap(t, app, find.text('operator').last);
    await type(t, 0, 'wy/plant/storage/**');
    await tap(t, app, inDialog.last);
    final call = app.calls('update_permissions').single;
    expect(call.key, '$plant/sys');
    expect(
      call.args,
      Value.from({
        'role': 'operator',
        'path': 'wy/plant/storage/**',
        'level': 'read',
      }),
    );
    await app.leave(t);
  });
}
