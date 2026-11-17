import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/site/actions/switch_site_action.dart';
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
      // central's list answers slowly; the switch to edge reads edge's
      api.delays['wy/central/sys/links'] = const Duration(milliseconds: 60);
      int reads() => api.calls
          .where((c) => c.op == 'children' && c.key == 'wy/central/sys/links')
          .length;
      final sent = reads();
      final left = s.dispatchAndWait(RetrieveLinksAction());
      // central's read is under way when the switch comes
      for (var i = 0; i < 200 && reads() == sent; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(reads(), sent + 1);
      final switched = s.dispatchAndWait(SwitchSiteAction('edge'));
      await left;
      await switched;
      expect(s.state.site.current, 'edge');
      expect(s.state.links.table.keys, ['new']);
    },
  );

  group('the newest read of the links wins, and waits for none', () {
    const base = 'wy/central/sys/links';
    const slow = Duration(milliseconds: 80);
    const fast = Duration(milliseconds: 5);
    final before = [Child('old', NodeMeta())];
    final after = [Child('old', NodeMeta()), Child('added', NodeMeta())];

    bool waiting() => s.state.wait.isWaitingForType<RetrieveLinksAction>();

    setUp(() {
      api.metas['$base/added'] = NodeMeta(
        attr: {'driver': const VStr('s7'), 'mode': const VStr('embedded')},
      );
    });

    test('an older answer that comes last does not replace the newer '
        'table, and the newer read is kept while the older one is still '
        'out', () async {
      api.childrenInTurn[base] = [(slow, before, null), (fast, after, null)];
      var olderDone = false;
      final older = s
          .dispatchAndWait(RetrieveLinksAction())
          .whenComplete(() => olderDone = true);
      final newer = s.dispatchAndWait(RetrieveLinksAction());
      await newer;
      // (b) the newer read did not wait: the older one is still out
      expect(olderDone, isFalse);
      expect(s.state.links.table.keys, ['old', 'added']);
      // a read is still out, and the screen says so
      expect(waiting(), isTrue);
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
      api.childrenInTurn[base] = [(fast, before, null), (slow, after, null)];
      final older = s.dispatchAndWait(RetrieveLinksAction());
      final newer = s.dispatchAndWait(RetrieveLinksAction());
      await older;
      expect(s.state.links.table.keys, ['old']);
      expect(waiting(), isTrue);
      await newer;
      expect(s.state.links.table.keys, ['old', 'added']);
      expect(waiting(), isFalse);
    });

    test('a failure of a read a newer one replaced is not said', () async {
      api.childrenInTurn[base] = [
        (slow, null, WyrmException.of(Status.timeout, 'late')),
        (fast, after, null),
      ];
      final older = s.dispatchAndWait(RetrieveLinksAction());
      final newer = s.dispatchAndWait(RetrieveLinksAction());
      await newer;
      final status = await older;
      expect(status.originalError, isNotNull);
      expect(status.wrappedError, isNull);
      expect(s.state.problems.items, isEmpty);
      expect(s.state.links.table.keys, ['old', 'added']);
      expect(waiting(), isFalse);
    });

    test('a failure of the read of a site that was left is not said; the '
        'site on screen has its own links', () async {
      api.childrenInTurn[base] = [
        (slow, null, WyrmException.of(Status.timeout, 'late')),
      ];
      final left = s.dispatchAndWait(RetrieveLinksAction());
      final switched = s.dispatchAndWait(SwitchSiteAction('edge'));
      await switched;
      await left;
      expect(s.state.problems.items, isEmpty);
      expect(s.state.links.table.keys, ['new']);
      expect(waiting(), isFalse);
    });

    test('a failure of the newest read is said as before', () async {
      api.childrenInTurn[base] = [
        (fast, null, WyrmException.of(Status.timeout, 'no answer')),
      ];
      final status = await s.dispatchAndWait(RetrieveLinksAction());
      expect(status.wrappedError, isNotNull);
      expect(s.state.problems.items, hasLength(1));
      expect(waiting(), isFalse);
    });
  });
}
