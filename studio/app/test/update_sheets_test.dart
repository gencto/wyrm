import 'package:app/common/sizes.dart';
import 'package:app/common/update_sheets.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/package_info.dart';
import 'package:models/restore_point.dart';
import 'package:models/update_report.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/task_sheet.dart';

UpdateReport _report(String result, {int at = 10, int gone = 0}) =>
    UpdateReport(
      from: '0.4.2',
      to: '0.5.0',
      at: at,
      result: result,
      kept: 226,
      added: 4,
      gone: gone,
      newKeys: const ['modbus/a'].lock,
      goneKeys: [if (gone > 0) 'line2/b'].lock,
      links: const ['modbus', 'line2'].lock,
      reason: gone > 0 ? 'line2: 61 of 84 nodes' : '',
      restorePoint: true,
    );

PackageInfo _pkg({
  UpdateReport? last,
  bool changesState = false,
  String? previous,
  String latest = '0.5.0',
}) => PackageInfo(
  name: 'modbus',
  version: '0.4.2',
  latest: latest,
  updateAvailable: latest.isNotEmpty,
  changesState: changesState,
  state: 3,
  previous: previous,
  keepUntil: 1700000000,
  lastUpdate: last,
);

UpdateSheetData _data(
  PackageInfo p, {
  bool follow = false,
  String? asks,
  bool acceptNew = false,
  bool busy = false,
  int seenAt = -1,
  String? reason,
  bool official = true,
  bool takePoint = true,
}) => UpdateSheetData(
  package: p,
  links: const ['modbus', 'line2'],
  follow: follow,
  official: official,
  asks: asks,
  acceptNew: acceptNew,
  busy: busy,
  seenAt: seenAt,
  reason: reason,
  takePoint: takePoint,
  points: const [('modbus', RestorePoint(at: 5, version: '0.4.2', size: 3000))],
);

T _one<T extends SheetBlock>(TaskSheetVm vm, bool Function(T) test) =>
    vm.blocks.whereType<T>().firstWhere(test);

/// The states of the update sheet (boards `LinkUpdate*`, spec
/// `updates-backups.md` §1).
void main() {
  setUpAll(() => S.load(const Locale('en')));

  test('the review of an official package offers the update', () {
    final vm = updateSheet(_data(_pkg()));
    expect(vm.title, 'Update modbus 0.4.2 → 0.5.0');
    expect(vm.primary, 'Update links: 2');
    expect(vm.primaryEnabled, isTrue);
    expect(vm.blocks.whereType<SheetOption>().map((o) => o.id), [
      'point',
      'auto',
    ]);
  });

  test('a store format change locks the restore point on', () {
    final vm = updateSheet(
      _data(_pkg(changesState: true), takePoint: false),
    );
    final point = _one<SheetOption>(vm, (o) => o.id == 'point');
    expect(point.value, isTrue);
    expect(point.enabled, isFalse);
    expect(point.reason, isNotNull);
  });

  test('new rights hold the update until they are accepted', () {
    const asks = 'modbus 0.5.0 asks for more: net 10.0.5.0/24';
    final held = updateSheet(_data(_pkg(), asks: asks));
    expect(held.primaryEnabled, isFalse);
    expect(_one<SheetCard>(held, (c) => c.detail == asks).tone, Tone.warn);
    expect(_one<SheetOption>(held, (o) => o.id == 'accept').value, isFalse);

    final accepted = updateSheet(_data(_pkg(), asks: asks, acceptNew: true));
    expect(accepted.primaryEnabled, isTrue);
  });

  test('without config the update is locked with the reason', () {
    final vm = updateSheet(
      _data(_pkg(), reason: 'needs config on sys/links'),
    );
    expect(vm.primaryEnabled, isFalse);
    expect(vm.primaryReason, 'needs config on sys/links');
  });

  test('a custom package is updated from a file', () {
    final d = _data(_pkg(latest: ''), official: false);
    expect(updateSheet(d).primary, 'Choose the archive…');
    expect(updatePrimary(d), 'file');
  });

  test('progress while the action runs and while the check runs', () {
    final running = _data(_pkg(last: _report('ok')), follow: true, busy: true);
    expect(running.stage, UpdateStage.progress);

    // The action answered; the report of before is still the one shown.
    final stale = _data(_pkg(last: _report('ok')), follow: true, seenAt: 10);
    expect(stale.stage, UpdateStage.progress);

    final checking = _data(
      _pkg(last: _report('checking', at: 11)),
      follow: true,
      seenAt: 10,
    );
    expect(checking.stage, UpdateStage.progress);
    final vm = updateSheet(checking);
    expect(vm.secondary, 'Stop and roll back');
    expect(vm.primaryEnabled, isFalse);
    final steps = vm.blocks.whereType<SheetSteps>().single.steps;
    expect(steps.map((s) => s.state), [
      SheetStepState.done,
      SheetStepState.done,
      SheetStepState.done,
      SheetStepState.now,
    ]);
  });

  test('ok: a good banner, the counts, and Open', () {
    final d = _data(
      _pkg(last: _report('ok', at: 11), previous: '0.4.2'),
      follow: true,
      seenAt: 10,
    );
    expect(d.stage, UpdateStage.result);
    final vm = updateSheet(d);
    expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.good);
    expect(
      vm.blocks.whereType<SheetTiles>().single.tiles.map((t) => t.number),
      ['226', '+4', '0'],
    );
    expect(vm.primary, 'Open modbus');
    expect(updatePrimary(d), 'open');
    // The newest restore point offers the rollback while a version is kept.
    final point = _one<SheetRow>(vm, (r) => r.divider);
    expect(point.action, 'rollback');
    expect(point.actionLabel, 'Roll back to 0.4.2…');
  });

  test('ok with nodes gone warns and offers the rollback', () {
    final d = _data(
      _pkg(last: _report('ok', gone: 23), previous: '0.4.2'),
      follow: true,
    );
    final vm = updateSheet(d);
    expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.warn);
    expect(
      vm.blocks.whereType<SheetBanner>().single.text,
      contains('61 of 84'),
    );
    expect(updatePrimary(d), 'rollback');
    expect(vm.primaryQuiet, isTrue);
  });

  test('rolled back: a warn banner, no second rollback', () {
    final d = _data(_pkg(last: _report('rolled_back')), follow: true);
    final vm = updateSheet(d);
    expect(vm.pill, 'rolled back');
    // The report keeps the update's from and to: the links run `from`.
    expect(
      vm.blocks.whereType<SheetBanner>().single.title,
      'Rolled back to 0.4.2',
    );
    expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.warn);
    expect(_one<SheetRow>(vm, (r) => r.divider).action, isNull);
    expect(updatePrimary(d), 'log');
  });

  test('failed keeps the new version and offers the rollback', () {
    final d = _data(
      _pkg(last: _report('failed'), previous: '0.4.2'),
      follow: true,
    );
    expect(updateSheet(d).pill, 'failed');
    expect(updatePrimary(d), 'rollback');
  });

  test('restore points without any update: no progress, no rollback', () {
    // Review point 9.
    final d = _data(_pkg(), follow: true);
    expect(d.stage, UpdateStage.points);
    final vm = updateSheet(d);
    expect(vm.title, 'Versions of modbus');
    expect(vm.primary, isNull);
    expect(vm.secondary, 'Close');
    expect(vm.blocks.whereType<SheetSteps>(), isEmpty);
    expect(vm.blocks.whereType<SheetRow>().single.action, isNull);
    expect(updatePrimary(d), '');

    // The first update of a package, started from this sheet: progress.
    expect(_data(_pkg(), follow: true, seenAt: 0).stage, UpdateStage.progress);
  });

  test('sizes read in binary units', () {
    expect(bytesText(812), '812 B');
    expect(bytesText(48 * 1024), '48 KiB');
    expect(bytesText(3250586), '3.1 MiB');
    expect(bytesText(3 << 30), '3 GiB');
  });
}
