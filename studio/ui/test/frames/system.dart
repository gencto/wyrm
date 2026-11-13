// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:ui/alerts/warn_banner.dart';
import 'package:ui/buttons/pill_tabs.dart';
import 'package:ui/charts/traffic_card.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/containers/attention_panel.dart';
import 'package:ui/containers/command_card.dart';
import 'package:ui/containers/guide_card.dart';
import 'package:ui/containers/standby_pair.dart';
import 'package:ui/containers/sys_tile.dart';
import 'package:ui/forms/log_toolbar.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/system_page.dart';
import 'package:ui/tables/log_table.dart';
import 'package:ui/tables/row_list.dart';
import 'package:ui/tables/term_table.dart';

import 'trend.dart';

// The data of boards `System`, `SystemAvail`, `SystemAvailLag`,
// `SystemAvailNone`, `SystemLog` and `SystemMaint` (design canvas), as
// SystemPage arguments, and two states the boards do not draw: loading and
// no `config` on `sys`.

void _none(Object? _) {}

/// The standby of a frame: following, behind, or none.
enum Ha { ok, lagging, none }

/// The board's polyline (`x,y` pairs in an 800 × 120 box, y down) as values
/// every 20 px, so the chart's even steps draw the same line.
List<double> _curve(String points) {
  final p = [
    for (final s in points.split(' '))
      (
        double.parse(s.split(',').first),
        120 - double.parse(s.split(',').last),
      ),
  ];
  final out = <double>[];
  for (var x = 0.0; x <= 800; x += 20) {
    final i = p.indexWhere((e) => e.$1 >= x);
    if (i <= 0) {
      out.add(p.first.$2);
    } else {
      final (x0, y0) = p[i - 1];
      final (x1, y1) = p[i];
      out.add(y0 + (y1 - y0) * (x - x0) / (x1 - x0));
    }
  }
  return out;
}

/// The board's two lines as a live trend: 41 samples over the hour from
/// 01:02 (UTC) to 02:02, in msg/s (the board's 120 px box × 80).
TrendVm _traffic(List<double> inward, List<double> outward) {
  final t0 = DateTime.utc(2026, 11, 12, 1, 2).microsecondsSinceEpoch;
  const step = 90 * 1000000;
  List<TrendSample> line(List<double> v) => [
    for (final (i, x) in v.indexed) TrendSample(t0 + i * step, x * 80),
  ];
  final end = t0 + (inward.length - 1) * step;
  return TrendVm(
    title: 'messages in and out per second over the last hour',
    series: [
      TrendSeriesVm(
        id: 'in',
        name: 'messages_in_per_second',
        label: 'in',
        color: .good,
        unit: 'msg/s',
        decimals: 0,
        samples: line(inward),
        overview: line(inward),
      ),
      TrendSeriesVm(
        id: 'out',
        name: 'messages_out_per_second',
        label: 'out',
        color: .text4,
        unit: 'msg/s',
        decimals: 0,
        samples: line(outward),
        overview: line(outward),
      ),
    ],
    rangeStart: t0,
    rangeEnd: end,
    windowStart: t0,
    windowEnd: end,
    rollup: 'raw',
    minWindow: 10 * step,
    endsNow: true,
    live: true,
    card: false,
    legend: false,
    hint: false,
    plotHeight: 120,
    format: trendFormat,
  );
}

const _reason = 'needs config on sys';

SystemPage _page({
  String tab = 'overview',
  Ha ha = Ha.ok,
  bool loading = false,
  bool rights = true,
}) {
  final lag = ha == Ha.lagging;
  final dash = loading ? '—' : null;
  final attention = <AttentionItemVm>[
    if (lag)
      const AttentionItemVm(
        id: 'standby',
        title: 'Standby is 1,240 records behind',
        detail: 'And one fork was moved aside after a split',
        go: 'Open Availability ›',
      ),
    const AttentionItemVm(
      id: 'link:bacnet',
      title: 'bacnet failed',
      detail: 'wasm component stopped: fuel limit reached during start',
      go: 'Open in Links ›',
      tone: Tone.bad,
    ),
    const AttentionItemVm(
      id: 'quarantine:field-gw',
      title: 'field-gw waits in quarantine',
      detail: 'Unknown certificate CN link:field-gw since 01:20',
      go: 'Open Quarantine ›',
    ),
    const AttentionItemVm(
      id: 'broker:line2',
      title: 'line2 waits for Authorize',
      detail: 'A downstream broker that relays 1 site',
      go: 'Open in Sites ›',
    ),
    if (ha == Ha.none)
      const AttentionItemVm(
        id: 'no-standby',
        title: 'No standby follows this broker',
        detail: 'standby_connected is 0',
        go: 'Open Availability ›',
        tone: Tone.neutral,
      ),
  ];
  return SystemPage(
    onTapViewsLab: () {},
    title: 'wyrmd on plant',
    pill: const StatusPillVm(label: 'Running · active', tone: Tone.good),
    meta: loading ? '—' : '0.1.0 · Zenoh 1.10.1 · rust (prod) · started 2026-11-04 21:58 UTC · up 6 d 4 h',
    tabsLabel: 'System sections',
    tabs: [
      const PillTabVm(id: 'overview', label: 'Overview'),
      PillTabVm(
        id: 'availability',
        label: 'Availability',
        dot: loading
            ? null
            : availabilityDot(standby: ha != Ha.none, behind: lag),
      ),
      const PillTabVm(id: 'log', label: 'Log'),
      const PillTabVm(id: 'maintenance', label: 'Maintenance'),
    ],
    tab: tab,
    onTab: _none,
    overview: SystemOverviewVm(
      groups: [
        TileGroupVm(
          label: 'Links and sites',
          tiles: [
            SysTileVm(
              label: 'Links connected',
              keyName: 'links_connected',
              value: dash ?? '4',
              unit: loading ? '' : 'of 5',
              sub: loading ? 'open Links' : 'bacnet failed · open Links',
              subTone: loading ? Tone.neutral : Tone.bad,
              about: 'Links whose liveliness token is present (they serve their tree).',
              link: true,
            ),
            SysTileVm(
              label: 'In quarantine',
              keyName: 'quarantined',
              value: dash ?? '1',
              sub: loading
                  ? 'open Quarantine'
                  : 'field-gw waits · open Quarantine',
              tone: loading ? Tone.neutral : Tone.warn,
              subTone: loading ? Tone.neutral : Tone.warn,
              outlined: !loading,
              about: 'Unknown certificates waiting in quarantine.',
              link: true,
            ),
            SysTileVm(
              label: 'Packages',
              keyName: 'packages_total',
              value: dash ?? '6',
              sub: 'installed link packages',
              link: true,
            ),
            SysTileVm(
              label: 'Upstream',
              keyName: 'upstream_connected',
              value: dash ?? '1',
              unit: 'connected',
              sub: loading ? 'open Sites' : 'edge · open Sites',
              about: 'Upstream brokers that are connected.',
              link: true,
            ),
            SysTileVm(
              label: 'Downstream',
              keyName: 'downstream_connected',
              value: dash ?? '1',
              unit: 'connected',
              sub: loading ? 'open Sites' : 'line2 · open Sites',
              about: 'Downstream brokers that are connected.',
              link: true,
            ),
            SysTileVm(
              label: 'Sessions',
              keyName: 'sessions',
              value: dash ?? '14',
              sub: 'network sessions; gateway users not counted',
              about: 'Network sessions of the router: links, peer brokers. Gateway users share one in-process session.',
            ),
          ],
        ),
        TileGroupVm(
          label: 'Process and disk',
          tiles: [
            SysTileVm(
              label: 'CPU',
              keyName: 'cpu',
              value: dash ?? '17',
              unit: '%',
              sub: '100 = one core',
              about: 'CPU time of the broker process over the metrics interval; 100 = one core.',
            ),
            SysTileVm(
              label: 'Memory',
              keyName: 'memory',
              value: dash ?? '212',
              unit: 'MiB',
              sub: 'resident',
              about: 'Resident memory of the broker process.',
            ),
            SysTileVm(
              label: 'Free disk',
              keyName: 'disk_free',
              value: dash ?? '38.2',
              unit: loading ? 'MiB' : 'GiB',
              sub: 'on the data_dir file system',
              about: 'Free space on the file system of data_dir.',
            ),
            SysTileVm(
              label: 'data_dir',
              keyName: 'data_size',
              value: dash ?? '1.9',
              unit: loading ? 'MiB' : 'GiB',
              sub: loading ? 'open History' : 'history 1.4 GiB · open History',
              about: 'Size of data_dir, measured every minute.',
              link: true,
            ),
            SysTileVm(
              label: 'ACL denials',
              keyName: 'acl_denied',
              value: dash ?? '3',
              sub: 'since the router started · open Audit',
              about: "Messages the router's access control dropped since the router started.",
              link: true,
            ),
            SysTileVm(
              label: 'Audit records',
              keyName: 'audit_records',
              value: dash ?? '18,402',
              sub: 'who did what · open Audit',
              about: 'Records in the audit journal.',
              link: true,
            ),
          ],
        ),
      ],
      traffic: TrafficCardVm(
        title: 'Router traffic',
        measures: const [
          PillTabVm(id: 'messages', label: 'Messages'),
          PillTabVm(id: 'frames', label: 'Frames'),
          PillTabVm(id: 'bytes', label: 'Bytes'),
        ],
        measure: 'messages',
        inKey: 'messages_in_per_second',
        outKey: 'messages_out_per_second',
        inNow: dash ?? '5,120',
        outNow: dash ?? '4,870',
        unit: 'msg/s',
        trend: loading
            ? null
            : _traffic(
                _curve(
                  '0,58 40,57 80,59 120,56 160,57 200,58 240,57 280,56 320,57 360,58 400,57 440,104 460,70 480,58 520,57 560,56 600,58 640,57 680,55 720,57 760,56 800,57',
                ),
                _curve(
                  '0,52 40,50 80,51 120,49 160,50 200,52 240,51 280,50 320,49 360,51 400,50 440,96 460,62 480,51 520,50 560,49 600,51 640,50 680,48 720,50 760,49 800,50',
                ),
              ),
        note: 'Sampled from the `sys` rates while Studio is open (the broker keeps no history of them). Network sessions only: embedded links and gateway users talk in-process and are not counted.',
        empty: 'Collecting…',
      ),
    ),
    availability: ha == Ha.none
        ? const SystemAvailVm(
            guide: GuideCardVm(
              title: 'No standby is following this broker',
              body: '`sys/standby_connected` is 0. Either no warm standby is configured, or the one configured cannot reach this broker. If this host fails, the site stops until it is back; links on other machines walk to their next endpoint only if they have one.',
              stepsTitle: 'To add one (on the hosts, not in Studio)',
              steps: [
                '1. Copy the keys to the second host: `wyrmd keys export` here, `wyrmd keys import` there.',
                '2. In `wyrmd.json5` on both hosts: `standby: {peer, takeover_s, primary, witness}` and `peers.listen`; a lease `arbiter` on a third host is recommended.',
                '3. Start the second host; this tab shows it within a second.',
              ],
              link: 'Guide: docs/operations.md › Warm standby ›',
            ),
          )
        : SystemAvailVm(
            pair: StandbyPairVm(
              activeLabel: 'This broker · active',
              activeName: 'plant',
              activeNote: 'Serves links, flows, the gateway and peers. Answers `sys/replication/**` for its standby.',
              flow: 'WAL, files, storage, history',
              every: 'pulled every 1 s',
              standbyLabel: lag ? 'Standby · behind' : 'Standby · following',
              standbyName: 'standby:plant',
              standbyNote: 'Same keys, own `data_dir`. Takes over only if this broker stops answering and a witness still answers it.',
              behind: lag,
            ),
            tiles: [
              const SysTileVm(
                label: 'Standby connected',
                keyName: 'standby_connected',
                value: '1',
                sub: 'follows this broker over the peer link',
                tone: Tone.good,
                about: '1 while a warm standby follows this broker over the peer link (ADR 0036).',
              ),
              SysTileVm(
                label: 'Lag',
                keyName: 'standby_lag',
                value: lag ? '1,240' : '0',
                unit: 'records',
                sub: lag
                    ? 'not on the standby yet: a takeover now loses them'
                    : 'the standby has every registry record',
                tone: lag ? Tone.warn : Tone.neutral,
                subTone: lag ? Tone.warn : Tone.neutral,
                outlined: lag,
                about: 'Records of the registry WAL the standby has not received yet.',
              ),
              SysTileVm(
                label: 'Arbiter lease',
                keyName: 'arbiter_lease_s',
                value: lag ? '2' : '8',
                unit: 's left',
                sub: lag
                    ? 'renewing late: check the arbiter host'
                    : 'renewed by the lease arbiter',
                tone: lag ? Tone.warn : Tone.neutral,
                subTone: lag ? Tone.warn : Tone.neutral,
                about: 'Seconds left of the lease the arbiters granted this broker; 0 without arbiters.',
              ),
              SysTileVm(
                label: 'Forks moved aside',
                keyName: 'standby_forks',
                value: lag ? '1' : '0',
                unit: 'since start',
                sub: lag
                    ? 'after a healed split · audit standby_forked'
                    : 'no split since this broker started',
                tone: lag ? Tone.bad : Tone.neutral,
                subTone: lag ? Tone.bad : Tone.neutral,
                about: 'Sets of records the standby moved aside after a healed split.',
              ),
            ],
            banner: lag
                ? const WarnBannerVm(
                    title: 'The standby is behind and moved a fork aside',
                    body: '1,240 registry records are not on the standby yet: a takeover now would lose them. One set of records was moved aside after both brokers were active (a healed split): the audit record `standby_forked` says which.',
                    action: 'Open the audit record ›',
                  )
                : null,
            heldTitle: 'What the standby holds',
            held: const [
              TermVm(
                term: 'Control plane',
                text: 'Registry, flow definitions and gateway users: the WAL records themselves, checked against the HMAC chain.',
              ),
              TermVm(
                term: 'Secrets and link data',
                text: 'secrets.bin, link tokens, link data_dirs and packages: sealed parts of 1 MiB, files up to 64 MiB, removed when gone here.',
              ),
              TermVm(
                term: 'Broker storage',
                text: 'The storage change journal, applied into the standby’s own storage (full tree beyond 20,000 changes).',
              ),
              TermVm(
                term: 'History',
                text: 'Every series’ rows from the change journal, written into the standby’s own day files.',
              ),
            ],
          ),
    log: SystemLogVm(
      toolbar: LogToolbarVm(
        sourceLabel: 'Source',
        sources: const [
          ChoiceItemVm(value: '', label: 'broker (all)'),
          ChoiceItemVm(value: 'scheduler', label: 'link: scheduler'),
          ChoiceItemVm(value: 'alarm', label: 'link: alarm'),
          ChoiceItemVm(value: 'dql', label: 'link: dql'),
          ChoiceItemVm(value: 'uplink', label: 'link: uplink'),
          ChoiceItemVm(value: 'storage', label: 'link: storage'),
        ],
        source: '',
        levelLabel: 'Level and more severe',
        levels: const [
          ChoiceItemVm(value: 'info', label: 'info'),
          ChoiceItemVm(value: 'warn', label: 'warn'),
          ChoiceItemVm(value: 'error', label: 'error'),
          ChoiceItemVm(value: 'debug', label: 'debug'),
          ChoiceItemVm(value: 'trace', label: 'trace'),
        ],
        level: 'info',
        filterLabel: 'Filter',
        filterHint: 'text in the target or message',
        filter: '',
        linesLabel: 'Lines',
        lines: 200,
        autoLabel: 'every 5 s',
        auto: true,
        getLabel: 'Get log',
        aroundLabel: 'Around (UTC)',
        aroundHint: 'hh:mm:ss',
        aroundClear: 'Show every time',
        aroundBad: 'Type a time as hh:mm or hh:mm:ss.',
        disabledReason: rights ? null : _reason,
      ),
      summary: rights
          ? "200 lines from the broker's ring · newest first · `sys/~act/get_log`"
          : '`sys/~act/get_log` · config',
      copyLabel: 'Copy',
      saveLabel: 'Save as .log',
      rows: rights
          ? const [
              LogRowVm(
                time: '02:01:44',
                level: 'INFO',
                target: 'gateway',
                message: 'olena: set …/plc1/t2/~set ok (read back in 212 ms)',
              ),
              LogRowVm(
                time: '01:58:10',
                level: 'WARN',
                target: 'admin::peers',
                message: 'line2 asks for broker:line2 relaying 1 site; waits for Authorize',
              ),
              LogRowVm(
                time: '01:56:31',
                level: 'ERROR',
                target: 'link{id=bacnet}',
                message:
                    'wasm component stopped: fuel limit reached during start',
              ),
              LogRowVm(
                time: '01:56:30',
                level: 'INFO',
                target: 'admin::supervisor',
                message: 'bacnet: restart 3 of 5, back-off 8 s',
              ),
              LogRowVm(
                time: '01:41:02',
                level: 'INFO',
                target: 'admin',
                message: 'ACL rebuilt from registry (23 rules); router runtime restarted in 0.9 s',
              ),
              LogRowVm(
                time: '01:41:01',
                level: 'INFO',
                target: 'admin::standby',
                message: 'standby held for the rebuild (hold_until +60 s)',
              ),
              LogRowVm(
                time: '01:30:00',
                level: 'INFO',
                target: 'history',
                message: 'day file 2026-11-10 opened; 1,204 series',
              ),
              LogRowVm(
                time: '01:12:22',
                level: 'INFO',
                target: 'admin::peers',
                message: 'upstream edge connected; 6 streams reopened',
              ),
              LogRowVm(
                time: '01:12:18',
                level: 'WARN',
                target: 'admin::peers',
                message: 'upstream edge unreachable, retry in 4 s',
              ),
              LogRowVm(
                time: '01:02:07',
                level: 'INFO',
                target: 'gateway',
                message: 'admin logged in from 10.0.1.24',
              ),
            ]
          : const [],
      message: rights
          ? 'No lines at this level.'
          : 'The log is read with config on sys.',
      levelTitle: 'Broker log level',
      levelKey: 'sys/log_level',
      levelNote: "Staged in Review and apply; once applied it takes effect at once, no restart, and replaces `RUST_LOG`. Zenoh stays at warn below trace. Values and tokens are never logged below trace. A link's own level: Links › the link › Log.",
      levels: const [
        PillTabVm(id: 'error', label: 'error'),
        PillTabVm(id: 'warn', label: 'warn'),
        PillTabVm(id: 'info', label: 'info'),
        PillTabVm(id: 'debug', label: 'debug'),
        PillTabVm(id: 'trace', label: 'trace'),
      ],
      level: 'info',
      levelReason: rights ? null : _reason,
    ),
    maintenance: SystemMaintVm(
      staleTitle: 'Disconnected links',
      staleNote: 'Links admitted at runtime that run on other machines and are not connected now. Clearing removes them from the registry; their ids are retired and cannot be used again.',
      stale: const [
        RowItemVm(
          id: 'meter-07',
          title: 'meter-07',
          subtitle: 'external · CN link:meter-07',
          trailing: 'not connected',
        ),
        RowItemVm(
          id: 'field-gw-old',
          title: 'field-gw-old',
          subtitle: 'external · CN link:field-gw-old',
          trailing: 'not connected',
        ),
      ],
      staleEmpty: 'No disconnected links.',
      clearLabel: 'Clear 2 disconnected links…',
      clearReason: rights ? null : _reason,
      staleFooter: '`sys/~act/clear_conns` · config · asks before it runs',
      profilesTitle: 'Device profiles',
      profilesNote: 'Models served as `pub/<vendor>:<model>`: points, units and ranges that links and the assistant inherit.',
      putLabel: 'Put profile…',
      putReason: rights ? null : _reason,
      profiles: [
        for (final (name, points) in const [
          ('schneider:pm5560', '48 points'),
          ('abb:m4m-30', '36 points'),
          ('carel:pco5', '22 points'),
        ])
          RowItemVm(
            id: name,
            title: name,
            trailing: points,
            action: 'Remove',
            actionHint: 'Remove profile $name',
            actionReason: rights ? null : _reason,
          ),
      ],
      profilesEmpty: 'No profiles.',
      profilesFooter: '`sys/profiles` › Put Profile, Remove Profile · config',
      backupTitle: 'Back up and restore',
      backupNote: "Everything the broker owns is in its `data_dir` (here 1.9 GiB). Studio does not take backups: they hold the site's keys and are made on the host. The steps, ready to copy:",
      commands: const [
        CommandCardVm(
          id: 'backup',
          title: 'Back up (broker stopped)',
          code: 'sudo systemctl stop wyrmd\nsudo tar --same-permissions -czf /backup/wyrm-plant.tgz -C /var/lib wyrm\nsudo systemctl start wyrmd',
          note: 'Consistent and simplest. With a filesystem snapshot (LVM, btrfs, ZFS) the broker can keep running.',
          copyLabel: 'Copy: Back up (broker stopped)',
        ),
        CommandCardVm(
          id: 'verify',
          title: 'Check a copy',
          code: 'wyrmd -c /etc/wyrm/wyrmd.json5 verify',
          note: 'Checks every control-plane store offline: CRC, HMAC chain, anchors. Run it on the restored data_dir before a start.',
          copyLabel: 'Copy: Check a copy',
        ),
        CommandCardVm(
          id: 'check',
          title: 'Before a restart with a changed file',
          code: 'wyrmd -c /etc/wyrm/wyrmd.json5 check',
          note:
              'The configuration parses and validates; exit code 1 otherwise.',
          copyLabel: 'Copy: Before a restart with a changed file',
        ),
      ],
      backupWarning: "A backup holds the site CA and the gateway key: whoever reads it is an administrator. Encrypt it and keep it where only the broker's administrators can read it.",
      elsewhereLabel: 'Also broker settings, kept where they are used:',
      elsewhere: const [
        ElsewhereVm(
          id: 'quarantine',
          label: 'Admission of new links › Links › Quarantine',
        ),
        ElsewhereVm(id: 'sites', label: 'Tokens for sites below › Sites'),
        ElsewhereVm(id: 'access', label: 'Roles and grants › Access'),
        ElsewhereVm(id: 'history', label: 'Retention and purge › History'),
      ],
    ),
    attention: AttentionPanelVm(
      heading: 'Needs a look · ${loading ? 0 : attention.length}',
      note: "From the broker's own values. Each opens the screen where it is fixed.",
      empty: 'Nothing needs a look.',
      items: loading ? const [] : attention,
      factsTitle: 'This broker',
      facts: [
        const BrokerFactVm(label: 'Site', value: 'plant', mono: true),
        const BrokerFactVm(
          label: 'Liveliness',
          value: 'wy/plant/sys/broker',
          mono: true,
          dot: Tone.good,
        ),
        BrokerFactVm(
          label: 'Started',
          value: loading ? '—' : '2026-11-04 21:58 UTC',
        ),
        BrokerFactVm(
          label: 'Build',
          value: loading ? '—' : '0.1.0 · rust (prod)',
        ),
      ],
    ),
    onAttention: _none,
    onTile: _none,
    onMeasure: _none,
    onSource: _none,
    onLevel: _none,
    onFilter: _none,
    onLines: _none,
    onAround: _none,
    onAuto: _none,
    onGetLog: () {},
    onCopyLog: () {},
    onSaveLog: () {},
    onLogLevel: _none,
    onClear: () {},
    onPutProfile: () {},
    onRemoveProfile: _none,
    onCopyCommand: _none,
    onElsewhere: _none,
    onBanner: () {},
    onGuide: () {},
  );
}

/// Board `System`: the Overview.
SystemPage systemOverview() => _page();

/// Board `SystemAvail`: the standby follows.
SystemPage systemAvail() => _page(tab: 'availability');

/// Board `SystemAvailLag`: the standby is behind and moved a fork aside.
SystemPage systemAvailLag() => _page(tab: 'availability', ha: Ha.lagging);

/// Board `SystemAvailNone`: no standby.
SystemPage systemAvailNone() => _page(tab: 'availability', ha: Ha.none);

/// Board `SystemLog`.
SystemPage systemLog() => _page(tab: 'log');

/// Board `SystemMaint`.
SystemPage systemMaint() => _page(tab: 'maintenance');

/// No `sys` value yet: tiles with `—`, the traffic `Collecting…`.
SystemPage systemLoading() => _page(loading: true);

/// The user's grants do not reach `config` on `sys`: the values are shown,
/// the controls are disabled with the reason (Maintenance).
SystemPage systemNoRights() => _page(tab: 'maintenance', rights: false);

/// The same on the Log tab: the log cannot be read, the level not changed.
SystemPage systemLogNoRights() => _page(tab: 'log', rights: false);
