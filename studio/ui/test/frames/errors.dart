// The boards' sentences are long: a list of them reads best one string
// per item, split over lines.
// ignore_for_file: no_adjacent_strings_in_list

import 'package:material_ui/material_ui.dart';
import 'package:ui/alerts/panel_fault.dart';
import 'package:ui/alerts/start_fault.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/buttons/problems_pill.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/indicators/fail_chip.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/problems_drawer.dart';
import 'package:ui/theme/extensions/colors.dart';
import 'package:ui/theme/typography.dart';

// The data of the boards of the canvas row "Errors" (`ErrorDialog` and its
// frames `ErrReach`, `ErrInput`, `ErrBusy`, `ErrGone`, `ErrBroker`,
// `ErrStudio`; `ErrorQuiet`, `ErrorProblems`; `ErrorPanel`, `ErrorFatal`),
// as view-models of the widgets that draw them.

const _when = '2026-11-10 11:52:04 (local)';

List<ErrorRowVm> _brokerRows(String code, String hex, String where) {
  final [key, call] = where.split(' › ');
  return [
    ErrorRowVm('Status', '$code (0x$hex)'),
    ErrorRowVm('Call', '$call on $key'),
    ErrorRowVm('Site', key.split('/')[1]),
    const ErrorRowVm('As', 'olena (operator)'),
    const ErrorRowVm('Gateway', 'https://plant.local:8445'),
    const ErrorRowVm('Time', _when),
  ];
}

/// The dialog of one kind, as the board's `kind` prop draws it; [details]
/// as its `details` prop (open).
ErrorDialogVm errorDialogVm(String kind, {bool details = false}) {
  ErrorDialogVm broker({
    required Tone tone,
    required String icon,
    required String title,
    required String where,
    required String said,
    required List<String> advice,
    required String code,
    required String hex,
    required String primary,
    String saidLabel = 'The broker said',
    String? secondary,
    String? note,
    int? countdown,
  }) => ErrorDialogVm(
    tone: tone,
    icon: icon,
    title: title,
    where: where,
    saidLabel: saidLabel,
    said: said,
    advice: advice,
    note: note,
    chip: code,
    details: _brokerRows(code, hex, where),
    detailsOpen: details,
    secondary: secondary,
    primary: primary,
    countdown: countdown,
    countdownLabel: (s) => 'Try again in $s s',
  );
  return switch (kind) {
    'reach' => broker(
      tone: .warn,
      icon: 'err_reach',
      title: 'edge did not answer',
      where: 'wy/edge/downstream/modbus/plc1/t2 › set',
      saidLabel: 'Studio waited 10 s',
      said:
          'No answer from the broker at edge. The link to it is up, so the '
          'broker or the device behind it is slow.',
      advice: const [
        'Try again; if it keeps timing out, look at the link’s status in '
            'Links.',
      ],
      note:
          'A write that timed out may still have been applied. Check the '
          'value before you send it again.',
      code: 'timeout',
      hex: '28',
      primary: 'Try again',
      secondary: 'Close',
    ),
    'input' => broker(
      tone: .ember,
      icon: 'err_input',
      title: 'The broker refused these parameters',
      where: 'wy/plant/downstream/modbus/plc1 › edit',
      said: 'poll_rate: 0 is below the minimum of 100 ms.',
      advice: const [
        'Back in the form, the field is marked; correct it and save again.',
      ],
      code: 'invalid_parameter',
      hex: '23',
      primary: 'Back to the form',
    ),
    'busy' => broker(
      tone: .neutral,
      icon: 'err_busy',
      title: 'plant is busy, the install did not start',
      where: 'wy/plant/sys/links › install_repo',
      said:
          'An access-control rebuild is in progress; new installs are '
          'refused until the router is back.',
      advice: const [
        'Studio can try again by itself when the broker is ready.',
      ],
      code: 'busy',
      hex: '24',
      primary: 'Try again',
      secondary: 'Close',
      countdown: 4,
    ),
    'gone' => broker(
      tone: .neutral,
      icon: 'err_gone',
      title: 'pump-control is not there anymore',
      where: 'wy/plant/dataflows/pump-control › get_def',
      said: 'No node at dataflows/pump-control.',
      advice: const [
        'Someone removed or renamed it after this screen loaded. Refresh to '
            'see what is there now.',
      ],
      code: 'not_found',
      hex: '27',
      primary: 'Refresh',
      secondary: 'Close',
    ),
    'broker' => broker(
      tone: .bad,
      icon: 'err_broker',
      title: 'Installing modbus 0.4.2 failed on plant',
      where: 'wy/plant/sys/links › install_repo',
      said:
          'unpack modbus-0.4.2.zip: wyrm-link.json: wyrm_link 3 is newer '
          'than this broker (2).',
      advice: const [
        'Install a version built for this broker, or update wyrmd on plant.',
        'The broker log around 11:52 has the rest of the story.',
      ],
      code: 'internal_error',
      hex: '25',
      primary: 'Open the log',
      secondary: 'Close',
    ),
    'studio' => ErrorDialogVm(
      tone: .bad,
      icon: 'err_studio',
      title: 'Studio could not open this flow',
      where: 'Flow editor › open pump-control',
      saidLabel: 'What happened',
      said:
          'Studio could not read the saved layout of this flow. This is a '
          'fault in Studio, not on the broker; nothing was sent.',
      advice: const [
        'Open the flow again; Studio lays it out afresh if the layout stays '
            'unreadable.',
        'Copy the report and send it to us: it holds no values or passwords.',
      ],
      chip: 'studio · FormatException',
      details: const [
        ErrorRowVm(
          'Error',
          'FormatException: Unexpected character (at offset 412)',
        ),
        ErrorRowVm('In', 'flow_layout_mapper.dart › decode'),
        ErrorRowVm('Screen', 'Flow editor'),
        ErrorRowVm('Studio', '0.3.0 (macOS 15.1)'),
        ErrorRowVm('Time', _when),
        ErrorRowVm('Report', 'the stack trace is in the copied report only'),
      ],
      detailsOpen: details,
      copy: 'Copy report',
      primary: 'OK',
    ),
    _ => broker(
      tone: .warn,
      icon: 'err_rights',
      title: 'You can’t deploy pump-control',
      where: 'wy/plant/dataflows/pump-control › deploy',
      said:
          'Deploying needs config on dataflows/pump-control. Your role '
          'operator has write there.',
      advice: const [
        'Ask an administrator for config on dataflows, or ask one to deploy '
            'it.',
        'Your edits stay in the editor; nothing was sent to the plant.',
      ],
      code: 'permission_denied',
      hex: '21',
      primary: 'OK',
      secondary: 'See my access',
    ),
  };
}

/// The screen the boards draw under an error surface: placeholders of the
/// top bar (48), the rail (64) and a page. Not a Studio screen: the boards
/// use it to show where a surface sits, and so do these frames.
class ErrorBackdrop extends StatelessWidget {
  const ErrorBackdrop({
    this.title = 'Dataflows',
    this.trailing,
    this.rail = 5,
    this.active = 1,
    this.page,
    this.side,
    super.key,
  });

  final String title;

  /// In the top bar before the account dot (the Problems pill); a grey bar
  /// when null.
  final Widget? trailing;
  final int rail;
  final int active;

  /// Under the title; three cards and a tall one when null.
  final Widget? page;

  /// A panel on the right of the page (the Problems drawer, the inspector).
  final Widget? side;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget box(double w, double h, double r, Color color) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: color, borderRadius: .circular(r)),
    );
    Widget card(double h) => Container(
      height: h,
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: .circular(10),
      ),
    );
    return ColoredBox(
      color: c.ground0,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.ground1,
              border: Border(bottom: BorderSide(color: c.line1)),
            ),
            child: Row(
              spacing: 12,
              children: [
                box(22, 22, 6, c.emberTint),
                Text(
                  'WYRM Studio',
                  style: boardText(weight: .w600, color: c.text1),
                ),
                Text('plant', style: boardText(color: c.text4)),
                const Spacer(),
                trailing ?? box(120, 10, 5, c.ground4),
                box(28, 28, 14, c.ground4),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: .stretch,
              children: [
                Container(
                  width: 64,
                  padding: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(
                    color: c.ground1,
                    border: Border(right: BorderSide(color: c.line1)),
                  ),
                  child: Column(
                    spacing: 14,
                    children: [
                      for (var i = 0; i < rail; i++)
                        box(28, 28, 8, i == active ? c.emberTint : c.ground4),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Text(
                          title,
                          style: boardText(
                            size: 24,
                            weight: .w600,
                            color: c.text1,
                          ),
                        ),
                        SizedBox(height: page == null ? 16 : 14),
                        if (page case final p?)
                          p
                        else ...[
                          Row(
                            spacing: 12,
                            children: [
                              for (var i = 0; i < 3; i++)
                                Expanded(child: card(120)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          card(360),
                        ],
                      ],
                    ),
                  ),
                ),
                ?side,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One frame of the dialog boards: the dimmed screen, the scrim, the card.
Widget errorDialogFrame(String kind, {bool details = false}) => Stack(
  fit: .expand,
  children: [
    const ErrorBackdrop(),
    const ColoredBox(color: ErrorDialog.scrim),
    ErrorDialog(
      vm: errorDialogVm(kind, details: details),
      onPrimary: () {},
      onClose: () {},
      onSecondary: () {},
      onCopy: () {},
    ),
  ],
);

/// The toasts of board `ErrorQuiet`: a stream that is down (it stays) and a
/// read that failed (it hides in 8 s).
const errorToasts = [
  ToastVm(
    id: 2,
    title: 'Live values from edge stopped',
    line:
        'The peer link went down. Studio reopens the streams when it is back.',
    details: true,
    stays: 'stays until edge is back',
  ),
  ToastVm(
    id: 1,
    title: 'Reading t2 failed',
    line: 'timeout: the device did not answer within 2 s.',
    details: true,
    retry: true,
  ),
];

/// The five problems of board `ErrorProblems`, newest first.
const errorProblems = [
  ProblemVm(
    id: 5,
    title: 'Reading t2 failed',
    time: '11:52:06',
    where: 'wy/plant/downstream/modbus/plc1/t2 › subscribe',
    said: 'timeout: the device did not answer within 2 s.',
    retry: true,
  ),
  ProblemVm(
    id: 4,
    title: 'Live values from edge stopped',
    time: '11:49:41',
    where: 'wy/edge/downstream/** › subscribe',
    said:
        'disconnected: the peer link to edge went down; Studio reopens the '
        'streams when it is back.',
  ),
  ProblemVm(
    id: 3,
    title: 'You can’t deploy pump-control',
    time: '11:47:12',
    where: 'wy/plant/dataflows/pump-control › deploy',
    said: 'permission_denied: needs config on dataflows/pump-control.',
    shown: true,
  ),
  ProblemVm(
    id: 2,
    tone: .neutral,
    title: 'History of flow_rate unavailable',
    time: '11:30:02',
    where: 'wy/plant/downstream/modbus/plc1/flow_rate › history',
    said: 'not_found: no watch records this point.',
  ),
  ProblemVm(
    id: 1,
    tone: .bad,
    title: 'Installing modbus 0.4.2 failed on plant',
    time: '11:12:55',
    where: 'wy/plant/sys/links › install_repo',
    said: 'internal_error: wyrm_link 3 is newer than this broker (2).',
    shown: true,
  ),
];

/// The explorer rows the boards draw under the quiet surfaces: a table of
/// names and values, with the `read failed` chip on `t2`.
class _Rows extends StatelessWidget {
  const _Rows({this.failed = true, this.times = true});

  final bool failed;
  final bool times;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = [
      ('modbus', 0.0, '', ''),
      ('plc1', 18.0, '', ''),
      ('t1', 36.0, '21.4 °C', '11:52:10'),
      ('t2', 36.0, failed ? '—' : '22.9 °C', failed ? 'no value' : ''),
      ('pump_on', 36.0, 'true', '11:51:58'),
      if (times) ('flow_rate', 36.0, '12.8 m³/h', '11:52:09'),
      ('plc2', 18.0, '', ''),
    ];
    return Container(
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: .circular(10),
      ),
      child: Column(
        children: [
          for (final (name, indent, value, time) in rows)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: name != 't2'
                    ? null
                    : failed
                    ? const Color(0xFF1A1311)
                    : const Color(0xFF1F1A16),
                border: Border(top: BorderSide(color: c.ground3)),
              ),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: indent),
                      child: Row(
                        spacing: 8,
                        children: [
                          Text(
                            name,
                            style: boardText(
                              size: 13,
                              color: c.text1,
                              code: true,
                            ),
                          ),
                          if (failed && name == 't2')
                            const FailChip(
                              vm: FailChipVm(
                                label: 'read failed',
                                tip:
                                    'Reading the value failed: timeout. '
                                    'Details in Problems.',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(
                      value,
                      style: boardText(
                        size: 13,
                        color: failed && name == 't2' ? c.muted : c.text1,
                        code: true,
                      ),
                    ),
                  ),
                  if (times)
                    SizedBox(
                      width: 120,
                      child: Text(
                        time,
                        style: boardText(size: 12, color: c.text4),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Boards `ErrorQuiet` ([drawer] false: the toasts and the mark on the row)
/// and `ErrorProblems` ([drawer] true: the drawer, no toasts).
Widget errorQuietFrame({bool drawer = false}) => Stack(
  fit: .expand,
  children: [
    ErrorBackdrop(
      title: 'Explorer',
      rail: 4,
      active: 0,
      trailing: ProblemsPill(
        vm: ProblemsPillVm(label: '3 problems', bad: true, open: drawer),
        onTap: () {},
      ),
      page: const _Rows(),
      side: !drawer
          ? null
          : ProblemsDrawer(
              problems: errorProblems,
              onClose: () {},
              onClear: () {},
              onDetails: (_) {},
              onRetry: (_) {},
            ),
    ),
    if (!drawer)
      Positioned(
        right: 20,
        bottom: 20,
        width: ToastStack.width,
        child: ToastStack(
          toasts: errorToasts,
          onDismiss: (_) {},
          onDetails: (_) {},
          onRetry: (_) {},
        ),
      ),
  ],
);

/// The card of board `ErrorPanel`.
const errorPanelVm = PanelFaultVm(
  title: 'The inspector could not be drawn',
  body:
      'Something in t2’s description is not what Studio expects. The rest '
      'of Studio still works; values and actions elsewhere are not affected.',
  line: 'RangeError (index): Invalid value: 3 · node_inspector · 11:52:06',
);

/// Board `ErrorPanel`: the inspector failed to draw, the rest works.
Widget errorPanelFrame() => Builder(
  builder: (context) {
    final c = context.colors;
    return ErrorBackdrop(
      title: 'Explorer',
      rail: 3,
      active: 0,
      trailing: ProblemsPill(
        vm: const ProblemsPillVm(label: '1 problem', bad: true),
        onTap: () {},
      ),
      page: const _Rows(failed: false, times: false),
      side: Container(
        // The board's 360 is the content box: 20 of padding each side
        // and the 1 px line are outside it.
        width: 401,
        padding: const EdgeInsets.only(top: 40),
        decoration: BoxDecoration(
          color: c.ground1,
          border: Border(left: BorderSide(color: c.line1)),
        ),
        child: PanelFault(vm: errorPanelVm, onDrawAgain: () {}, onCopy: () {}),
      ),
    );
  },
);

/// Board `ErrorFatal`: Studio cannot open its own settings.
Widget errorFatalFrame() => StartFault(
  vm: const StartFaultVm(
    title: 'Studio could not start',
    body:
        'The settings it saved on this computer are unreadable, so it '
        'cannot tell which gateways you use. Your brokers are not affected: '
        'nothing on them depends on Studio.',
    rows: [
      ErrorRowVm('Error', 'DatabaseException: invalid codec signature'),
      ErrorRowVm(
        'File',
        '~/Library/Application Support/uk.gencto.wyrmStudio/database.db',
      ),
      ErrorRowVm('Studio', '0.3.0 (macOS 15.1)'),
    ],
    note:
        'Fresh settings keep the unreadable file beside the new one as '
        'database.db.broken. You add your gateways and log in again.',
    noteCode: 'database.db.broken',
  ),
  onFresh: () {},
  onCopy: () {},
  onQuit: () {},
);
