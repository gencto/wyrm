import 'package:business/wyrm/decode/access.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/audit_line.dart';
import 'package:models/grant_source.dart';
import 'package:models/role_grant.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// The decoders of Access (studio-rules §8): `sys ▸ get_permissions` and
/// `sys/audit ▸ tail` as wyrm-admin writes them (`perm_row`, the audit
/// record map), and what a shape it does not write turns into.
void main() {
  test('a grant of each source, and one this client does not know', () {
    Value row(String source) => Value.from({
      'subject': 'operator',
      'path': 'wy/{site}/downstream/**',
      'level': 'write',
      'source': source,
    });
    expect(
      roleGrantOf(row('gateway')),
      const Valid(
        RoleGrant(
          subject: 'operator',
          path: 'wy/{site}/downstream/**',
          level: 'write',
          source: GrantSource.gateway,
        ),
      ),
    );
    expect(
      [
        for (final s in ['acl', 'link', 'peer']) roleGrantOf(row(s)),
      ],
      [
        isA<Valid<RoleGrant>>().having(
          (v) => v.value.source,
          'source',
          GrantSource.acl,
        ),
        isA<Valid<RoleGrant>>().having(
          (v) => v.value.source,
          'source',
          GrantSource.link,
        ),
        isA<Valid<RoleGrant>>().having((v) => v.value.source, 'source', null),
      ],
    );
  });

  test('a grant that is not a map, or whose field is not a text', () {
    expect(
      roleGrantOf(const VStr('x')),
      const Invalid<RoleGrant>('grant', '', 'not a map'),
    );
    expect(
      roleGrantOf(Value.from({'subject': 3, 'path': 'p', 'level': 'read'})),
      const Invalid<RoleGrant>('grant', 'subject', 'not a text'),
    );
  });

  test('an audit record as wyrm-admin writes it, numbers as digits', () {
    expect(
      auditLineOf(
        Value.from({
          't': 1700000000000000,
          'sub': 'user:olena',
          'op': 'set',
          'key': 'downstream/plc1/sp',
          'status': 0,
        }),
      ),
      const Valid(
        AuditLine(
          time: '1700000000000000',
          what: 'set downstream/plc1/sp',
          result: '0',
        ),
      ),
    );
    expect(
      auditLineOf(
        Value.from({
          'time': 't1',
          'who': 'user:admin',
          'event': 'invoke',
          'target': 'x',
          'action': 'restart',
          'result': 'ok',
        }),
      ),
      const Valid(
        AuditLine(
          time: 't1',
          who: 'user:admin',
          what: 'invoke x restart',
          result: 'ok',
        ),
      ),
    );
    expect(auditLineOf(const VInt(1)), isA<Invalid<AuditLine>>());
  });

  test('an answer of arrays or of single records', () {
    expect(
      recordsOf([
        const VArray([VInt(1), VInt(2)]),
        const VInt(3),
      ]).toList(),
      const [VInt(1), VInt(2), VInt(3)],
    );
  });

  test('the link a key is under', () {
    expect(linkOf('wy/plant/downstream/modbus/dev/t1'), 'modbus');
    expect(linkOf('wy/plant/sys/links/modbus'), isNull);
    expect(linkOf('wy/plant/downstream'), isNull);
  });
}
