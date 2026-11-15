import 'package:app/mappers/links_mappers.dart';
import 'package:business/wyrm/link_update.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/package_info.dart';
import 'package:models/restore_point.dart';
import 'package:models/update_next.dart';
import 'package:models/update_report.dart';
import 'package:models/update_result.dart';
import 'package:models/update_stage.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/link_update_sheet.dart';
import 'package:ui/overlays/task_sheet.dart';

UpdateReport _report(UpdateResult result, {int at = 10, int gone = 0}) =>
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

LinkUpdate _data(
  PackageInfo p, {
  bool follow = false,
  String? asks,
  bool acceptNew = false,
  bool busy = false,
  int seenAt = -1,
  String? reason,
  bool official = true,
  bool takePoint = true,
}) => LinkUpdate(
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
  points: const [
    LinkPoint('modbus', RestorePoint(at: 5, version: '0.4.2', size: 3000)),
  ],
);

T _one<T extends SheetBlock>(TaskSheetVm vm, bool Function(T) test) =>
    vm.blocks.whereType<T>().firstWhere(test);

/// The sheet of [d], with its options and its rollback link reporting.
TaskSheetVm sheet(LinkUpdate d) => linkUpdateSheet(
  d.ui,
  onTakePoint: (_) {},
  onAutoRollback: (_) {},
  onAcceptNew: (_) {},
  onRollBack: () {},
);

/// The states of the update sheet (boards `LinkUpdate*`, spec
/// `updates-backups.md` §1), decided in `business` (`LinkUpdate`) and
/// worded in `ui` (`linkUpdateSheet`).
void main() {
  setUpAll(() => S.load(const Locale('en')));

  test('the review of an official package offers the update', () {
    final vm = sheet(_data(_pkg()));
    expect(vm.title, 'Update modbus 0.4.2 → 0.5.0');
    expect(vm.primary, 'Update links: 2');
    expect(vm.primaryEnabled, isTrue);
    expect(vm.blocks.whereType<SheetOption>().map((o) => o.label), [
      S.current.updOptPoint,
      S.current.updOptAuto,
    ]);
  });

  test('a store format change locks the restore point on', () {
    final vm = sheet(
      _data(_pkg(changesState: true), takePoint: false),
    );
    final point = _one<SheetOption>(
      vm,
      (o) => o.label == S.current.updOptPoint,
    );
    expect(point.value, isTrue);
    expect(point.enabled, isFalse);
    expect(point.reason, isNotNull);
  });

  test('new rights hold the update until they are accepted', () {
    const asks = 'modbus 0.5.0 asks for more: net 10.0.5.0/24';
    final held = sheet(_data(_pkg(), asks: asks));
    expect(held.primaryEnabled, isFalse);
    expect(_one<SheetCard>(held, (c) => c.detail == asks).tone, Tone.warn);
    expect(
      _one<SheetOption>(held, (o) => o.label == S.current.updOptAccept).value,
      isFalse,
    );

    final accepted = sheet(_data(_pkg(), asks: asks, acceptNew: true));
    expect(accepted.primaryEnabled, isTrue);
  });

  test('without config the update is locked with the reason', () {
    final vm = sheet(
      _data(_pkg(), reason: 'needs config on sys/links'),
    );
    expect(vm.primaryEnabled, isFalse);
    expect(vm.primaryReason, 'needs config on sys/links');
  });

  test('a custom package is updated from a file', () {
    final d = _data(_pkg(latest: ''), official: false);
    expect(sheet(d).primary, 'Choose the archive…');
    expect(d.next, UpdateNext.file);
  });

  test('progress while the action runs and while the check runs', () {
    final running = _data(
      _pkg(last: _report(UpdateResult.ok)),
      follow: true,
      busy: true,
    );
    expect(running.stage, UpdateStage.progress);

    // The action answered; the report of before is still the one shown.
    final stale = _data(
      _pkg(last: _report(UpdateResult.ok)),
      follow: true,
      seenAt: 10,
    );
    expect(stale.stage, UpdateStage.progress);

    final checking = _data(
      _pkg(last: _report(UpdateResult.checking, at: 11)),
      follow: true,
      seenAt: 10,
    );
    expect(checking.stage, UpdateStage.progress);
    final vm = sheet(checking);
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
      _pkg(last: _report(UpdateResult.ok, at: 11), previous: '0.4.2'),
      follow: true,
      seenAt: 10,
    );
    expect(d.stage, UpdateStage.result);
    final vm = sheet(d);
    expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.good);
    expect(
      vm.blocks.whereType<SheetTiles>().single.tiles.map((t) => t.number),
      ['226', '+4', '0'],
    );
    expect(vm.primary, 'Open modbus');
    expect(d.next, UpdateNext.open);
    // The newest restore point offers the rollback while a version is kept.
    final point = _one<SheetRow>(vm, (r) => r.divider);
    expect(point.onAction, isNotNull);
    expect(point.actionLabel, 'Roll back to 0.4.2…');
  });

  test('ok with nodes gone warns and offers the rollback', () {
    final d = _data(
      _pkg(last: _report(UpdateResult.ok, gone: 23), previous: '0.4.2'),
      follow: true,
    );
    final vm = sheet(d);
    expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.warn);
    expect(
      vm.blocks.whereType<SheetBanner>().single.text,
      contains('61 of 84'),
    );
    expect(d.next, UpdateNext.rollback);
    expect(vm.primaryQuiet, isTrue);
  });

  test('rolled back: a warn banner, no second rollback', () {
    final d = _data(_pkg(last: _report(UpdateResult.rolledBack)), follow: true);
    final vm = sheet(d);
    expect(vm.pill, 'rolled back');
    // The report keeps the update's from and to: the links run `from`.
    expect(
      vm.blocks.whereType<SheetBanner>().single.title,
      'Rolled back to 0.4.2',
    );
    expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.warn);
    expect(_one<SheetRow>(vm, (r) => r.divider).onAction, isNull);
    expect(d.next, UpdateNext.log);
  });

  test('a result this client does not know is said as the broker said it', () {
    final d = _data(
      _pkg(
        last: _report(UpdateResult.unknown).copyWith(resultWord: 'quarantined'),
      ),
      follow: true,
    );
    expect(d.stage, UpdateStage.result);
    final vm = sheet(d);
    expect(vm.pill, S.current.updPillUnknown);
    final banner = vm.blocks.whereType<SheetBanner>().single;
    expect(banner.title, S.current.updUnknownResult('quarantined'));
    expect(banner.tone, Tone.warn);
    expect(d.next, UpdateNext.open);
  });

  test('failed keeps the new version and offers the rollback', () {
    final d = _data(
      _pkg(last: _report(UpdateResult.failed), previous: '0.4.2'),
      follow: true,
    );
    expect(sheet(d).pill, 'failed');
    expect(d.next, UpdateNext.rollback);
  });

  test('restore points without any update: no progress, no rollback', () {
    // Review point 9.
    final d = _data(_pkg(), follow: true);
    expect(d.stage, UpdateStage.points);
    final vm = sheet(d);
    expect(vm.title, 'Versions of modbus');
    expect(vm.primary, isNull);
    expect(vm.secondary, 'Close');
    expect(vm.blocks.whereType<SheetSteps>(), isEmpty);
    expect(vm.blocks.whereType<SheetRow>().single.onAction, isNull);
    expect(d.next, isNull);

    // The first update of a package, started from this sheet: progress.
    expect(_data(_pkg(), follow: true, seenAt: 0).stage, UpdateStage.progress);
  });

  test('sizes read in binary units', () {
    expect(Formats.bytes(812), '812 B');
    expect(Formats.bytes(48 * 1024), '48 KiB');
    expect(Formats.bytes(3250586), '3.1 MiB');
    expect(Formats.bytes(3 << 30), '3 GiB');
  });
}
