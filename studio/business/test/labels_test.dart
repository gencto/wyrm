import 'package:business/wyrm/labels.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a human reads for a name the broker uses (owner 2026-11-11), by the
/// broker's own rule (ADR 0042). The first four groups are the cases of the
/// unit tests of `crates/wyrm-core/src/display.rs`, input for input and
/// output for output: change both sides together.
void main() {
  group('the rule of wyrm_core::display', () {
    test('humanize_keys', () {
      const cases = {
        'add_device': 'Add device',
        'remove': 'Remove',
        'read_registers': 'Read registers',
        'set_password': 'Set password',
        'unit_id': 'Unit ID',
        'id': 'ID',
        'base_url': 'Base URL',
        'url': 'URL',
        'add_mqtt': 'Add MQTT',
        'ca': 'CA',
        'skip_tls_check': 'Skip TLS check',
        'import_dsa': 'Import DSA',
        'timeout_ms': 'Timeout (ms)',
        'poll_rate_s': 'Poll rate (s)',
        'max_hz': 'Max (Hz)',
        'store_mb': 'Store (MB)',
        'retention_days': 'Retention (days)',
        'per_chat_us': 'Per chat (µs)',
        'ms': 'Ms',
        's': 'S',
        'qos': 'QoS',
        'add_ip_connection': 'Add IP connection',
        'get-log': 'Get log',
        'a_ab': 'A ab',
        'ADD_Device': 'Add device',
        '__x__': 'X',
        '': '',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(humanize(key), value, reason: key);
      }
    });

    test('humanized_keys_pass_the_check', () {
      for (final key in [
        'add_device',
        'unit_id',
        'timeout_ms',
        'mtls',
        'gzip',
        'a_ab',
      ]) {
        expect(check(humanize(key)), isNull, reason: key);
      }
    });

    test('sentence_case', () {
      const cases = {
        'Add Device': 'Add device',
        'Add IP Connection': 'Add IP connection',
        'Rescan For Serial Ports': 'Rescan for serial ports',
        'Slave ID': 'Slave ID',
        'Client Key (PEM)': 'Client key (PEM)',
        'Max Upload (MiB)': 'Max upload (MiB)',
        'Rate Limit (requests/s)': 'Rate limit (requests/s)',
        'Import from DSA': 'Import from DSA',
        'Add Modbus Device': 'Add Modbus device',
        'Use ReadPropertyMultiple': 'Use ReadPropertyMultiple',
        'Who-Is': 'Who-Is',
        'Install Link ▸': 'Install link ▸',
        'Unsubscribe and Purge': 'Unsubscribe and purge',
        'Write Mode': 'Write mode',
        'Use Socket Mode': 'Use Socket Mode',
        'Add AWS IoT Core': 'Add AWS IoT Core',
        'Scale (Linear, Then Offset)': 'Scale (Linear, Then Offset)',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(sentence(key), value, reason: key);
      }
    });

    test('check_refuses_what_breaks_the_style', () {
      for (final good in [
        'Add device',
        'Timeout (ms)',
        'Slave ID',
        'URL',
        'mTLS',
        'SNMP v3',
        '...',
        'Send to Slack',
      ]) {
        expect(check(good), isNull, reason: good);
      }
      for (final bad in [
        '',
        ' Add device',
        'add_device',
        'Add_device',
        'Add device.',
        'Base Url',
        'Unit id',
        'add device',
        'Add Device',
        'Poll Rate (s)',
      ]) {
        expect(check(bad), isNotNull, reason: bad);
      }
    });
  });

  test('a name reads in sentence case, a unit suffix in brackets', () {
    expect(humanize('a_ab'), 'A ab');
    expect(humanize('add_watch_path'), 'Add watch path');
    expect(humanize('edit'), 'Edit');
    expect(humanize('poll_s'), 'Poll (s)');
  });

  test("the meta's display wins; an empty one does not", () {
    expect(
      labelOf('add_watch_path', display: 'Add watch path'),
      'Add watch path',
    );
    expect(labelOf('add_watch_path', display: ' '), 'Add watch path');
    expect(labelOf('unit_id'), 'Unit ID');
  });

  test('a snake_case choice reads as words, any other stays as it is', () {
    expect(choiceLabel('read_back'), 'Read back');
    expect(choiceLabel('a_ab'), 'A ab');
    for (final raw in [
      'holding',
      'f32',
      '1m',
      'All Data',
      'pkg:modbus',
      'wy/edge/downstream',
      'portable-echo',
      'f32_wbswap',
    ]) {
      expect(choiceLabel(raw), raw, reason: raw);
    }
    expect(choiceLabels(['holding', 'read_back']), {'read_back': 'Read back'});
  });
}
