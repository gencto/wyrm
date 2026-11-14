import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/alerts/trust_card.dart';
import 'package:ui/buttons/found_gateway_row.dart';
import 'package:ui/containers/discover_panel.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/log_in_page.dart';

// The data of boards *Discover*, *DiscoverScan*, *DiscoverTrust* and
// *DiscoverNone* (design canvas, docs/design/specs/unlock-discover.md §4),
// as LogInPage arguments.

void _none(Object? _) {}

FieldVm<String?> _field(String? v) => FieldVm(value: v, onChanged: _none);

const _wifi = 'Wi-Fi “Plant-OT”';

List<FoundGatewayRowVm> _rows() => [
  FoundGatewayRowVm(
    id: 'plant',
    site: 'plant',
    tags: [
      FoundTagVm(S.current.tagUsedBefore, Tone.good),
      FoundTagVm(S.current.tagActiveStandby, Tone.ember),
    ],
    hosts: S.current.hostsWithStandby('plant.local:8446', 'edge.local:8444'),
    note: '${S.current.noteWyrmd('0.9.4')} · ${S.current.notePinned('plant')}',
    seen: S.current.seenNow,
  ),
  FoundGatewayRowVm(
    id: 'line3',
    site: 'line3',
    tags: [FoundTagVm(S.current.tagDownstreamOf('plant'), Tone.neutral)],
    hosts: '10.0.7.31:8446 · reaches plant',
    note: '${S.current.noteWyrmd('0.9.4')} · ${S.current.noteKnownAs('plant')}',
    seen: S.current.seenAgo('2'),
  ),
  FoundGatewayRowVm(
    id: 'lab',
    site: 'lab',
    tags: [FoundTagVm(S.current.tagNew, Tone.warn)],
    hosts: 'lab-bench.local:8446',
    note: '${S.current.noteWyrmd('0.9.2')} · ${S.current.noteNew}',
    noteTone: Tone.warn,
    dot: Tone.warn,
    seen: S.current.seenAgo('3'),
  ),
  FoundGatewayRowVm(
    id: 'test-rig',
    site: 'test-rig',
    tags: [FoundTagVm(S.current.tagPlainHttp, Tone.bad)],
    hosts: 'http://10.0.7.88:8080',
    note: S.current.problemPlainHttp,
    noteTone: Tone.bad,
    dot: Tone.bad,
    seen: S.current.seenAgo('5'),
    enabled: false,
  ),
];

/// One frame of the *Find on this network* boards; [stage] as the board's
/// `stage` prop: `found`, `scan`, `trust`, `none`.
Widget discover(String stage) {
  final trust = stage == 'trust';
  final none = stage == 'none';
  final rows = _rows();
  return LogInPage(
    gateway: _field(
      trust
          ? 'https://lab-bench.local:8446'
          : none
          ? null
          : 'https://plant.local:8446',
    ),
    gatewayHint: 'https://host:port',
    user: _field('olena'),
    password: _field('correct-horse'),
    isWaiting: false,
    onPressedLogIn: () {},
    version: 'Studio 1.0 · English',
    standby: _field(null),
    gatewayTone: trust
        ? Tone.warn
        : none
        ? Tone.neutral
        : Tone.good,
    gatewayNote: trust
        ? S.current.pickedFrom('lab')
        : none
        ? S.current.typeOrFind
        : 'plant · answered in 12 ms',
    remember: const FieldVm<bool>(value: true, onChanged: _none),
    onFind: () {},
    discover: trust
        ? null
        : DiscoverPanelVm(
            title: switch (stage) {
              'scan' => S.current.discoverLooking('$_wifi (10.0.7.0/24)'),
              'none' => S.current.discoverNothing,
              _ => S.current.discoverFound(4, _wifi),
            },
            scanning: stage == 'scan',
            rows: switch (stage) {
              'scan' => rows.take(2).toList(),
              'none' => const [],
              _ => rows,
            },
            none: none
                ? DiscoverNoneVm(
                    title: S.current.discoverNoneTitle('Wi-Fi “Guest-5G”'),
                    reasons: [
                      DiscoverReasonVm(S.current.whyMulticast),
                      DiscoverReasonVm(
                        S.current.whyPermissionMac,
                        settings: S.current.openSettings,
                      ),
                      DiscoverReasonVm(
                        S.current.whyAnnounce,
                        tone: Tone.neutral,
                      ),
                      DiscoverReasonVm(S.current.whyType, tone: Tone.good),
                    ],
                    range: _field('10.0.7.0/24'),
                    port: _field('8446'),
                  )
                : null,
          ),
    onOpenSettings: () {},
    trust: trust
        ? TrustCardVm(
            title: S.current.trustTitle('lab'),
            why: S.current.trustWhy('lab'),
            code: const [
              '4F2A',
              '91C0',
              'D7E3',
              '5B18',
              'A0C4',
              '7E29',
              '3D6F',
              'B812',
            ],
            where: S.current.trustWhere('wyrmd ca fingerprint'),
            command: 'wyrmd ca fingerprint',
            trust: S.current.trustMatches('lab'),
          )
        : null,
    tls: trust
        ? S.current.tlsNotTrusted('lab')
        : S.current.tlsCertificateOf('plant'),
    tlsTone: trust ? Tone.warn : Tone.good,
  );
}
