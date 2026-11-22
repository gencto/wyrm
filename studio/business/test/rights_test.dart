import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/decode/access.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/node_detail.dart';
import 'package:business/wyrm/rights.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/change_op.dart';
import 'package:models/change_side.dart';
import 'package:models/grant.dart';
import 'package:models/grant_level.dart';
import 'package:models/role_grant.dart';
import 'package:models/staged_change.dart';
import 'package:wyrm_client/wyrm_client.dart' hide Grant;

class _Reader with Selectors {
  _Reader(this.state);

  @override
  final AppState state;
}

/// A session logged into `central` with [grants] under the cap [max].
_Reader _session(List<Grant> grants, {Perm? max = Perm.config}) => _Reader(
  AppState.initial().copyWith.site(
    name: 'central',
    max: max,
    grants: grants.lock,
  ),
);

void main() {
  group('SelectSite rights', () {
    final r = _session(const [
      Grant(key: 'wy/central/downstream/**', level: Perm.write),
      Grant(key: 'wy/central/sys/links', level: Perm.read),
      Grant(key: 'wy/edge/**', level: Perm.config),
    ]);

    test('the first matching grant decides, as the gateway signs it', () {
      expect(r.site.levelOn('wy/central/downstream/modbus/a'), Perm.write);
      expect(r.site.levelOn('wy/central/sys/links'), Perm.read);
      expect(r.site.levelOn('wy/edge/sys'), Perm.config);
      expect(r.site.levelOn('wy/central/sys'), Perm.none);
    });

    test('viewer then operator: read on downstream, as the gateway signs', () {
      // the gateway's default roles in role order (`Grants::perm`, the
      // first grant that intersects the key): viewer's read comes first
      final s = _session(const [
        Grant(key: 'wy/central/downstream/**', level: Perm.read),
        Grant(key: 'wy/central/downstream/**', level: Perm.write),
      ], max: Perm.write);
      expect(s.site.levelOn('wy/central/downstream/m/sp'), Perm.read);
      expect(s.site.can(Perm.write, 'wy/central/downstream/m/sp'), isFalse);
      expect(
        s.site.lacks(Perm.write, 'wy/central/downstream/m/sp'),
        const Lack(Perm.write, 'downstream/m/sp'),
      );
    });

    test('a none before a wider grant denies what it covers', () {
      final s = _session(const [
        Grant(key: 'wy/central/sys/**', level: Perm.none),
        Grant(key: 'wy/central/**', level: Perm.config),
      ]);
      expect(s.site.levelOn('wy/central/sys/links'), Perm.none);
      expect(s.site.can(Perm.list, 'wy/central/sys/links'), isFalse);
      expect(s.site.mayRead('wy/central/sys/links'), isFalse);
      // what the none does not cover keeps the wider grant
      expect(s.site.levelOn('wy/central/downstream/x'), Perm.config);
    });

    test('a missing level is a typed lack, never a hidden control', () {
      expect(
        r.site.lacks(Perm.config, 'wy/central/sys/links'),
        const Lack(Perm.config, 'sys/links'),
      );
      expect(r.site.lacks(Perm.write, 'wy/central/downstream/x'), isNull);
    });

    test('the viewed site defaults to the one logged into', () {
      expect(r.site.root, 'wy/central');
      final there = _Reader(r.state.copyWith.site(current: 'plant'));
      expect(there.site.root, 'wy/plant');
      expect(there.site.home, 'wy/central');
    });
  });

  // What a right is when it is missing or not known. On main 7ac1beee,
  // where a level was a name ranked by its place in a list (-1 for one not
  // in it), a user with no grant could read (`mayRead`), a missing `max`
  // lifted the cap, a role grant whose level is none was kept, and a
  // staged change was `write` unless told (rights_actions_test.dart has
  // what that sent). The other cases here held on main too; they keep it.
  group('the check fails closed', () {
    test(
      'each level boundary: a grant gives its level and every lower one',
      () {
        for (final have in Perm.values) {
          final s = _session([Grant(key: 'wy/central/**', level: have)]);
          for (final need in Perm.values) {
            expect(
              s.site.can(need, 'wy/central/sys'),
              need.code <= have.code,
              reason: '$have grants $need',
            );
            expect(
              s.site.lacks(need, 'wy/central/sys'),
              need.code <= have.code ? isNull : Lack(need, 'sys'),
            );
          }
        }
      },
    );

    test('a user with no grant has no right at all', () {
      final s = _session(const []);
      for (final need in Perm.values.where((p) => p != Perm.none)) {
        expect(s.site.can(need, 'wy/central/sys'), isFalse);
      }
      expect(s.site.mayRead('wy/central/downstream/x'), isFalse);
    });

    test('a missing max (no /api/me read) closes the cap', () {
      final s = _session(const [
        Grant(key: 'wy/central/**', level: Perm.config),
      ], max: null);
      expect(s.site.levelOn('wy/central/sys'), Perm.none);
      expect(s.site.levelOn('wy/central/sys'), Perm.none);
      expect(s.site.can(Perm.read, 'wy/central/sys'), isFalse);
      expect(s.site.mayRead('wy/central/sys'), isFalse);
    });

    test('max caps every grant, highest and first match alike', () {
      for (final max in Perm.values) {
        final s = _session(const [
          Grant(key: 'wy/central/**', level: Perm.config),
        ], max: max);
        expect(s.site.levelOn('wy/central/sys'), max);
        expect(s.site.levelOn('wy/central/sys'), max);
        expect(s.site.can(Perm.config, 'wy/central/sys'), max == Perm.config);
      }
    });

    test('an unknown max from the wire refuses /api/me: no session, no cap '
        'lifted', () {
      expect(
        () => GatewayIdentity.fromValue(
          Value.from({
            'sub': 'user:eve',
            'site': 'central',
            'roles': ['operator'],
            'max': 'root',
            'exp': 0,
            'grants': [
              {'k': 'wy/**', 'p': 'config'},
            ],
          }),
        ),
        throwsA(isA<DecodeError>()),
      );
    });

    test('an unknown level of a grant from the wire refuses /api/me', () {
      expect(
        () => GatewayIdentity.fromValue(
          Value.from({
            'sub': 'user:eve',
            'site': 'central',
            'roles': ['operator'],
            'max': 'config',
            'exp': 0,
            'grants': [
              {'k': 'wy/**', 'p': 'superuser'},
            ],
          }),
        ),
        throwsA(isA<DecodeError>()),
      );
    });

    test('an unknown level of a role grant from the wire is refused', () {
      final row = roleGrantOf(
        Value.from({
          'subject': 'operator',
          'path': 'wy/**',
          'level': 'superuser',
          'source': 'gateway',
        }),
      );
      expect(row, isA<Invalid<RoleGrant>>());
      expect((row as Invalid<RoleGrant>).field, 'level');
    });

    test('an ACL rule is its words, never a level', () {
      final row = roleGrantOf(
        Value.from({
          'subject': 'link:modbus',
          'path': 'wy/central/downstream/modbus/**',
          'level': 'put, query (ingress/egress)',
          'source': 'acl',
        }),
      );
      expect(
        (row as Valid<RoleGrant>).value.level,
        const GrantLevel.rule('put, query (ingress/egress)'),
      );
    });

    test("an action's level is its own, else the node's invokable; with "
        'neither it is not callable', () {
      NodeMeta meta({Perm? invokable}) => NodeMeta(
        invokable: invokable,
        actions: {
          'own': ActionMeta(level: Perm.config),
          'plain': ActionMeta(),
          'off': ActionMeta(level: Perm.none),
        },
      );
      final read = nodeDetailOf('k', meta(invokable: Perm.read));
      expect(read.invokable, Perm.read);
      expect(
        {for (final a in read.actions) a.name: a.level},
        {
          'own': Perm.config,
          'plain': Perm.read,
        },
      );
      final none = nodeDetailOf('k', meta());
      expect([for (final a in none.actions) a.name], ['own']);
      final closed = nodeDetailOf('k', meta(invokable: Perm.none));
      expect([for (final a in closed.actions) a.name], ['own']);
    });

    test('a staged change is checked at the level it states', () {
      // `level` is required: a change with none does not compile
      const c = StagedChange(
        id: '1',
        op: ChangeOp.edit,
        key: 'wy/central/sys/x',
        field: 'value',
        to: ChangeSide.text('1'),
        level: Perm.config,
      );
      final writer = _session(const [
        Grant(key: 'wy/central/**', level: Perm.write),
      ]);
      final admin = _session(const [
        Grant(key: 'wy/central/**', level: Perm.config),
      ]);
      expect(writer.site.can(c.level, c.key), isFalse);
      expect(
        writer.site.lacks(c.level, c.key),
        const Lack(Perm.config, 'sys/x'),
      );
      expect(admin.site.can(c.level, c.key), isTrue);
    });
  });
}
