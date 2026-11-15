import 'package:app/connectors/links_page_connector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/inputs/switch_row.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'links_page_words.dart';
import 'support/link_install_app.dart' show packageZip;
import 'support/links_app.dart';
import 'support/words_dump.dart';

/// Links as the store makes it (studio-rules, step 1): every word of each
/// tab, inspector and update sheet in its main states, in English and
/// Ukrainian, and what each control does — read from the fake broker's
/// calls, the staged changes, the dialogs and the screen, not from which
/// actions ran, so it holds before and after the rewrite.
void main() {
  setUp(() => S.load(const Locale('en')));

  Future<LinksApp> shown(
    WidgetTester t, {
    LinksFixture fixture = const LinksFixture(),
    bool config = true,
    Locale locale = const Locale('en'),
  }) async {
    await S.load(locale);
    final app = LinksApp(fixture: fixture, config: config);
    await app.pump(t, locale: locale);
    return app;
  }

  /// Shows Links, taps [taps] in turn and compares every word with the
  /// words of [name].
  Future<void> expectWords(
    WidgetTester t,
    String name,
    List<String> Function() taps, {
    LinksFixture fixture = const LinksFixture(),
    bool config = true,
    Locale locale = const Locale('en'),
  }) async {
    final app = await shown(
      t,
      fixture: fixture,
      config: config,
      locale: locale,
    );
    for (final label in taps()) {
      await app.tap(t, label);
    }
    expectWordsOf(name, app.words(t), linksWords[name] ?? const []);
    await app.leave(t);
  }

  group('every word', () {
    testWidgets('On this broker', (t) => expectWords(t, 'local', () => []));
    testWidgets(
      'a built-in link selected',
      (t) => expectWords(t, 'local modbus', () => ['modbus']),
    );
    testWidgets(
      'an official package with an update, selected',
      (t) => expectWords(t, 'local bacnet', () => ['bacnet']),
    );
    testWidgets(
      'a custom WASM package selected',
      (t) => expectWords(t, 'local telegram', () => ['telegram']),
    );
    testWidgets(
      'a built-in link without config, no backups',
      (t) => expectWords(
        t,
        'local modbus no config',
        () => ['modbus'],
        config: false,
        fixture: const LinksFixture(backups: false),
      ),
    );
    testWidgets(
      'Updates',
      (t) => expectWords(t, 'updates', () => [S.current.updTab]),
    );
    testWidgets(
      'the update review of an official package',
      (t) => expectWords(
        t,
        'review bacnet',
        () => [S.current.updTab, 'bacnet'],
      ),
    );
    testWidgets(
      'the update review of a custom package',
      (t) => expectWords(
        t,
        'review telegram',
        () => [S.current.updTab, 'telegram'],
      ),
    );
    testWidgets(
      'Update all official',
      (t) => expectWords(
        t,
        'update all',
        () => [S.current.updTab, S.current.updAllOfficial],
      ),
    );
    testWidgets(
      'an update the broker checks',
      (t) => expectWords(
        t,
        'progress',
        () => [S.current.updTab, 'bacnet'],
        fixture: const LinksFixture(update: UpdateShown.checking),
      ),
    );
    testWidgets(
      'an update that ran',
      (t) => expectWords(
        t,
        'result ok',
        () => ['bacnet', S.current.actVersions],
        fixture: const LinksFixture(update: UpdateShown.ok),
      ),
    );
    testWidgets(
      'an update rolled back',
      (t) => expectWords(
        t,
        'result rolled back',
        () => ['bacnet', S.current.actVersions],
        fixture: const LinksFixture(update: UpdateShown.rolledBack),
      ),
    );
    testWidgets(
      'an update that failed',
      (t) => expectWords(
        t,
        'result failed',
        () => ['bacnet', S.current.actVersions],
        fixture: const LinksFixture(update: UpdateShown.failed),
      ),
    );
    testWidgets(
      'an update that lost nodes',
      (t) => expectWords(
        t,
        'result gone',
        () => ['bacnet', S.current.actVersions],
        fixture: const LinksFixture(update: UpdateShown.gone),
      ),
    );
    testWidgets(
      'the versions of a package never updated',
      (t) => expectWords(
        t,
        'points',
        () => ['bacnet', S.current.actVersions],
      ),
    );
    testWidgets(
      'On other devices',
      (t) => expectWords(t, 'remote', () => [S.current.onOtherDevices]),
    );
    testWidgets(
      'an external link selected',
      (t) => expectWords(
        t,
        'remote field-cam',
        () => [S.current.onOtherDevices, 'field-cam'],
      ),
    );
    testWidgets(
      'Quarantine',
      (t) => expectWords(t, 'quarantine', () => [S.current.quarantine]),
    );
    testWidgets(
      'a link waiting in quarantine, selected',
      (t) => expectWords(
        t,
        'quarantine field-gw',
        () => [S.current.quarantine, 'link:field-gw'],
      ),
    );
    testWidgets(
      'a broker waiting in quarantine, selected',
      (t) => expectWords(
        t,
        'quarantine line2',
        () => [S.current.quarantine, 'broker:line2'],
      ),
    );
    testWidgets(
      'uk: an official package selected',
      (t) => expectWords(
        t,
        'uk local bacnet',
        () => ['bacnet'],
        locale: const Locale('uk'),
      ),
    );
    testWidgets(
      'uk: the update review',
      (t) => expectWords(
        t,
        'uk review bacnet',
        () => [S.current.updTab, 'bacnet'],
        locale: const Locale('uk'),
      ),
    );
    testWidgets(
      'uk: an update that ran',
      (t) => expectWords(
        t,
        'uk result ok',
        () => ['bacnet', S.current.actVersions],
        locale: const Locale('uk'),
        fixture: const LinksFixture(update: UpdateShown.ok),
      ),
    );
    testWidgets(
      'uk: an external link selected',
      (t) => expectWords(
        t,
        'uk remote field-cam',
        () => [S.current.onOtherDevices, 'field-cam'],
        locale: const Locale('uk'),
      ),
    );
    testWidgets(
      'uk: a link waiting in quarantine',
      (t) => expectWords(
        t,
        'uk quarantine field-gw',
        () => [S.current.quarantine, 'link:field-gw'],
        locale: const Locale('uk'),
      ),
    );
  });

  group('what each control does', () {
    testWidgets('shown: reads the links, packages, quarantine, backups', (
      t,
    ) async {
      final app = await shown(t);
      final listed = {for (final c in app.calls('children')) c.key};
      expect(
        listed,
        containsAll(['$sys/links', '$sys/packages', '$sys/quarantine']),
      );
      expect(
        {for (final c in app.calls('meta')) c.key},
        contains('$sys/backups'),
      );
      final watched = app.store.state.live.watched.keys.toSet();
      expect(
        watched,
        containsAll([
          '$sys/links/*/state',
          '$sys/enable_quarantine',
          '$sys/allow_all_links',
          '$sys/packages/*/*',
          '$sys/links/*/restore_points',
        ]),
      );
      await app.leave(t);
      expect(
        app.store.state.live.watched.keys.where(
          (k) => k.startsWith('$sys/links') || k.startsWith('$sys/packages'),
        ),
        isEmpty,
      );
    });

    testWidgets('Stop and Start run on the selected link', (t) async {
      final app = await shown(t);
      await app.tap(t, 'modbus');
      await app.tap(t, S.current.actStop);
      expect(
        [for (final c in app.calls('stop')) c.key],
        [
          '$sys/links/modbus',
        ],
      );
      await app.tap(t, 'bacnet');
      await app.tap(t, S.current.actStart);
      expect(
        [for (final c in app.calls('start')) c.key],
        [
          '$sys/links/bacnet',
        ],
      );
      await app.leave(t);
    });

    testWidgets('Remove link asks, then removes; Cancel keeps it', (
      t,
    ) async {
      final app = await shown(t);
      await app.tap(t, 'bacnet');
      await app.tap(t, S.current.actRemoveLink);
      expectWordsOf(
        'remove dialog',
        app.dialogWords(t),
        linksWords['remove dialog'] ?? const [],
      );
      await app.answer(t, S.current.cancel);
      expect(app.calls('remove'), isEmpty);
      await app.tap(t, S.current.actRemoveLink);
      await app.answer(t, S.current.remove);
      expect(
        [for (final c in app.calls('remove')) c.key],
        [
          '$sys/links/bacnet',
        ],
      );
      await app.leave(t);
    });

    testWidgets('Remove of a built-in link says the tree goes', (t) async {
      final app = await shown(t);
      await app.tap(t, 'modbus');
      await app.tap(t, S.current.actRemoveLink);
      expectWordsOf(
        'remove builtin dialog',
        app.dialogWords(t),
        linksWords['remove builtin dialog'] ?? const [],
      );
      await app.answer(t, S.current.cancel);
      await app.leave(t);
    });

    testWidgets('Deauthorize asks, then deauthorizes the external link', (
      t,
    ) async {
      final app = await shown(t);
      await app.tap(t, S.current.onOtherDevices);
      await app.tap(t, 'field-cam');
      await app.tap(t, S.current.actDeauthorize);
      expectWordsOf(
        'deauthorize dialog',
        app.dialogWords(t),
        linksWords['deauthorize dialog'] ?? const [],
      );
      await app.answer(t, S.current.actDeauthorize);
      expect(
        [for (final c in app.calls('deauthorize')) c.args],
        [
          Value.from({'link': 'field-cam'}),
        ],
      );
      await app.leave(t);
    });

    testWidgets('Reject asks, then rejects', (
      t,
    ) async {
      final app = await shown(t);
      await app.tap(t, S.current.quarantine);
      await app.tap(t, 'link:field-gw');
      await app.tap(t, S.current.reject);
      expectWordsOf(
        'reject dialog',
        app.dialogWords(t),
        linksWords['reject dialog'] ?? const [],
      );
      await app.answer(t, S.current.reject);
      expect(
        [for (final c in app.calls('reject')) c.key],
        [
          '$sys/quarantine/field-gw',
        ],
      );
      await app.leave(t);
    });

    testWidgets('Approve sends the form', (t) async {
      final app = await shown(t);
      await app.tap(t, S.current.quarantine);
      await app.tap(t, 'link:field-gw');
      await t.enterText(
        find
            .descendant(
              of: find.byType(LinksPageConnector),
              matching: find.byType(EditableText),
            )
            .last,
        'gw-1',
      );
      await app.settle(t);
      await app.tap(t, S.current.approve);
      expect(
        [for (final c in app.calls('approve')) c.args],
        [
          Value.from({'name': 'gw-1'}),
        ],
      );
      await app.leave(t);
    });

    testWidgets('the admission switches stage a change of sys', (t) async {
      final app = await shown(t);
      await app.tap(t, S.current.quarantine);
      await t.tap(find.byType(AppSwitch).first);
      await app.settle(t);
      await t.tap(find.byType(AppSwitch).last);
      await app.settle(t);
      expect(
        [
          for (final c in app.store.state.changes.table.values)
            (c.key, c.from, c.to, c.value),
        ],
        [
          ('$sys/enable_quarantine', 'on', 'off', false),
          ('$sys/allow_all_links', 'off', 'on', true),
        ],
      );
      await app.leave(t);
    });

    testWidgets('a row of Updates opens its sheet; Update sends it', (
      t,
    ) async {
      final app = await shown(t);
      await app.tap(t, S.current.updTab);
      await app.tap(t, 'bacnet');
      // the restore point is locked on; auto rollback turned off
      await app.tap(t, S.current.updOptAuto);
      await app.tap(t, S.current.updDo(1));
      expect(
        [for (final c in app.calls('update')) (c.key, c.args)],
        [
          (
            '$sys/packages/bacnet',
            Value.from({'restore_point': true, 'auto_rollback_s': 0}),
          ),
        ],
      );
      await app.leave(t);
    });

    testWidgets('Cancel closes the sheet', (t) async {
      final app = await shown(t);
      await app.tap(t, S.current.updTab);
      await app.tap(t, 'bacnet');
      expect(find.text(S.current.updDo(1)), findsOneWidget);
      await app.tap(t, S.current.cancel);
      expect(find.text(S.current.updDo(1)), findsNothing);
      await app.leave(t);
    });

    testWidgets('Update from a file of a custom package asks for a zip', (
      t,
    ) async {
      final app = await shown(t);
      await app.tap(t, 'telegram');
      await app.tap(t, S.current.actUpdateFromFile);
      expect(find.text(S.current.updChooseArchive), findsOneWidget);
      await app.leave(t);
    });

    testWidgets('Roll back asks, then rolls back', (t) async {
      final app = await shown(
        t,
        fixture: const LinksFixture(update: UpdateShown.failed),
      );
      await app.tap(t, 'bacnet');
      await app.tap(t, S.current.actVersions);
      await app.tap(t, S.current.updRollBackTo('0.2.0'));
      expectWordsOf(
        'rollback dialog',
        app.dialogWords(t),
        linksWords['rollback dialog'] ?? const [],
      );
      await app.answer(t, S.current.updRollBack);
      expect(
        [for (final c in app.calls('rollback')) c.key],
        [
          '$sys/packages/bacnet',
        ],
      );
      await app.leave(t);
    });

    testWidgets('Open link of a result shows the link on this broker', (
      t,
    ) async {
      final app = await shown(
        t,
        fixture: const LinksFixture(update: UpdateShown.ok),
      );
      await app.tap(t, 'bacnet');
      await app.tap(t, S.current.actVersions);
      await app.tap(t, S.current.updOpenLink('bacnet'));
      expectWordsOf(
        'after open link',
        app.words(t),
        linksWords['after open link'] ?? const [],
      );
      await app.leave(t);
    });

    testWidgets("a link's dialogs open from its inspector, each its own", (
      t,
    ) async {
      final app = await shown(t);
      await app.tap(t, 'modbus');
      for (final (label, title) in [
        (S.current.actViewLog, S.current.logOf('modbus')),
        (S.current.actEditParams, S.current.editParamsOf('modbus')),
        (S.current.actParamsHistory, S.current.historyOf('modbus')),
        (S.current.actSecrets, S.current.actSecrets),
        (S.current.actGrant, S.current.grantFor('modbus')),
      ]) {
        await app.tap(t, label);
        expect(
          find.descendant(of: find.byType(Dialog), matching: find.text(title)),
          findsWidgets,
          reason: label,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await app.settle(t);
        expect(find.byType(Dialog), findsNothing, reason: label);
      }
      // the backup dialog closes with its own buttons only
      await app.tap(t, S.current.actBackUp);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(S.current.bakTitleLink('modbus')),
        ),
        findsWidgets,
      );
      await app.leave(t);
    });

    testWidgets('Update from file: a zip goes to install_zip of its link', (
      t,
    ) async {
      final app = await shown(t);
      await app.tap(t, 'telegram');
      await app.tap(t, S.current.actUpdateFromFile);
      await app.tap(t, S.current.updChooseArchive);
      expect(app.picker.asked, [
        ['zip'],
      ]);
      final call = app.calls('install_zip').single;
      expect(call.key, '$sys/links');
      expect(call.args!['name'], const VStr('telegram'));
      expect(call.args!['zip'], VBytes(packageZip));
      expect(call.args!['restore_point'], const VBool(true));
      expect(call.args!['auto_rollback_s'], const VInt(120));
      await app.leave(t);
    });

    testWidgets('a progress with a kept version: its second button rolls '
        'back', (t) async {
      final app = await shown(
        t,
        fixture: const LinksFixture(update: UpdateShown.checkingKept),
      );
      await app.tap(t, S.current.updTab);
      await app.tap(t, 'bacnet');
      await app.tap(t, S.current.updStopAndRollBack);
      expectWordsOf(
        'stop and roll back dialog',
        app.dialogWords(t),
        linksWords['stop and roll back dialog'] ?? const [],
      );
      await app.answer(t, S.current.updRollBack);
      expect([for (final c in app.calls('rollback')) c.key], [
        '$sys/packages/bacnet',
      ]);
      await app.leave(t);
    });

    testWidgets('a progress without a kept version: its second button '
        'closes', (t) async {
      final app = await shown(
        t,
        fixture: const LinksFixture(update: UpdateShown.checking),
      );
      await app.tap(t, S.current.updTab);
      await app.tap(t, 'bacnet');
      await app.tap(t, S.current.updStopAndRollBack);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text(S.current.updUpdating('bacnet')), findsNothing);
      expect(app.calls('rollback'), isEmpty);
      await app.leave(t);
    });

    testWidgets('a rolled-back result: its first button opens the log', (
      t,
    ) async {
      final app = await shown(
        t,
        fixture: const LinksFixture(update: UpdateShown.rolledBack),
      );
      await app.tap(t, 'bacnet');
      await app.tap(t, S.current.actVersions);
      await app.tap(t, S.current.updOpenLog);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(S.current.logOf('bacnet')),
        ),
        findsWidgets,
      );
      await app.leave(t);
    });

    testWidgets('rights the new version asks for are accepted, then sent', (
      t,
    ) async {
      final app = await shown(t);
      app.api.invokes.remove('$sys/packages/bacnet ▸ update');
      app.api.answers['$sys/packages/bacnet ▸ update'] = (args) => [
        if (args?['accept'] case VBool(v: true))
          Value.from({'success': true, 'message': 'updated'})
        else
          Value.from({
            'success': false,
            'message': 'asks for network 10.0.4.0/24:47808',
          }),
      ];
      await app.tap(t, S.current.updTab);
      await app.tap(t, 'bacnet');
      await app.tap(t, S.current.updDo(1));
      expectWordsOf(
        'review asks',
        app.words(t),
        linksWords['review asks'] ?? const [],
      );
      await app.tap(t, S.current.updOptAccept);
      await app.tap(t, S.current.updDo(1));
      expect([for (final c in app.calls('update')) c.args], [
        Value.from({'restore_point': true, 'auto_rollback_s': 120}),
        Value.from({
          'accept': true,
          'restore_point': true,
          'auto_rollback_s': 120,
        }),
      ]);
      await app.leave(t);
    });
  });
}
