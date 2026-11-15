import 'package:business/wyrm/decode/broker_text.dart';
import 'package:business/wyrm/decode/catalog_rows.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/install_field.dart';
import 'package:business/wyrm/decode/link_params.dart';
import 'package:business/wyrm/decode/requested_rights.dart';
import 'package:business/wyrm/decode/sys_verdict.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:models/catalog_form.dart';
import 'package:models/catalog_row.dart';
import 'package:models/install_field.dart';
import 'package:models/requested_right.dart';
import 'package:models/sys_verdict.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// The decoders behind Add a link (studio-rules §8): the answer of an
/// install, the rows of `attr.catalog`, a text value read once, and the
/// field a refusal names. Each shape decodes once, typed; a value of
/// another shape names its field.
void main() {
  List<String> warnings() {
    final seen = <String>[];
    final sub = decodeLog.onRecord.listen((r) => seen.add(r.message));
    addTearDown(sub.cancel);
    Logger.root.level = Level.ALL;
    return seen;
  }

  group('sysVerdictOf', () {
    test('the last row counts: success and message, kept verbatim', () {
      expect(
        sysVerdictOf([
          Value.from({'success': false, 'message': 'first'}),
          Value.from({'success': true, 'message': 'link modbus installed'}),
        ], where: 't'),
        const SysVerdict(success: true, message: 'link modbus installed'),
      );
    });

    test('no row, or a null one, is no success', () {
      expect(
        sysVerdictOf(const [], where: 't'),
        const SysVerdict(success: false),
      );
      expect(
        sysVerdictOf(const [VNull()], where: 't'),
        const SysVerdict(success: false),
      );
    });

    test('a map without success: the action ran', () {
      expect(
        sysVerdictOf([
          Value.from({'message': 'done'}),
        ], where: 't'),
        const SysVerdict(success: true, message: 'done'),
      );
    });

    test('an answer that is no map: the action ran, said nothing more', () {
      expect(
        sysVerdictOf(const [VStr('ok')], where: 't'),
        const SysVerdict(success: true),
      );
    });

    test('a failure is a failure whatever its message; each bad field is '
        'logged', () {
      final seen = warnings();
      expect(
        sysVerdictOf([
          Value.from({'success': false, 'message': 3}),
        ], where: 'install_zip on plant'),
        const SysVerdict(success: false),
      );
      expect(
        sysVerdictOf([
          Value.from({'success': 'yes', 'message': 'odd'}),
        ], where: 'install_zip on plant'),
        const SysVerdict(success: false, message: 'odd'),
        reason: 'an answer that does not say it succeeded did not',
      );
      expect(seen, [
        'install_zip on plant: sys verdict.message: not a text',
        'install_zip on plant: sys verdict.success: not a bool',
      ]);
    });
  });

  group('catalogRowsOf', () {
    test('no attr.catalog: no rows', () {
      expect(catalogRowsOf(null), isNull);
      expect(catalogRowsOf({'other': Value.from(1)}), isNull);
      expect(catalogRowsOf({'catalog': Value.from(<Object?>[])}), isEmpty);
    });

    test('a row by its id, trimmed, its form typed', () {
      final rows = catalogRowsOf({
        'catalog': Value.from([
          {
            'id': 'package:alarm-process',
            'title': ' Alarms ',
            'summary': 'Classes',
            'category': 'Apps',
            'version': '0.3.0',
            'form': 'process',
            'official': true,
          },
          {'id': 'driver:mock'},
        ]),
      })!;
      expect(
        rows['package:alarm-process'],
        const CatalogRow(
          id: 'package:alarm-process',
          title: 'Alarms',
          summary: 'Classes',
          category: 'Apps',
          version: '0.3.0',
          form: CatalogForm.process,
          official: true,
        ),
      );
      expect(rows['driver:mock'], const CatalogRow(id: 'driver:mock'));
    });

    test('a row that is not one is left out and logged with its field', () {
      final warnings = <String>[];
      final sub = decodeLog.onRecord.listen((r) => warnings.add(r.message));
      addTearDown(sub.cancel);
      Logger.root.level = Level.ALL;
      final rows = catalogRowsOf({
        'catalog': Value.from([
          'not a row',
          {'title': 'no id'},
          {'id': 'driver:x', 'official': 'yes'},
          {'id': 'driver:y', 'version': 2},
          {'id': 'driver:ok'},
        ]),
      })!;
      expect(rows.keys, ['driver:ok']);
      expect(warnings, [
        'attr.catalog: catalog row.: not a map',
        'attr.catalog: catalog row.id: missing',
        'attr.catalog: catalog row.official: not a bool',
        'attr.catalog: catalog row.version: not a text',
      ]);
    });
  });

  group('brokerTextOf and hostOf', () {
    test('a text, none, or another type named', () {
      expect(
        brokerTextOf(const VStr('0.1.0'), 'sys', 'version'),
        const Valid<String?>('0.1.0'),
      );
      expect(brokerTextOf(null, 'sys', 'version'), const Valid<String?>(null));
      expect(
        brokerTextOf(const VInt(1), 'sys', 'version'),
        const Invalid<String?>('sys', 'version', 'not a text'),
      );
    });

    test('a host only when the distribution names one', () {
      expect(hostOf('linux-aarch64'), 'linux-aarch64');
      expect(hostOf('rust (prod)'), isNull);
      expect(hostOf(null), isNull);
    });
  });

  group('installFieldOf', () {
    test('the parameter a refusal names, as the field that holds it', () {
      expect(installFieldOf('id', git: false), InstallField.name);
      expect(installFieldOf('name', git: true), InstallField.name);
      expect(installFieldOf('url', git: false), InstallField.url);
      expect(installFieldOf('url', git: true), InstallField.git);
      expect(installFieldOf('ref', git: true), InstallField.ref);
      expect(installFieldOf('driver', git: false), isNull);
    });
  });

  group('sysRunOf', () {
    test('no answer is a run that said nothing; a map is its verdict', () {
      expect(
        sysRunOf(const VNull(), where: 't'),
        const SysVerdict(success: true),
      );
      expect(
        sysRunOf(
          Value.from({'success': false, 'message': 'asks for net'}),
          where: 't',
        ),
        const SysVerdict(success: false, message: 'asks for net'),
      );
    });

    test('a failed run with a message of another type stays a failure', () {
      expect(
        sysRunOf(Value.from({'success': false, 'message': 7}), where: 't'),
        const SysVerdict(success: false),
      );
    });
  });

  group('brokerBoolOf', () {
    test('a bool, none, or another type named', () {
      expect(
        brokerBoolOf(const VBool(true), 'p', 'f'),
        const Valid<bool?>(true),
      );
      expect(brokerBoolOf(null, 'p', 'f'), const Valid<bool?>(null));
      expect(
        brokerBoolOf(const VStr('yes'), 'p', 'f'),
        const Invalid<bool?>('p', 'f', 'not a bool'),
      );
    });
  });

  group('linkParamsOf', () {
    test('one JSON object, JSON that is no object, or no JSON', () {
      expect(
        switch (linkParamsOf('{"poll_s": 2}')) {
          ParamsObject(:final params) => params,
          _ => null,
        },
        {'poll_s': 2},
      );
      expect(linkParamsOf('[1]'), isA<ParamsNotObject>());
      expect(
        switch (linkParamsOf('{"poll_s": ')) {
          ParamsNotJson(:final detail) => detail,
          _ => null,
        },
        isNotEmpty,
      );
    });
  });

  group('requestedRightsOf', () {
    test('the capabilities and the grants, typed', () {
      expect(
        requestedRightsOf(
          {
            'net': ['10.0.5.0/24:502'],
            'store_mb': 1,
            'memory_mb': 64,
            'call_ms': 200,
          },
          [
            {'path': 'wy/{site}/downstream/modbus', 'level': 'read'},
          ],
        ).orWarn('test'),
        [
          const RequestedRight.network(['10.0.5.0/24:502']),
          const RequestedRight.store(1),
          const RequestedRight.memory(64),
          const RequestedRight.call(200),
          const RequestedRight.grant(
            level: Perm.read,
            path: 'wy/{site}/downstream/modbus',
          ),
        ],
      );
      expect(requestedRightsOf(null, null).orWarn('test'), isEmpty);
    });

    test('a field of another type names it', () {
      expect(
        requestedRightsOf({'store_mb': '1'}, null),
        const Invalid<List<RequestedRight>>(
          'package manifest',
          'capabilities.store_mb',
          'not a whole number',
        ),
      );
      expect(
        requestedRightsOf(null, [
          {'path': 'x', 'level': 'admin'},
        ]),
        const Invalid<List<RequestedRight>>(
          'package manifest',
          'requester.level',
          'not a level',
        ),
      );
    });
  });
}
