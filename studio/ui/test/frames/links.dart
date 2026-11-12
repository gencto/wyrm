// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:ui/buttons/action_row.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/detail_inspector.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/links_page.dart';
import 'package:ui/tables/row_table.dart';

// The data of boards *Studio · Links*, *Links · On other devices* and
// *Links · Quarantine* (design canvas), as LinksPage arguments.

void _none(Object? _) {}

List<TabItemVm> tabs() => const [
  TabItemVm(id: 'local', label: 'On this broker', count: '5'),
  TabItemVm(id: 'remote', label: 'On other devices', count: '3'),
  TabItemVm(
    id: 'quarantine',
    label: 'Quarantine',
    count: '3',
    countTone: Tone.warn,
  ),
];

LinksPage linksLocal() => LinksPage(
  title: 'Links on plant',
  subtitle: 'Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.',
  addLabel: 'Add a link',
  onTapLinkInstall: () {},
  tabs: tabs(),
  tab: 'local',
  description: 'Started and watched by plant: built-in drivers and installed packages. You can stop, change, upgrade and remove them.',
  columns: const [
    ColumnVm('Link', flex: 3),
    ColumnVm('Version · source', flex: 3),
    ColumnVm('Runs as', flex: 2),
    ColumnVm('State', flex: 3),
  ],
  rows: const [
    RowVm(
      id: 'modbus',
      selected: true,
      cells: [
        CellVm(
          title: 'modbus',
          subtitle: 'built-in driver modbus',
          strong: true,
        ),
        CellVm(title: 'wyrmd 0.9.4', subtitle: 'downstream/modbus'),
        CellVm(chip: 'Embedded'),
        CellVm(
          title: 'Connected',
          tone: Tone.good,
          subtitle: '2 connections · 23 devices',
        ),
      ],
    ),
    RowVm(
      id: 's7-press',
      cells: [
        CellVm(title: 's7-press', subtitle: 'built-in driver s7', strong: true),
        CellVm(title: 'wyrmd 0.9.4', subtitle: 'downstream/s7-press'),
        CellVm(chip: 'Process'),
        CellVm(
          title: 'Connected',
          tone: Tone.good,
          subtitle: '1 connection · up 3 d',
        ),
      ],
    ),
    RowVm(
      id: 'pg-history',
      cells: [
        CellVm(title: 'pg-history', subtitle: 'package postgres', strong: true),
        CellVm(title: '1.3.0 · repository', subtitle: 'sha256 9f2c…41ab'),
        CellVm(chip: 'WASM'),
        CellVm(
          title: 'Connected',
          tone: Tone.good,
          subtitle: '1.4.0 in the repository',
        ),
      ],
    ),
    RowVm(
      id: 'acme-meter',
      cells: [
        CellVm(
          title: 'acme-meter',
          subtitle: 'package acme-meter',
          strong: true,
        ),
        CellVm(title: '1.2.0 · zip', subtitle: 'sha256 0b7e…c912'),
        CellVm(chip: 'Process'),
        CellVm(
          title: 'Failed',
          tone: Tone.bad,
          subtitle: 'exit 101 · 5 restarts, stopped',
        ),
      ],
    ),
  ],
  onTab: _none,
  onRow: _none,
  onAction: _none,
  inspector: const DetailInspectorVm(
    eyebrow: 'Runs on plant',
    title: 'modbus',
    pill: StatusPillVm(label: 'Connected', tone: Tone.good),
    keyName: 'sys/links/modbus',
    facts: [
      FactVm(label: 'From', value: 'built-in driver modbus'),
      FactVm(label: 'Version', value: 'wyrmd 0.9.4'),
      FactVm(label: 'Runs as', value: 'Embedded'),
      FactVm(label: 'Branch', value: 'wy/plant/downstream/modbus', mono: true),
    ],
    groups: [
      ActionGroupVm(
        label: 'Run',
        actions: [
          ActionRowVm(
            id: 'stop',
            icon: 'action_stop',
            title: 'Stop',
            description:
                'Stays installed; its points go bad until you start it.',
            code: 'stop',
          ),
          ActionRowVm(
            id: 'log',
            icon: 'action_log',
            title: 'View log',
            description: 'Its last lines and its own log level.',
            code: 'get_log',
          ),
        ],
      ),
      ActionGroupVm(
        label: 'Version',
        actions: [
          ActionRowVm(
            id: 'builtin',
            icon: 'action_lock',
            title: 'Comes with wyrmd',
            disabledReason: 'A built-in driver updates with the broker.',
          ),
        ],
      ),
      ActionGroupVm(
        label: 'Remove',
        actions: [
          ActionRowVm(
            id: 'remove',
            icon: 'action_trash',
            title: 'Remove link',
            description: 'Stops it and deletes its tree.',
            code: 'remove',
            tone: Tone.bad,
          ),
        ],
      ),
    ],
  ),
);

LinksPage linksQuarantine() => LinksPage(
  title: 'Links on plant',
  subtitle: 'Links that run on this broker you manage fully. Links on other devices you only let in, limit or cut off.',
  addLabel: 'Add a link',
  onTapLinkInstall: () {},
  tabs: tabs(),
  tab: 'quarantine',
  description: 'Connections with a certificate from this site that no link is set up for. They can read and write nothing until you approve them.',
  settings: const [
    SettingCardVm(
      title: 'Hold unknown connections here',
      description: 'Off (with Allow all links off too): unknown certificates are ignored.',
      keyName: 'sys/enable_quarantine',
      value: FieldVm(value: true, onChanged: _none),
    ),
    SettingCardVm(
      title: 'Allow all links',
      description:
          'Every new CN from this CA becomes a link at once, no approval.',
      keyName: 'sys/allow_all_links',
      value: FieldVm(value: false, onChanged: _none),
    ),
  ],
  columns: const [
    ColumnVm('Who', flex: 3),
    ColumnVm('From', flex: 3),
    ColumnVm('Why here', flex: 2),
    ColumnVm('State', flex: 3),
  ],
  rows: const [
    RowVm(
      id: 'plc-gw-7',
      selected: true,
      cells: [
        CellVm(title: 'plc-gw-7', subtitle: 'link · over tls', strong: true),
        CellVm(title: 'from 10.0.9.40', subtitle: 'CA-signed · plant CA'),
        CellVm(chip: 'New'),
        CellVm(
          title: 'Waiting',
          tone: Tone.warn,
          subtitle: 'first seen 3 min ago',
        ),
      ],
    ),
    RowVm(
      id: 'broker:line3',
      cells: [
        CellVm(
          title: 'broker:line3',
          subtitle: 'downstream broker · over quic',
          strong: true,
        ),
        CellVm(title: 'from 10.0.13.2', subtitle: 'asks to relay: cell-a'),
        CellVm(chip: 'Broker'),
        CellVm(title: 'Waiting', tone: Tone.warn, subtitle: 'decide in Sites'),
      ],
    ),
  ],
  onTab: _none,
  onRow: _none,
  onAction: _none,
  inspector: const DetailInspectorVm(
    eyebrow: 'Waiting in quarantine',
    title: 'plc-gw-7',
    pill: StatusPillVm(
      label: 'Waiting',
      tone: Tone.warn,
      mark: Mark.ring,
    ),
    keyName: 'sys/quarantine/plc-gw-7',
    facts: [
      FactVm(label: 'From', value: 'from 10.0.9.40'),
      FactVm(label: 'Seen', value: 'first seen 3 min ago'),
      FactVm(label: 'Can do', value: 'nothing: no read, no write'),
    ],
    form: InspectorFormVm(
      id: 'plc-gw-7',
      label: 'Let it in',
      submit: 'Approve',
      secondary: 'Reject',
      note: 'Approve makes it an external link with its own branch and a link token.',
      fields: [
        ParamFieldVm(
          id: 'name',
          label: 'Display name',
          kind: ParamKind.text,
          onChanged: _none,
        ),
        ParamFieldVm(
          id: 'group',
          label: 'Who may operate it',
          kind: ParamKind.choice,
          value: 'engineer',
          choices: ['admin', 'engineer', 'operator'],
          onChanged: _none,
        ),
      ],
    ),
  ),
);
