import 'package:business/wyrm/decode/broker_text.dart';
import 'package:business/wyrm/decode/catalog_rows.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/install_field.dart';
import 'package:business/wyrm/decode/sys_verdict.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:models/install_field.dart';
import 'package:models/sys_verdict.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// The decoders behind Add a link (studio-rules §8): the answer of an
/// install, the rows of `attr.catalog`, a text value read once, and the
/// field a refusal names. Each shape decodes once, typed; a value of
/// another shape names its field.
void main() {
  group('sysVerdictOf', () {
    test('the last row counts: success and message, kept verbatim', () {
      expect(
        sysVerdictOf([
          Value.from({'success': false, 'message': 'first'}),
          Value.from({'success': true, 'message': 'link modbus installed'}),
        ]),
        const Valid(
          SysVerdict(success: true, message: 'link modbus installed'),
        ),
      );
    });

    test('no row, or a null one, is no success', () {
      expect(
        sysVerdictOf(const []),
        const Valid(SysVerdict(success: false)),
      );
      expect(
        sysVerdictOf(const [VNull()]),
        const Valid(SysVerdict(success: false)),
      );
    });

    test('a map without success: the action ran', () {
      expect(
        sysVerdictOf([
          Value.from({'message': 'done'}),
        ]),
        const Valid(SysVerdict(success: true, message: 'done')),
      );
    });

    test('an answer that is no map: the action ran, said nothing more', () {
      expect(
        sysVerdictOf(const [VStr('ok')]),
        const Valid(SysVerdict(success: true)),
      );
    });

    test('a success or a message of another type names its field', () {
      expect(
        sysVerdictOf([
          Value.from({'success': 'yes'}),
        ]),
        const Invalid<SysVerdict>('sys verdict', 'success', 'not a bool'),
      );
      expect(
        sysVerdictOf([
          Value.from({'success': true, 'message': 3}),
        ]),
        const Invalid<SysVerdict>('sys verdict', 'message', 'not a text'),
      );
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
      expect(rows['package:alarm-process'], (
        title: 'Alarms',
        summary: 'Classes',
        category: 'Apps',
        version: '0.3.0',
        form: CatalogForm.process,
        official: true,
      ));
      expect(rows['driver:mock'], (
        title: '',
        summary: '',
        category: '',
        version: '',
        form: null,
        official: false,
      ));
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
}
