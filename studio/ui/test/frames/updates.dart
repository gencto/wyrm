// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/task_sheet.dart';
import 'package:ui/pages/links_page.dart';
import 'package:ui/tables/row_table.dart';

// The data of boards `LinkUpdate`, `LinkUpdateProgress`, `LinkUpdateDone`
// and `LinkUpdateRolledBack` (design canvas), as LinksPage arguments: the
// Updates tab with the update of `modbus` as a drawer.

void _none(Object? _) {}

RowVm _row(
  String id,
  String kind,
  String pkg,
  String origin,
  String version,
  String state, {
  bool selected = false,
  bool custom = false,
}) => RowVm(
  id: id,
  selected: selected,
  cells: [
    CellVm(title: id, subtitle: kind, strong: true),
    CellVm(title: pkg, subtitle: origin),
    CellVm(
      title: version,
      monospace: true,
      tone: custom ? null : Tone.ember,
      mark: Mark.none,
    ),
    CellVm(title: state, tone: custom ? Tone.ember : null, mark: Mark.none),
  ],
);

LinksPage _links(TaskSheetVm sheet) => LinksPage(
  title: 'Links on plant',
  subtitle: 'Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.',
  addLabel: 'Add a link',
  onTapLinkInstall: () {},
  secondLabel: 'Update all official…',
  onSecond: () {},
  tabs: const [
    TabItemVm(id: 'local', label: 'On this broker', count: '9'),
    TabItemVm(
      id: 'updates',
      label: 'Updates',
      count: '3',
      countTone: Tone.ember,
    ),
    TabItemVm(id: 'remote', label: 'On other devices', count: '2'),
    TabItemVm(id: 'quarantine', label: 'Quarantine', count: '0'),
  ],
  tab: 'updates',
  description: 'Links whose package has a newer version. Every link of a package is updated together, and the broker keeps what it needs to go back.',
  columns: const [
    ColumnVm('Link', flex: 3),
    ColumnVm('Package', flex: 3),
    ColumnVm('Version', flex: 2),
    ColumnVm('State', flex: 3),
  ],
  rows: [
    _row(
      'modbus',
      'Process',
      'package modbus',
      'official',
      '0.4.2 → 0.5.0',
      'updated together',
      selected: true,
    ),
    _row(
      'line2-modbus',
      'Process',
      'package modbus',
      'official',
      '0.4.2 → 0.5.0',
      'updated together',
    ),
    _row(
      'telegram',
      'WASM',
      'package telegram',
      'official',
      '0.3.0 → 0.3.1',
      '',
    ),
    _row(
      'counter-avg',
      'WASM',
      'package counter-avg',
      'custom',
      '1.2.0',
      'Update from file…',
      custom: true,
    ),
  ],
  onTab: _none,
  onRow: _none,
  onAction: _none,
  sheet: sheet,
  onSheetPrimary: () {},
  onSheetSecondary: () {},
  onSheetToggle: (_, {required value}) {},
  onSheetAction: _none,
  onSheetClose: () {},
);

/// Board `LinkUpdate`: the review of an official package.
LinksPage linkUpdateReview() => _links(
  const TaskSheetVm(
    title: 'Update modbus 0.4.2 → 0.5.0',
    pill: 'official',
    pillTone: Tone.good,
    sub: 'Official package · 2 links run it · released 11 Nov',
    blocks: [
      SheetLabel('What is new in 0.5.0'),
      SheetBullets([
        'FC23 read/write in one request',
        'Points keep their quality across a reconnect',
        'Fix: BCD32 word order on Schneider meters',
      ]),
      SheetLabel('What changes for the broker'),
      SheetCard(
        tone: Tone.warn,
        title: '2 links restart: modbus, line2-modbus',
        detail: 'About 5 s without values each; their nodes are declared again from the settings they keep.',
      ),
      SheetCard(
        title: 'Settings and nodes are kept',
        detail: 'The framework tree (2 connections, 6 devices, 142 points) stays in each link’s data folder and is read by 0.5.0.',
      ),
      SheetCard(
        tone: Tone.warn,
        title: 'It asks for one more network range',
        detail: 'net: 10.0.5.0/24 (scan of a second subnet). Not applied unless you accept it below.',
      ),
      SheetCard(
        title: 'Store format: same (state 3)',
        detail: 'The package says 0.5.0 reads the store of 0.4.2. A package that changes it says so here and rollback restores the old store.',
      ),
      SheetLabel('Before it starts'),
      SheetOption(
        id: 'point',
        label: 'Save a restore point of both links (settings, nodes, store, the package 0.4.2) · 3.1 MiB, kept 7 days',
        value: true,
      ),
      SheetOption(
        id: 'auto',
        label: 'Roll back by itself if a link does not come back with all its nodes in 2 min',
        value: true,
      ),
      SheetOption(
        id: 'accept',
        label: 'Accept the new rights it asks for (network 10.0.5.0/24)',
        value: false,
      ),
    ],
    note: 'Needs config on sys/links',
    secondary: 'Cancel',
    primary: 'Update 2 links',
  ),
);

/// Board `LinkUpdateProgress`: the health check runs.
LinksPage linkUpdateProgress() => _links(
  const TaskSheetVm(
    title: 'Updating modbus',
    pill: 'step 5 of 7',
    pillTone: Tone.ember,
    sub: 'Values of these two links pause while each restarts.',
    blocks: [
      SheetSteps([
        SheetStep(
          'Restore point saved',
          SheetStepState.done,
          detail: 'restore/modbus/2026-11-13T15:24 · 3.1 MiB',
        ),
        SheetStep(
          'Package fetched and checked',
          SheetStepState.done,
          detail: 'modbus-0.5.0-linux-aarch64.zip · SHA-256 ok',
        ),
        SheetStep(
          'Package unpacked beside 0.4.2',
          SheetStepState.done,
          detail: 'packages/modbus/0.5.0 (0.4.2 kept for rollback)',
        ),
        SheetStep(
          'modbus restarted on 0.5.0',
          SheetStepState.done,
          detail: 'hello in 1.8 s',
        ),
        SheetStep(
          'modbus: nodes declared again',
          SheetStepState.now,
          detail: '118 of 142 · waiting up to 2 min',
        ),
        SheetStep('line2-modbus restarted on 0.5.0', SheetStepState.todo),
        SheetStep(
          'Health: every link back with its nodes',
          SheetStepState.todo,
        ),
      ]),
    ],
    note: 'You can leave this screen; it goes on.',
    secondary: 'Stop and roll back',
    primary: 'Updating…',
    primaryEnabled: false,
  ),
);

/// Board `LinkUpdateDone`.
LinksPage linkUpdateDone() => _links(
  const TaskSheetVm(
    title: 'modbus updated',
    pill: 'done',
    pillTone: Tone.good,
    sub: '0.4.2 → 0.5.0 · 2 links · 38 s',
    blocks: [
      SheetBanner(
        title: 'Both links run 0.5.0',
        text: 'modbus and line2-modbus are back with all their nodes. 0.4.2 stays installed for 7 days so you can roll back in one step.',
      ),
      SheetLabel('Nodes before and after'),
      SheetTiles([
        SheetTile('226', 'kept'),
        SheetTile('+4', 'new in 0.5.0', tone: Tone.good),
        SheetTile('0', 'gone'),
      ]),
      SheetRow(
        sign: '+',
        tone: Tone.good,
        text: 'modbus/ip1/~act/read_write_registers',
        note: 'new action',
      ),
      SheetRow(
        sign: '+',
        tone: Tone.good,
        text: 'modbus/*/diagnostics/reconnects',
        note: 'new value, per connection',
      ),
      SheetLabel('Restore points'),
      SheetRow(
        divider: true,
        text: '0.4.2 · before update',
        note: 'today 15:24 · 3.1 MiB · kept 7 days',
        action: 'rollback',
        actionLabel: 'Roll back to 0.4.2…',
      ),
      SheetRow(
        divider: true,
        text: '0.4.1 · before update',
        note: '2 Nov · 2.8 MiB',
      ),
    ],
    note: 'Audit: package_update, restore_point',
    secondary: 'Close',
    primary: 'Open modbus',
  ),
);

/// Board `LinkUpdateRolledBack`.
LinksPage linkUpdateRolledBack() => _links(
  const TaskSheetVm(
    title: 'modbus update rolled back',
    pill: 'rolled back',
    pillTone: Tone.warn,
    sub: '0.5.0 → 0.4.2 · by itself after 2 min',
    blocks: [
      SheetBanner(
        tone: Tone.warn,
        title: 'Rolled back to 0.4.2',
        text: 'line2-modbus came back on 0.5.0 with 61 of 84 nodes in 2 min. Both links run 0.4.2 again with the store and settings of the restore point. The log of 0.5.0 is kept with the restore point.',
      ),
      SheetLabel('Nodes before and after'),
      SheetTiles([
        SheetTile('84', 'kept (0.4.2)'),
        SheetTile('0', 'new'),
        SheetTile('0', 'gone'),
      ]),
      SheetRow(
        sign: '!',
        tone: Tone.warn,
        text: 'line2-modbus/ip1/unit3/**',
        note: 'not declared by 0.5.0 (23 points)',
      ),
      SheetLabel('Restore points'),
      SheetRow(
        divider: true,
        text: '0.4.2 · before update',
        note: 'today 15:24 · in use',
      ),
    ],
    note: 'Audit: update_rollback',
    secondary: 'Close',
    primary: 'Open the log of 0.5.0',
  ),
);
