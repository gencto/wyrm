import 'package:material_ui/material_ui.dart';
import 'package:ui/alerts/unreachable_alert.dart';
import 'package:ui/buttons/recent_chip.dart';
import 'package:ui/containers/welcome_panel.dart';
import 'package:ui/models/gateway_note.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/log_in_page.dart';

// The data of boards *Login*, *LoginSigning*, *LoginWrong*,
// *LoginUnreachable* and *LoginWelcome* (design canvas), as LogInPage
// arguments.

void _none(Object? _) {}

FieldVm<String?> _field(String? v) => FieldVm(value: v, onChanged: _none);

const _steps = [
  'Reaching plant',
  'Checking user and password',
  'Reading your role and sites',
];

List<RecentChipVm> _recent({bool down = false}) => [
  RecentChipVm(
    id: 'https://plant.local:8446',
    label: 'plant',
    tone: down ? Tone.bad : Tone.good,
    current: true,
  ),
  const RecentChipVm(
    id: 'https://edge.local:8444',
    label: 'edge',
    tone: Tone.good,
  ),
  const RecentChipVm(
    id: 'https://central.example:8445',
    label: 'central',
    tone: Tone.good,
  ),
];

/// One state of the log-in page; [stage] as the board's `stage` prop.
Widget login({
  String stage = 'idle',
  bool remember = true,
  bool? busy,
  String gateway = 'https://plant.local:8446',
  List<RecentChipVm>? recent,
  GatewayNote? note,
  Tone? gatewayTone,
}) {
  final unreachable = stage == 'unreachable';
  final wrong = stage == 'wrong';
  return LogInPage(
    gateway: _field(gateway),
    user: _field('olena'),
    password: FieldVm(
      value: 'correct-horse',
      onChanged: _none,
      error: wrong
          ? 'User or password is wrong. Ask an administrator to reset it; '
                'the gateway never sends it by mail.'
          : null,
    ),
    isWaiting: busy ?? stage == 'signing',
    onPressedLogIn: () {},
    version: 'Studio 1.0 · English',
    standby: _field(null),
    gatewayTone: gatewayTone ?? (unreachable ? Tone.bad : Tone.good),
    gatewayNote:
        note ??
        (unreachable
            ? const GatewayNote.noAnswer('plant')
            : const GatewayNote.answered('plant', 12)),
    recent: recent ?? _recent(down: unreachable),
    onRecent: _none,
    remember: FieldVm(value: remember, onChanged: _none),
    steps: _steps,
    step: 1,
    wrong: wrong,
    unreachable: unreachable
        ? const UnreachableAlertVm(
            detail: 'https://plant.local:8446 · connection refused after 5 s',
            advice:
                'The broker may be restarting or this computer is on another '
                'network.',
            standby: 'edge.local:8444',
          )
        : null,
    onRetry: () {},
    onUseStandby: () {},
    tls: 'TLS · certificate of the plant CA',
    // ADR 0050: the gateway field has `Find on this network` beside it
    // (docs/design/specs/unlock-discover.md §4); the Login boards predate it.
    onFind: () {},
    welcome: stage == 'welcome'
        ? const WelcomePanelVm(
            title: 'Welcome, olena',
            site: 'plant',
            facts: [
              'engineer on plant · reaches edge and central',
              '14 links · 2 flows · 1 waiting in quarantine',
            ],
            // The preload at its third step (owner decision 2026-11-08,
            // docs/design/specs/login.md §5): the board has no step list.
            steps: [
              'Reading the tree of plant',
              'Reading the flows',
              'Reading the flow blocks',
              'Reading the links',
              'Reading the sites',
            ],
            step: 2,
          )
        : null,
  );
}

/// Five gateways on one computer (the demo's ports), labelled by
/// `gatewayLabel` (docs/design/specs/login.md §3.2 "Gateway labels"): the
/// one in the field does not answer.
const oneHostLabels = [
  '127.0.0.1:8444',
  '127.0.0.1:8445',
  '127.0.0.1:8446',
  '127.0.0.1:18448',
  '127.0.0.1:18449',
];

Widget loginOneHost() => login(
  gateway: 'http://127.0.0.1:8446',
  note: const GatewayNote.noAnswer('127.0.0.1:8446'),
  gatewayTone: Tone.bad,
  recent: [
    for (final l in oneHostLabels)
      RecentChipVm(
        id: 'http://$l',
        label: l,
        tone: l.endsWith(':8446') ? Tone.bad : Tone.good,
        current: l.endsWith(':8446'),
      ),
  ],
);
