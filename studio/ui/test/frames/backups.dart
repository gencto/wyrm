// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:material_ui/material_ui.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/task_sheet.dart';

import 'links.dart';
import 'system.dart';

// The data of boards `Backup`, `BackupProgress`, `BackupDone`,
// `BackupRestore` and `LinkBackup` (design canvas): the dialog over the
// workspace it was opened from.

/// A dialog [sheet] over [page], as `showDialog` lays it.
Widget over(Widget page, TaskSheetVm sheet, {double width = 680}) => Stack(
  children: [
    Positioned.fill(child: page),
    const Positioned.fill(child: ColoredBox(color: Colors.black54)),
    Positioned.fill(
      child: TaskSheet(
        vm: sheet,
        dialog: true,
        width: width,
        onPrimary: () {},
        onSecondary: () {},
        onToggle: (_, {required value}) {},
        onPick: (_, _) {},
        onText: (_, _) {},
        onAction: (_) {},
      ),
    ),
  ],
);

List<SheetChip> _ranges(int on) => [
  for (final (i, t) in const [
    'Last 7 days',
    'Last 30 days',
    'Last 90 days',
    'All',
  ].indexed)
    SheetChip(id: '$i', label: t, on: i == on),
];

List<SheetBlock> _sections({bool restore = false}) => [
  SheetSection(
    id: 'control',
    name: 'Control plane',
    size: '1.2 MiB',
    detail: 'Registry (links, grants, peers, tokens), users and roles, flow store, audit. Needed to restore anything else.',
    on: true,
    locked: !restore,
    tag: restore ? null : 'always',
  ),
  const SheetSection(
    id: 'keys',
    name: 'Keys and secrets',
    size: '48 KiB',
    detail: 'Site CA, state and secrets keys, gateway keys, link tokens and sealed secrets. Sealed with the passphrase below.',
    on: true,
    tag: 'passphrase',
    tagTone: Tone.warn,
  ),
  const SheetSection(
    id: 'dataflows',
    name: 'Dataflows',
    size: '310 KiB',
    detail: 'The artifacts of the flow engine; the flows themselves are in the control plane.',
    on: true,
  ),
  const SheetSection(
    id: 'storage',
    name: 'Broker storage',
    size: '2.4 MiB',
    detail: 'The storage tree and its values, with a JSON export for people.',
    on: true,
  ),
  SheetSection(
    id: 'history',
    name: 'History',
    size: '431 MiB',
    detail: 'The recorded days of the historian and its index.',
    on: !restore,
    chips: restore ? const [] : _ranges(1),
  ),
  SheetSection(
    id: 'links',
    name: 'Links',
    size: '22 MiB',
    detail: 'Per link: its definition, its secrets and its private data, sealed. Their packages go in too.',
    on: true,
    multi: true,
    chips: restore
        ? const []
        : [
            for (final id in const [
              'modbus',
              'line2-modbus',
              's7',
              'bacnet',
              'telegram',
              'scheduler',
              'alarm',
              'dql',
              'uplink',
            ])
              SheetChip(id: id, label: id, on: true),
          ],
  ),
  const SheetSection(
    id: 'packages',
    name: 'Installed packages',
    size: '18 MiB',
    detail: 'Every installed package as its files, so a restore needs no repository.',
    on: true,
  ),
  SheetSection(
    id: 'config',
    name: 'wyrmd.json5 (read only)',
    size: '6 KiB',
    detail: 'The configuration with secrets masked, for reference; a restore never writes it.',
    on: !restore,
    locked: restore,
  ),
];

/// Board `Backup`: what goes in, the passphrase, where.
Widget backupChoose() => over(
  systemMaint(),
  TaskSheetVm(
    title: 'Back up plant',
    sub: 'Pick what goes in. One .wyrm-backup file (a zip with a manifest); history days can be left out or limited.',
    blocks: [
      const SheetLabel('What goes in'),
      ..._sections(),
      const SheetField(
        id: 'passphrase',
        label: 'Passphrase for the keys and secrets',
        secret: true,
        note: 'Seals Keys and Secrets (Argon2id, ChaCha20-Poly1305), as wyrmd keys export. Without it they stay out. Studio never stores it.',
      ),
      const SheetChoice(
        id: 'where',
        label: 'Where',
        options: [
          ('computer', 'This computer'),
          ('store', 'File store link…'),
          ('broker', 'Keep on the broker'),
        ],
        selected: 'computer',
        note: 'A file store link (S3, WebDAV, a USB disk via localfs) takes it without passing through this computer.',
      ),
    ],
    note: 'About 482 MiB · config on sys',
    secondary: 'Cancel',
    primary: 'Back up',
  ),
);

/// Board `BackupProgress`.
Widget backupProgress() => over(
  systemMaint(),
  const TaskSheetVm(
    title: 'Backing up plant',
    sub: 'You can close this; the broker finishes it and keeps it under Backups.',
    blocks: [
      SheetBar(
        percent: 46,
        text:
            'History · day 2026-10-29 of 30 · 196 MiB of 431 MiB · 1 min left',
      ),
      SheetSteps([
        SheetStep('Control plane', SheetStepState.done),
        SheetStep('Keys and secrets, sealed', SheetStepState.done),
        SheetStep('Dataflows', SheetStepState.done),
        SheetStep('Broker storage', SheetStepState.done),
        SheetStep('History', SheetStepState.now),
        SheetStep('Links (9)', SheetStepState.todo),
        SheetStep('Installed packages', SheetStepState.todo),
      ]),
      SheetText(
        'Taken from one consistent moment (15:40:12): stores are read inside their own read transactions; the broker keeps running and writing.',
        small: true,
      ),
    ],
    note: '46 %',
    secondary: 'Close',
    primary: 'Backing up…',
    primaryEnabled: false,
    busy: true,
  ),
);

/// Board `BackupDone`.
Widget backupDone() => over(
  systemMaint(),
  const TaskSheetVm(
    title: 'Backup ready',
    sub: 'Download started · also kept on the broker for 7 days (Backups).',
    blocks: [
      SheetBanner(
        title: 'Saved plant-2026-11-13-1540.wyrm-backup',
        text: '462 MiB · 7 sections · checked after writing',
      ),
      SheetFacts([
        FactVm(label: 'SHA-256', value: '9f2c…41ab e07d…3c19', mono: true),
        FactVm(
          label: 'Contents',
          value: 'manifest.json, control/, secrets.sealed, storage.json, dataflows/, history/30 days, links/9',
        ),
        FactVm(label: 'Broker', value: 'plant · wyrmd 0.1.0 · registry 19'),
      ]),
      SheetText(
        "It holds the site's keys: whoever has the file and the passphrase is an administrator of plant.",
        small: true,
        tone: Tone.warn,
      ),
    ],
    secondary: 'Close',
    primary: 'Show in Backups',
  ),
);

/// Board `BackupRestore`.
Widget backupRestore() => over(
  systemMaint(),
  TaskSheetVm(
    title: 'Restore plant from a backup',
    sub: 'plant-2026-11-01-0300.wyrm-backup · tick what to bring back.',
    blocks: [
      const SheetLabel('Checked'),
      const SheetCard(
        title: 'plant-2026-11-01-0300.wyrm-backup · SHA-256 ok',
        detail: 'From plant · wyrmd 0.1.0 · registry 19 · 8 sections',
      ),
      const SheetCard(
        title: 'Same site and the same keys',
        detail: 'The CA and state key of this broker match the file; tokens and certificates stay valid.',
      ),
      const SheetCard(
        tone: Tone.warn,
        title: '3 links changed since then',
        detail: 'modbus 0.5.0 here, 0.4.2 in the file: restoring Links puts 0.4.2 back with its settings.',
      ),
      const SheetCard(
        tone: Tone.warn,
        title: 'Restart needed',
        detail: 'Control plane, keys and history are swapped while the broker is stopped; it restarts once (about 10 s).',
      ),
      const SheetLabel('In the file'),
      ..._sections(restore: true),
      const SheetChoice(
        id: 'mode',
        label: 'How',
        lines: true,
        options: [
          (
            'replace',
            'Replace what is ticked and restart the broker once (a backup of what it replaces is made first)',
          ),
          (
            'add',
            'Add only: links, flows and storage that do not exist yet; nothing replaced, no restart',
          ),
        ],
        selected: 'replace',
      ),
      const SheetField(
        id: 'passphrase',
        label: 'Passphrase of the backup',
        secret: true,
      ),
    ],
    note: 'A backup of what it replaces is made first',
    secondary: 'Cancel',
    primary: 'Restore and restart',
  ),
);

/// Board `LinkBackup`.
Widget linkBackup() => over(
  linksLocal(),
  TaskSheetVm(
    title: 'Back up the link modbus',
    sub: 'One file with everything modbus needs to come back, here or on another broker.',
    blocks: [
      const SheetLabel('What goes in'),
      const SheetSection(
        id: 'settings',
        name: 'Settings and nodes',
        size: '84 KiB',
        detail: 'Connections, devices, points as Export (wyrm-driver-branch/1), and grants and net of the link.',
        on: true,
        locked: true,
        tag: 'always',
      ),
      const SheetSection(
        id: 'data',
        name: 'Private data',
        size: '2.9 MiB',
        detail: 'data_dir/links/modbus/data: sealed settings and secrets (framework.tree), stores. Sealed with a passphrase.',
        on: true,
        tag: 'passphrase',
        tagTone: Tone.warn,
      ),
      const SheetSection(
        id: 'package',
        name: 'Package modbus 0.5.0',
        size: '3.4 MiB',
        detail: 'So it restores where the repository cannot be reached.',
        on: true,
      ),
      SheetSection(
        id: 'history',
        name: 'History of its points',
        size: '64 MiB',
        detail: '142 series watched under downstream/modbus.',
        on: true,
        chips: _ranges(0),
      ),
      const SheetFacts([
        FactVm(
          label: 'Link',
          value: 'modbus · process · package modbus 0.5.0 (official)',
        ),
        FactVm(
          label: 'Rights it has',
          value: 'write on downstream/modbus · net 10.0.4.0/24',
        ),
      ]),
      const SheetText(
        'Restore it on this broker (replaces the link, after a restore point) or on another broker as a new link: Links › Add › From backup. The package comes from the file when it is not installed there.',
        small: true,
      ),
      const SheetField(
        id: 'passphrase',
        label: 'Passphrase for the keys and secrets',
        secret: true,
      ),
      const SheetChoice(
        id: 'where',
        label: 'Where',
        options: [
          ('computer', 'This computer'),
          ('store', 'File store link…'),
          ('broker', 'Keep on the broker'),
        ],
        selected: 'computer',
      ),
    ],
    note: '70 MiB · config on sys/links',
    secondary: 'Cancel',
    primary: 'Back up modbus',
  ),
);
