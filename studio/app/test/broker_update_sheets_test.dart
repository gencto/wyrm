import 'package:app/common/broker_update_sheets.dart';
import 'package:business/wyrm/features.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/task_sheet.dart';

BrokerUpdateData _data({
  bool follow = false,
  String mode = 'self',
  String updateState = 'none',
  bool connected = true,
  String confirm = '',
  String? reason,
  Map<String, String> last = const {},
  int lostSeconds = 0,
}) => BrokerUpdateData(
  site: 'plant',
  version: '0.1.0',
  latest: '0.2.0',
  follow: follow,
  mode: mode,
  updateState: updateState,
  connected: connected,
  confirm: confirm,
  reason: reason,
  last: last,
  lostSeconds: lostSeconds,
);

/// The states of the broker update dialog (boards `BrokerUpdate*`, spec
/// `updates-backups.md` §3). The broker part does not exist: the values are
/// the ones ADR 0048 §2 names.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  test('every entry point is behind a flag that is off', () {
    expect(Features.brokerUpdate, isFalse);
  });

  test('the review asks for the site name before it updates', () {
    final empty = brokerUpdateSheet(_data());
    expect(empty.title, 'Update plant to wyrmd 0.2.0');
    expect(empty.pill, '0.1.0 → 0.2.0');
    expect(empty.primaryEnabled, isFalse);
    expect(empty.primaryReason, 'Type plant to confirm');

    expect(brokerUpdateSheet(_data(confirm: 'plan')).primaryEnabled, isFalse);
    expect(brokerUpdateSheet(_data(confirm: 'plant')).primaryEnabled, isTrue);
  });

  test('without config the update is locked with the reason', () {
    final vm = brokerUpdateSheet(
      _data(confirm: 'plant', reason: 'needs config on sys'),
    );
    expect(vm.primaryEnabled, isFalse);
    expect(vm.primaryReason, 'needs config on sys');
  });

  test('restarting: the gateway is lost, then the trial', () {
    final lost = _data(follow: true, connected: false, lostSeconds: 74);
    expect(lost.stage, BrokerUpdateStage.restarting);
    final vm = brokerUpdateSheet(lost);
    expect(
      vm.blocks.whereType<SheetSpinner>().single.text,
      contains('01:14'),
    );
    expect(vm.primaryEnabled, isFalse);
    expect(
      vm.blocks.whereType<SheetSteps>().single.steps.map((s) => s.state),
      [
        SheetStepState.done,
        SheetStepState.done,
        SheetStepState.now,
        SheetStepState.todo,
        SheetStepState.todo,
      ],
    );

    final trial = _data(follow: true, updateState: 'trial');
    expect(trial.stage, BrokerUpdateStage.restarting);
    expect(
      brokerUpdateSheet(
        trial,
      ).blocks.whereType<SheetSteps>().single.steps.map((s) => s.state),
      [
        SheetStepState.done,
        SheetStepState.done,
        SheetStepState.done,
        SheetStepState.now,
        SheetStepState.todo,
      ],
    );
  });

  test('a result shows only once the gateway is back', () {
    final offline = _data(
      follow: true,
      updateState: 'confirmed',
      connected: false,
    );
    expect(offline.stage, BrokerUpdateStage.restarting);
  });

  test('confirmed: the facts and a neutral Roll back', () {
    final d = _data(
      follow: true,
      updateState: 'confirmed',
      last: const {
        'from': '0.1.0',
        'to': '0.2.0',
        'down_s': '9',
        'links_back': '9',
        'links': '9',
        'back_s': '41',
        'rollback_until': '2026-11-20',
      },
    );
    expect(d.stage, BrokerUpdateStage.confirmed);
    final vm = brokerUpdateSheet(d);
    expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.good);
    final facts = vm.blocks.whereType<SheetFacts>().single.facts;
    expect(facts.map((f) => f.value), contains('9 of 9 in 41 s'));
    expect(facts.map((f) => f.value), contains('possible until 2026-11-20'));
    expect(vm.primary, 'Roll back to 0.1.0…');
    expect(vm.primaryQuiet, isTrue);
  });

  test('rolled back: a warn banner with the reason', () {
    final d = _data(
      follow: true,
      updateState: 'rolled_back',
      last: const {
        'from': '0.1.0',
        'to': '0.2.0',
        'reason': 'gateway: bind 127.0.0.1:8446: address in use',
      },
    );
    expect(d.stage, BrokerUpdateStage.rolledBack);
    final vm = brokerUpdateSheet(d);
    expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.warn);
    expect(
      vm.blocks.whereType<SheetFacts>().single.facts.map((f) => f.value),
      contains('gateway: bind 127.0.0.1:8446: address in use'),
    );
    expect(vm.primary, 'Open the log of 0.2.0');
  });

  test('external: no update, the commands and the backup', () {
    final d = _data(mode: 'external');
    expect(d.stage, BrokerUpdateStage.external);
    final vm = brokerUpdateSheet(d);
    expect(
      vm.blocks.whereType<SheetCode>().single.text,
      contains('ghcr.io/gencto/wyrmd:0.2.0'),
    );
    expect(vm.primary, 'Make the backup');
    expect(vm.blocks.whereType<SheetField>(), isEmpty);
  });
}
