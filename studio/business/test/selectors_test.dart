import 'package:business/redux/app_state.dart';
import 'package:business/redux/flows/actions/retrieve_flows_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/links/actions/stop_link_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/flow_summary.dart';
import 'package:models/link_info.dart';
import 'package:models/node_info.dart';
import 'package:models/workspace.dart';

/// Holds an [AppState] and what is in flight, and nothing else — which is
/// the entire contract [Selectors] asks for.
///
/// That two-member requirement is the facade's best property, and this class
/// is the proof: a reducer, a connector's `_Factory` and a test all satisfy
/// it the same way, so the selectors are exercised through exactly the
/// surface production code uses. A reducer and a `_Factory` ask their store
/// (`Waiting(isWaiting)`); a test says it (`Waiting.fixed`).
class _Reader with Selectors, WaitingGiven {
  _Reader(this.state, [this.given = const Waiting.none()]);

  @override
  final AppState state;

  @override
  final Waiting given;
}

void main() {
  group('the facade reads through to its slice', () {
    test('every selector answers from AppState.initial()', () {
      final r = _Reader(AppState.initial());

      expect(r.connectivity.isConnected, isTrue);
      expect(r.login.gateway, isNull);
      expect(r.login.user, isNull);
      expect(r.login.password, isNull);
      expect(r.session.token, isNull);
      expect(r.theme.mode, ThemeMode.dark);
      expect(r.language.locale, 'en');
    });

    test('a written slice is what the selector returns', () {
      final r = _Reader(
        AppState.initial().copyWith
            .login(user: 'admin', password: 'secret')
            .copyWith
            .session(token: 'tok'),
      );

      expect(r.login.user, 'admin');
      expect(r.login.password, 'secret');
      expect(r.session.token, 'tok');
    });
  });

  group('SelectSession.isAvailable', () {
    test('is false without a token and true with one', () {
      expect(_Reader(AppState.initial()).session.isAvailable, isFalse);
      expect(
        _Reader(
          AppState.initial().copyWith.session(token: 'tok'),
        ).session.isAvailable,
        isTrue,
      );
    });

    test('an empty string is a token — the check is null, not blank', () {
      // Pinning the rule rather than endorsing it: the router gates the whole
      // app on this (`_AuthGuard`), so if it should reject `''` the change
      // belongs here, where one test names it.
      expect(
        _Reader(
          AppState.initial().copyWith.session(token: ''),
        ).session.isAvailable,
        isTrue,
      );
    });
  });

  // The barrier's own question (which actions cover the app) is asked in
  // `app`, of its list: `app/test/blocking_actions_test.dart`.
  group('a wait by its name', () {
    test('nothing is in flight', () {
      final r = _Reader(AppState.initial());

      expect(r.waiting.logIn, isFalse);
      expect(r.waiting.linkActing, isFalse);
    });

    test('the log-in is its own wait: the page shows its progress', () {
      // The log-in page shows the busy button and the three live steps
      // (docs/design/specs/login.md §3.6–3.7).
      final r = _Reader(AppState.initial(), Waiting.fixed({LogInAction}));

      expect(r.waiting.logIn, isTrue);
      expect(r.waiting.links, isFalse, reason: 'another action');
    });

    test('a name over several actions answers for each of them', () {
      expect(Waiting.fixed({StopLinkAction}).linkActing, isTrue);
      expect(Waiting.fixed({RetrieveLinksAction}).linkActing, isFalse);
    });
  });

  group('refreshing: stale while revalidate', () {
    const flow = FlowSummary(id: 'f1');
    test('a read with content held is a refresh', () {
      final held = AppState.initial().copyWith.flows(
        table: {'f1': flow}.lock,
      );
      final r = _Reader(held, Waiting.fixed({RetrieveFlowsAction}));

      expect(r.refreshing(Workspace.flows), isTrue);
      expect(r.refreshing(Workspace.links), isFalse, reason: 'not its read');
    });

    test('a read with nothing held is a first load, not a refresh', () {
      final r = _Reader(
        AppState.initial(),
        Waiting.fixed({RetrieveFlowsAction}),
      );

      expect(r.refreshing(Workspace.flows), isFalse);
    });

    test('content held and no read in flight is at rest', () {
      final r = _Reader(
        AppState.initial().copyWith.flows(table: {'f1': flow}.lock),
      );

      expect(r.refreshing(Workspace.flows), isFalse);
    });

    test('one read refreshes every workspace that shows it', () {
      final held = AppState.initial().copyWith
          .links(table: {'m': const LinkInfo(id: 'm')}.lock)
          .copyWith
          .nodes(
            table: {'k': const NodeInfo(key: 'k', name: 'k')}.lock,
          );
      final r = _Reader(held, Waiting.fixed({RetrieveLinksAction}));

      expect(r.refreshing(Workspace.links), isTrue);
      expect(r.refreshing(Workspace.explorer), isTrue, reason: 'link dots');
    });
  });
}
