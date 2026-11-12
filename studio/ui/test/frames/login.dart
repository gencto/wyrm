import 'package:material_ui/material_ui.dart';
import 'package:ui/alerts/unreachable_alert.dart';
import 'package:ui/buttons/recent_chip.dart';
import 'package:ui/containers/welcome_panel.dart';
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
}) {
  final unreachable = stage == 'unreachable';
  final wrong = stage == 'wrong';
  return LogInPage(
    gateway: _field('https://plant.local:8446'),
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
    gatewayTone: unreachable ? Tone.bad : Tone.good,
    gatewayNote: unreachable
        ? 'No answer from plant'
        : 'plant · answered in 12 ms',
    recent: _recent(down: unreachable),
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
