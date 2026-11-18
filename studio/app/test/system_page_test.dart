import 'package:app/mappers/shell_mappers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/system_app.dart';
import 'system_page_words.dart';

/// System as the store makes it (studio-rules, step 1): every word of each
/// tab in its main states, and what each control does — read from the
/// state, the fake broker's calls, the clipboard and the toasts, not from
/// which actions ran, so it holds before and after the rewrite.
void main() {
  setUp(() => S.load(const Locale('en')));

  Future<SystemApp> shown(
    WidgetTester t, {
    SysFixture fixture = const SysFixture(),
    SysTab tab = SysTab.overview,
    bool config = true,
    Locale locale = const Locale('en'),
    bool toasts = true,
  }) async {
    await S.load(locale);
    final app = SystemApp(fixture: fixture, config: config);
    await app.pump(t, tab: tab, locale: locale, toasts: toasts);
    return app;
  }

  Future<void> expectWords(
    WidgetTester t,
    List<String> expected, {
    SysFixture fixture = const SysFixture(),
    SysTab tab = SysTab.overview,
    bool config = true,
    Locale locale = const Locale('en'),
  }) async {
    final app = await shown(
      t,
      fixture: fixture,
      tab: tab,
      config: config,
      locale: locale,
      toasts: false,
    );
    expect(app.words(t), expected);
    await app.leave(t);
  }

  group('every word', () {
    testWidgets('Overview', (t) => expectWords(t, overviewWords));
    testWidgets(
      'Overview with the traffic ring',
      (t) => expectWords(
        t,
        samplesWords,
        fixture: const SysFixture(samples: true),
      ),
    );
    testWidgets(
      'Overview before any value, the broker unreachable',
      (t) => expectWords(
        t,
        emptyWords,
        fixture: const SysFixture(
          values: false,
          connected: false,
          backups: false,
          aclSeen: null,
        ),
      ),
    );
    testWidgets(
      'Availability, the standby following',
      (t) => expectWords(t, availabilityWords, tab: SysTab.availability),
    );
    testWidgets(
      'Availability, behind, the lease renewing late',
      (t) => expectWords(
        t,
        lagWords,
        tab: SysTab.availability,
        fixture: const SysFixture(standby: Standby.lag, lease: 2),
      ),
    );
    testWidgets(
      'Availability, a fork moved aside, no arbiter',
      (t) => expectWords(
        t,
        forksWords,
        tab: SysTab.availability,
        fixture: const SysFixture(standby: Standby.forks, lease: 0),
      ),
    );
    testWidgets(
      'Availability, behind and a fork',
      (t) => expectWords(
        t,
        bothWords,
        tab: SysTab.availability,
        fixture: const SysFixture(standby: Standby.both),
      ),
    );
    testWidgets(
      'Availability, no standby',
      (t) => expectWords(
        t,
        noneWords,
        tab: SysTab.availability,
        fixture: const SysFixture(standby: Standby.none),
      ),
    );
    testWidgets(
      'Log',
      (t) => expectWords(t, logWords, tab: SysTab.log),
    );
    testWidgets(
      'Log without config on sys',
      (t) => expectWords(
        t,
        noConfigLogWords,
        tab: SysTab.log,
        config: false,
      ),
    );
    testWidgets(
      'Maintenance',
      (t) => expectWords(t, maintenanceWords, tab: SysTab.maintenance),
    );
    testWidgets(
      'Maintenance with three stale links',
      (t) => expectWords(
        t,
        maintenanceManyWords,
        tab: SysTab.maintenance,
        fixture: const SysFixture(stale: 3),
      ),
    );
    testWidgets(
      'Maintenance without config, no stale link, pub not listed, no backups',
      (t) => expectWords(
        t,
        noConfigMaintenanceWords,
        tab: SysTab.maintenance,
        config: false,
        fixture: const SysFixture(
          stale: 0,
          profilesListed: false,
          backups: false,
        ),
      ),
    );
    testWidgets(
      'Overview in Ukrainian, with the traffic ring',
      (t) => expectWords(
        t,
        ukOverviewWords,
        fixture: const SysFixture(samples: true),
        locale: const Locale('uk'),
      ),
    );
    testWidgets(
      'Availability in Ukrainian, behind and a fork, the lease late',
      (t) => expectWords(
        t,
        ukAvailabilityBothWords,
        tab: SysTab.availability,
        fixture: const SysFixture(standby: Standby.both, lease: 2),
        locale: const Locale('uk'),
      ),
    );
    testWidgets(
      'Availability in Ukrainian, no standby',
      (t) => expectWords(
        t,
        ukAvailabilityNoneWords,
        tab: SysTab.availability,
        fixture: const SysFixture(standby: Standby.none),
        locale: const Locale('uk'),
      ),
    );
    testWidgets(
      'Log in Ukrainian',
      (t) => expectWords(
        t,
        ukLogWords,
        tab: SysTab.log,
        locale: const Locale('uk'),
      ),
    );
    testWidgets(
      'Maintenance in Ukrainian',
      (t) => expectWords(
        t,
        ukMaintenanceWords,
        tab: SysTab.maintenance,
        locale: const Locale('uk'),
      ),
    );
  });

  testWidgets('shown, it watches sys and reads what it shows; left, it stops', (
    t,
  ) async {
    final app = await shown(t);
    final s = app.store.state;
    expect(s.system.shown, isTrue);
    expect(
      s.live.watched.keys,
      containsAll([
        '$sys/*',
        '$sys/links/*/state',
        '$sys/history/database_size',
        '$sys/backups/*/*',
      ]),
    );
    expect(s.system.about['$sys/cpu'], 'CPU of the broker process.');
    expect(s.system.units['$sys/cpu'], 'pct');
    expect(
      [for (final p in s.system.profiles) '${p.name} ${p.points}'],
      ['acme:ahu 14', 'acme:vav 1'],
    );
    expect(s.backups.view, ['b1', 'b2', 'b3', 'b4', 'b5']);
    expect(app.calls('get_log'), isEmpty, reason: 'only the Log tab reads it');

    await app.leave(t);
    final after = app.store.state;
    expect(after.system.shown, isFalse);
    expect(after.live.watched['$sys/*'] ?? 0, 0);
    expect(after.live.watched['$sys/backups/*/*'] ?? 0, 0);
    expect(after.system.aclSeen, 18402, reason: 'the ACL counter when left');
  });

  testWidgets("the Log tab reads the log with the toolbar's arguments", (
    t,
  ) async {
    final app = await shown(t);
    await t.tap(find.text('Log'));
    await app.settle(t);
    expect(find.text('Get log'), findsOneWidget);
    expect(app.logReads, [
      Value.from({'lines': 200}),
    ]);

    // auto off, so only the toolbar reads below: no read for it
    await t.tap(find.text('every 5 s'));
    await app.settle(t);
    expect(app.logReads, hasLength(1));
    expect(app.store.state.system.auto, isFalse);

    // the level
    await t.tap(find.text('info').first);
    await app.settle(t);
    await t.tap(find.text('warn').last);
    await app.settle(t);
    expect(app.logReads.last, Value.from({'lines': 200, 'level': 'warn'}));

    // the source: an embedded or wasm link
    await t.tap(find.text('broker (all)'));
    await app.settle(t);
    await t.tap(find.text(S.current.sysLinkSource('bacnet')).last);
    await app.settle(t);
    expect(
      app.logReads.last,
      Value.from({'lines': 200, 'level': 'warn', 'link': 'bacnet'}),
    );

    // the filter, on Enter
    await t.enterText(find.byType(TextField).first, 'fuel');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await app.settle(t);
    expect(
      app.logReads.last,
      Value.from({
        'lines': 200,
        'level': 'warn',
        'filter': 'fuel',
        'link': 'bacnet',
      }),
    );

    // the lines, on Enter (the toolbar may report them twice: on Enter
    // and when the field loses the focus)
    final before = app.logReads.length;
    await t.enterText(find.byType(TextField).at(2), '50');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await app.settle(t);
    expect(app.logReads.length, greaterThan(before));
    final reads = app.logReads.length - 1;
    expect(
      app.logReads.last,
      Value.from({
        'lines': 50,
        'level': 'warn',
        'filter': 'fuel',
        'link': 'bacnet',
      }),
    );

    // the time around which lines are shown: no read, the lines held
    await t.enterText(find.byKey(const ValueKey('log-around')), '02:01:44');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await app.settle(t);
    expect(app.logReads, hasLength(reads + 1));
    expect(find.text('02:01:44'), findsWidgets);
    expect(find.text('02:01:40'), findsOneWidget);

    // Get log
    await t.tap(find.text('Get log'));
    await app.settle(t);
    expect(app.logReads, hasLength(reads + 2));

    // none every 5 s while auto is off
    await t.pump(const Duration(seconds: 6));
    await app.settle(t);
    expect(app.logReads, hasLength(reads + 2));

    // auto on again: a read at once, then every 5 s
    await t.tap(find.text('every 5 s'));
    await app.settle(t);
    expect(app.logReads, hasLength(reads + 3));
    await t.pump(const Duration(seconds: 5));
    await app.settle(t);
    expect(app.logReads, hasLength(reads + 4));
    await app.leave(t);
  });

  testWidgets('Copy writes the lines shown, and says so', (t) async {
    final app = await shown(t, tab: SysTab.log);
    await t.tap(find.text('Copy'));
    await app.settle(t);
    expect(
      app.clipboard,
      '2026-11-12T02:01:44Z INFO wyrm_link_sdk link modbus connected\n'
      '2026-11-12T02:01:40Z WARN wyrm_admin::supervisor '
      'link bacnet stopped: fuel limit reached',
    );
    expect(app.notices(t), [S.current.sysLogCopied(2)]);
    await app.leave(t);
  });

  testWidgets('Save as .log that fails says why', (t) async {
    final app = await shown(t, tab: SysTab.log);
    await t.tap(find.text('Save as .log'));
    await app.settle(t);
    expect(app.notices(t).first, S.current.sysLogNotSaved);
    expect(app.notices(t), hasLength(2), reason: 'the title and the error');
    await app.leave(t);
  });

  testWidgets('the broker level is staged, and taken back', (t) async {
    final app = await shown(t, tab: SysTab.log);
    await t.tap(find.text('debug'));
    await app.settle(t);
    final staged = app.store.state.changes.table.values.single;
    expect(staged.key, '$sys/log_level');
    expect(staged.field, 'value');
    expect(staged.from.vm.text, 'info');
    expect(staged.to.vm.text, 'debug');
    expect(staged.level, Perm.config);
    expect(staged.value, 3);

    // a second pick replaces it
    await t.tap(find.text('trace'));
    await app.settle(t);
    expect(app.store.state.changes.table.values.single.to.vm.text, 'trace');
    expect(app.store.state.changes.table.values.single.value, 4);

    // the broker's own level takes it back
    await t.tap(find.text('info').last);
    await app.settle(t);
    expect(app.store.state.changes.table, isEmpty);
    await app.leave(t);
  });

  testWidgets('a level given as a name is read as that level', (t) async {
    final app = await shown(
      t,
      tab: SysTab.log,
      fixture: const SysFixture(level: 'warn'),
    );
    await t.tap(find.text('debug'));
    await app.settle(t);
    expect(app.store.state.changes.table.values.single.from.vm.text, 'warn');
    await app.leave(t);
  });

  testWidgets('Measure switches the traffic card', (t) async {
    final app = await shown(t);
    await t.tap(find.text('Frames'));
    await app.settle(t);
    expect(find.text('in · frames_in_per_second'), findsOneWidget);
    expect(find.text('310'), findsOneWidget);
    await t.tap(find.text('Bytes'));
    await app.settle(t);
    expect(find.text('in · data_in_per_second'), findsOneWidget);
    expect(find.text('81.2'), findsOneWidget);
    expect(find.text('kB/s'), findsNWidgets(2));
    await app.leave(t);
  });

  testWidgets('Clear asks with the ids, runs clear_conns, says what went', (
    t,
  ) async {
    final app = await shown(t, tab: SysTab.maintenance);
    await t.tap(find.text('Clear 1 disconnected link…'));
    await app.settle(t);
    expect(find.text(S.current.sysClearAsk), findsOneWidget);
    expect(find.text(S.current.sysClearAskBody('field-x')), findsOneWidget);
    await t.tap(find.text(S.current.sysClearConfirm));
    await app.settle(t);
    expect(app.calls('clear_conns'), hasLength(1));
    expect(app.notices(t), [S.current.sysCleared('field-x')]);
    await app.leave(t);
  });

  testWidgets('Clear left at the question runs nothing', (t) async {
    final app = await shown(t, tab: SysTab.maintenance);
    await t.tap(find.text('Clear 1 disconnected link…'));
    await app.settle(t);
    await t.tap(find.text(S.current.cancel));
    await app.settle(t);
    expect(app.calls('clear_conns'), isEmpty);
    expect(app.notices(t), isEmpty);
    await app.leave(t);
  });

  testWidgets('Remove asks, removes the profile, says so', (t) async {
    final app = await shown(t, tab: SysTab.maintenance);
    await t.tap(find.text('Remove').first);
    await app.settle(t);
    expect(
      find.text(S.current.sysRemoveProfileAsk('acme:ahu')),
      findsOneWidget,
    );
    await t.tap(find.text(S.current.sysRemove).last);
    await app.settle(t);
    final call = app.calls('remove').single;
    expect(call.key, '$sys/profiles');
    expect(call.args, Value.from({'name': 'acme:ahu'}));
    expect(app.notices(t), [S.current.sysProfileRemoved('acme:ahu')]);
    await app.leave(t);
  });

  testWidgets('a command card copies its command', (t) async {
    final app = await shown(t, tab: SysTab.maintenance);
    await t.tap(
      find.bySemanticsLabel(
        S.current.sysCopyCommand(S.current.sysCmdVerify),
      ),
    );
    await app.settle(t);
    expect(app.clipboard, 'wyrmd -c /etc/wyrm/wyrmd.json5 verify');
    expect(app.notices(t), [S.current.sysCommandCopied]);
    await app.leave(t);
  });

  testWidgets('with no standby the guide link copies its address', (t) async {
    final app = await shown(
      t,
      tab: SysTab.availability,
      fixture: const SysFixture(standby: Standby.none),
    );
    await t.tap(find.text(S.current.sysGuideLink));
    await app.settle(t);
    const url =
        'https://github.com/gencto/wyrm/blob/main/docs/operations.md'
        '#warm-standby-adr-0036-option-3-stage-a';
    expect(app.clipboard, url);
    expect(app.notices(t), [S.current.sysGuideCopied(url)]);
    await app.leave(t);
  });

  testWidgets("Back up… and a row's Open open the backup dialog", (t) async {
    final app = await shown(t, tab: SysTab.maintenance);
    await t.tap(find.text('Back up…'));
    await app.settle(t);
    expect(find.byType(Dialog), findsOneWidget);
    expect(app.store.state.backups.stage, isNotNull);
    await app.leave(t);
  });
}
