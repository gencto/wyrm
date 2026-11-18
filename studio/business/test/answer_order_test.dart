import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/site/actions/switch_site_action.dart';
import 'package:business/redux/site/actions/view_site_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// A read started without anyone waiting for it (a site switch reads the
/// links again) never lands an older answer over a newer one, nor one
/// site's table on another.
void main() {
  late FakeWyrmApi api;
  late Store<AppState> s;

  setUp(() async {
    final login = FakeLogin(
      session: FakeSession(
        who: identityOf(
          subject: 'user:olena',
          site: 'central',
          roles: const ['admin'],
          max: 'config',
          grants: const [('wy/**', 'config')],
        ),
      ),
    );
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('olena'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
    NodeMeta link(String driver) => NodeMeta(
      attr: {'driver': VStr(driver), 'mode': const VStr('embedded')},
    );
    api
      ..children_['wy/central/sys/links'] = [Child('old', NodeMeta())]
      ..metas['wy/central/sys/links/old'] = link('modbus')
      ..metas['wy/central/sys/links'] = NodeMeta()
      ..children_['wy/edge/sys/links'] = [Child('new', NodeMeta())]
      ..metas['wy/edge/sys/links/new'] = link('bacnet')
      ..metas['wy/edge/sys/links'] = NodeMeta();
    for (final site in ['central', 'edge']) {
      final k = 'wy/$site/sys/version';
      api.initial[k] = [ValSample(k, const Sample(VStr('0.1.0'), t: 1))];
    }
  });

  test(
    'the links of a site left, answered after the switch, are dropped',
    () async {
      // central's list is held; the switch to edge reads edge's
      final gate = api.hold('wy/central/sys/links');
      final left = s.dispatchAndWait(RetrieveLinksAction());
      await s.dispatchAndWait(SwitchSiteAction('edge'));
      gate.complete();
      await left;
      expect(s.state.site.current, 'edge');
      expect(s.state.links.table.keys, ['new']);
    },
  );

  group('the newest read of the links wins, and waits for none', () {
    const base = 'wy/central/sys/links';
    final before = [Child('old', NodeMeta())];
    final after = [Child('old', NodeMeta()), Child('added', NodeMeta())];
    final late = WyrmException.of(Status.timeout, 'late');

    bool waiting() => s.state.wait.isWaitingForType<RetrieveLinksAction>();

    /// Starts a read whose list is [answer]; its gate, and how it ends.
    (Completer<void>, Future<ActionStatus>) read(ListAnswer answer) {
      (api.childrenInTurn[base] ??= []).add(answer);
      final gate = api.hold(base);
      return (gate, s.dispatchAndWait(RetrieveLinksAction()));
    }

    setUp(() {
      api.metas['$base/added'] = NodeMeta(
        attr: {'driver': const VStr('s7'), 'mode': const VStr('embedded')},
      );
    });

    test('an older answer that comes last does not replace the newer '
        'table, and the newer read is kept while the older one is still '
        'out', () async {
      final (olderGate, older) = read(ListAnswer(before));
      final (newerGate, newer) = read(ListAnswer(after));
      newerGate.complete();
      await newer;
      // (b) the newer read did not wait: the older one is still held
      expect(olderGate.isCompleted, isFalse);
      expect(s.state.links.table.keys, ['old', 'added']);
      // a read is still out, and the screen says so
      expect(waiting(), isTrue);
      olderGate.complete();
      await older;
      // (a) the older answer came last and was dropped
      expect(s.state.links.table.keys, ['old', 'added']);
      expect(s.state.links.view, ['old', 'added']);
      // (c) nothing is left waiting
      expect(waiting(), isFalse);
      expect(s.state.problems.items, isEmpty);
    });

    test('an older answer that comes first is kept until the newer one '
        'comes: who awaits a read finds a table at least as new as its '
        'own', () async {
      final (olderGate, older) = read(ListAnswer(before));
      final (newerGate, newer) = read(ListAnswer(after));
      olderGate.complete();
      await older;
      expect(s.state.links.table.keys, ['old']);
      expect(waiting(), isTrue);
      newerGate.complete();
      await newer;
      expect(s.state.links.table.keys, ['old', 'added']);
      expect(waiting(), isFalse);
    });

    test('a read that failed while a newer one is under way ends as the '
        'newer one does: its waiter finds the fresh table, nothing is '
        'said', () async {
      final (olderGate, older) = read(ListAnswer.refused(late));
      final (newerGate, newer) = read(ListAnswer(after));
      olderGate.complete();
      var olderDone = false;
      final ended = older.whenComplete(() => olderDone = true);
      await pumpEventQueue();
      // it has nothing fresh: it waits for the newer read's outcome
      expect(olderDone, isFalse);
      newerGate.complete();
      final status = await ended;
      await newer;
      expect(status.isCompletedOk, isTrue);
      expect(s.state.links.table.keys, ['old', 'added']);
      expect(s.state.problems.items, isEmpty);
      expect(waiting(), isFalse);
    });

    test('both fail: the waiter of the older read fails too, and the '
        'failure is one line in Problems', () async {
      final (olderGate, older) = read(ListAnswer.refused(late));
      final (newerGate, newer) = read(
        ListAnswer.refused(WyrmException.of(Status.timeout, 'no answer')),
      );
      olderGate.complete();
      await pumpEventQueue();
      newerGate.complete();
      final statuses = await Future.wait([older, newer]);
      expect(statuses.every((st) => st.isCompletedFailed), isTrue);
      await pumpEventQueue();
      expect(s.state.problems.items, hasLength(1));
      // the newer read says it; the older one opens no second dialog
      expect(
        (statuses.first.wrappedError! as UserException).ifOpenDialog,
        isFalse,
      );
      expect(waiting(), isFalse);
    });

    test('an older good answer stands when the newer read failed, and '
        'the failure of the newest read is said', () async {
      final (olderGate, older) = read(ListAnswer(after));
      final (newerGate, newer) = read(ListAnswer.refused(late));
      newerGate.complete();
      final failed = await newer;
      expect(failed.wrappedError, isNotNull);
      olderGate.complete();
      await older;
      // nothing newer was kept: the older answer is the freshest there is
      expect(s.state.links.table.keys, ['old', 'added']);
      expect(waiting(), isFalse);
    });

    test('X, Y, then X again: the new read of X fails and the older good '
        'read of X arrives later; it is kept, the read of Y in between '
        'does not drop it', () async {
      final (firstGate, first) = read(ListAnswer(after));
      // away to edge (its links are read and kept) and back
      await s.dispatchAndWait(SwitchSiteAction('edge'));
      expect(s.state.links.table.keys, ['new']);
      s.dispatchSync(ViewSiteAction('central'));
      final (againGate, again) = read(ListAnswer.refused(late));
      firstGate.complete();
      await pumpEventQueue();
      againGate.complete();
      await Future.wait([first, again]);
      // central's table is the older good read of central, not edge's
      expect(s.state.links.table.keys, ['old', 'added']);
      expect(waiting(), isFalse);
    });

    test('a failure of the read of a site that was left is not said; the '
        'site on screen has its own links', () async {
      final (gate, left) = read(ListAnswer.refused(late));
      await s.dispatchAndWait(SwitchSiteAction('edge'));
      gate.complete();
      await left;
      expect(s.state.problems.items, isEmpty);
      expect(s.state.links.table.keys, ['new']);
      expect(waiting(), isFalse);
    });

    test('a failure of the newest read is said as before', () async {
      final (gate, only) = read(
        ListAnswer.refused(WyrmException.of(Status.timeout, 'no answer')),
      );
      gate.complete();
      final status = await only;
      expect(status.wrappedError, isNotNull);
      await pumpEventQueue();
      expect(s.state.problems.items, hasLength(1));
      expect(waiting(), isFalse);
    });
  });
}
