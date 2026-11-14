import 'package:material_ui/material_ui.dart';
import 'package:ui/alerts/unlock_notice.dart';
import 'package:ui/containers/unlock_offer.dart';
import 'package:ui/containers/unlock_panel.dart';
import 'package:ui/indicators/biometric_icon.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/overlays/lock_overlay.dart';
import 'package:ui/overlays/security_dialog.dart';
import 'package:ui/overlays/step_up_dialog.dart';
import 'package:ui/pages/log_in_page.dart';
import 'package:ui/shell/wyrm_logo.dart';
import 'package:ui/theme/extensions/colors.dart';
import 'package:ui/theme/typography.dart';

// The data of the boards *Unlock…* (design canvas, row *Log in, part 2*),
// as the widgets' arguments. The words are the boards' (plant, olena).

void _none(Object? _) {}

FieldVm<String?> _field(String? v) => FieldVm(value: v, onChanged: _none);

const _version = 'Studio 1.0 · English';

/// The log-in page with [unlock] or [offer] in place of the form.
Widget _page({UnlockPanelVm? unlock, UnlockOfferVm? offer}) => LogInPage(
  gateway: _field('https://plant.local:8446'),
  user: _field('olena'),
  password: _field('correct-horse'),
  isWaiting: false,
  onPressedLogIn: () {},
  version: _version,
  unlock: unlock,
  reEnable: const FieldVm(value: true, onChanged: _none),
  onUnlock: () {},
  onUsePassword: () {},
  onAnotherAccount: () {},
  offer: offer,
);

const _account = UnlockAccountVm(
  initials: 'OL',
  user: 'olena',
  role: '· engineer on plant',
  host: 'plant.local:8446 + standby',
  last: 'Touch ID · 2 h ago',
);

UnlockPanelVm _panel({
  String title = 'Log in',
  String subtitle = 'to plant’s gateway.',
  UnlockNoticeVm? notice,
  bool password = true,
  String? reEnable = 'Turn Touch ID on again after I log in',
  String footer = 'TLS · certificate of the plant CA',
  BiometricGlyph glyph = BiometricGlyph.finger,
  String name = 'Touch ID',
  UnlockAccountVm account = _account,
}) => UnlockPanelVm(
  title: title,
  subtitle: subtitle,
  notice: notice,
  account: account,
  password: password,
  glyph: glyph,
  unlockLabel: 'Unlock with $name',
  note: 'Or press Enter',
  passwordLabel: 'Password for olena',
  reEnable: reEnable,
  usePassword: 'Use the password',
  another: 'Another account or gateway',
  footer: footer,
  version: _version,
);

/// Board `Unlock` (and the page under `UnlockPrompt`, `UnlockWindows`).
Widget unlock({String platform = 'mac'}) {
  final windows = platform == 'windows';
  final name = windows ? 'Windows Hello' : 'Touch ID';
  return _page(
    unlock: _panel(
      title: 'Welcome back',
      subtitle: 'Unlock to open the tree of plant.',
      password: false,
      glyph: windows ? BiometricGlyph.face : BiometricGlyph.finger,
      name: name,
      account: UnlockAccountVm(
        initials: 'OL',
        user: 'olena',
        role: '· engineer on plant',
        host: 'plant.local:8446 + standby',
        last: '$name · 2 h ago',
      ),
      footer: windows
          ? 'Key in this PC’s TPM · added 3 Nov'
          : 'Key in this Mac’s Secure Enclave · added 3 Nov',
    ),
  );
}

/// Board `UnlockOffer`.
Widget offer() => _page(
  offer: const UnlockOfferVm(
    checked: 'Logged in to plant as olena · engineer',
    glyph: BiometricGlyph.finger,
    title: 'Unlock with Touch ID next time?',
    text:
        'Instead of the password, Touch ID opens a key that proves to plant '
        'it is you on this Mac.',
    facts: [
      OfferFactVm(
        'One key for olena on plant, made inside this Mac’s Secure Enclave. '
        'It never leaves it; Studio never keeps your password.',
      ),
      OfferFactVm(
        'Works with plant and its standby edge.local. Other gateways ask for '
        'their own.',
      ),
      OfferFactVm(
        'It ends when the fingerprints here change, when your password '
        'changes, or when an administrator removes this device.',
        tone: Tone.warn,
      ),
      OfferFactVm(
        'plant asks for the password once every 30 days.',
        tone: Tone.neutral,
      ),
    ],
    policy:
        'plant allows it: biometric devices on, up to 5 per user '
        '(gateway.devices). You can turn it off in the account menu › '
        'Security.',
    use: 'Use Touch ID',
    notNow: 'Not now',
    dontAsk: 'Don’t ask on this computer',
  ),
);

/// Board `UnlockFallback`.
Widget fallback() => _page(
  unlock: _panel(
    notice: const UnlockNoticeVm(
      title: 'Touch ID did not match 3 times',
      text: 'Log in with the password. Touch ID stays on for the next time.',
    ),
    reEnable: null,
    footer: 'Key in this Mac’s Secure Enclave · added 3 Nov',
  ),
);

/// Board `UnlockChanged`.
Widget changed() => _page(
  unlock: _panel(
    notice: const UnlockNoticeVm(
      title: 'Touch ID was turned off for this account',
      text:
          'The fingerprints on this Mac changed, so the key Studio kept no '
          'longer opens. Someone with the new finger cannot sign in as you.',
    ),
  ),
);

/// Board `UnlockSignedOut` (removed by an administrator).
Widget signedOut() => _page(
  unlock: _panel(
    notice: const UnlockNoticeVm(
      title: 'Removed by an administrator',
      text:
          'An administrator removed this Mac from your devices. Log in with '
          'the password; you can turn Touch ID on again after.',
      tone: Tone.bad,
    ),
  ),
);

/// Board `UnlockLinux`.
Widget linux() => _page(
  unlock: _panel(
    notice: const UnlockNoticeVm(
      title: 'No biometric unlock on this computer',
      text:
          'Linux has no system prompt Studio can bind a key to, so this '
          'computer always asks for the password.',
      tone: Tone.neutral,
    ),
    reEnable: null,
    glyph: BiometricGlyph.key,
    name: 'biometrics',
    account: const UnlockAccountVm(
      initials: 'OL',
      user: 'olena',
      role: '· engineer on plant',
      host: 'plant.local:8446 + standby',
      last: 'password',
    ),
  ),
);

/// The system's own prompt over the page (boards `UnlockPrompt`,
/// `UnlockWindows`): drawn by the OS, never by Studio, so only here.
Widget prompt({String platform = 'mac'}) {
  final windows = platform == 'windows';
  return Stack(
    children: [
      Positioned.fill(child: unlock(platform: platform)),
      // The board dims the form panel only (the prompt sits in it).
      Positioned(
        top: 0,
        right: 0,
        bottom: 0,
        width: 520,
        child: ColoredBox(
          color: const Color.fromRGBO(8, 10, 11, 0.55),
          child: Center(child: _OsPrompt(windows: windows)),
        ),
      ),
    ],
  );
}

class _OsPrompt extends StatelessWidget {
  const _OsPrompt({required this.windows});

  final bool windows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = windows ? c.good : c.ember;
    return Container(
      width: 346,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        color: windows ? const Color(0xFF202020) : const Color(0xFF2A2D30),
        borderRadius: BorderRadius.circular(windows ? 8 : 14),
        border: Border.all(
          color: windows ? const Color(0xFF3A3A3A) : const Color(0xFF3E4246),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 60,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: .min,
        spacing: 12,
        children: [
          Text(
            (windows ? 'Windows Security' : 'Touch ID').toUpperCase(),
            style: TextStyle(fontSize: 11, letterSpacing: 0.66, color: c.text4),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
            ),
            alignment: .center,
            child: BiometricIcon(
              glyph: windows ? BiometricGlyph.face : BiometricGlyph.finger,
              size: 34,
              compact: true,
              color: accent,
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'WYRM Studio',
                  style: TextStyle(fontWeight: .w600, color: c.text1),
                ),
                const TextSpan(text: ' wants to sign in to '),
                TextSpan(
                  text: 'plant',
                  style: TextStyle(fontWeight: .w600, color: c.text1),
                ),
                const TextSpan(text: ' as '),
                TextSpan(
                  text: 'olena',
                  style: TextStyle(fontWeight: .w600, color: c.text1),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: .center,
            style: TextStyle(fontSize: 14, height: 1.45, color: c.text1),
          ),
          Text(
            windows
                ? 'Face, fingerprint or your Windows Hello PIN.'
                : 'Touch the sensor to allow this.',
            style: TextStyle(fontSize: 12, color: c.text3),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Container(
                    height: 32,
                    alignment: .center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: c.line3),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontSize: 13, color: c.text1),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 32,
                    alignment: .center,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      windows ? 'Simulate Hello' : 'Simulate a touch',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: .w600,
                        color: c.onEmber,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            'prototype: drawn by the system, not by Studio',
            style: TextStyle(fontSize: 11, color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// The Studio shell behind the in-app boards, simplified as the boards
/// draw it (header, tree, the values of ahu1).
class _Shell extends StatelessWidget {
  const _Shell();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const tree = [
      ('plant', 16.0, '▾', 1),
      ('downstream', 30.0, '▾', 0),
      ('modbus', 44.0, '▾', 0),
      ('tcp-line2', 58.0, '▾', 0),
      ('ahu1', 72.0, '', 2),
      ('ahu-old', 72.0, '', 0),
      ('s7', 44.0, '▸', 0),
      ('bacnet', 44.0, '▸', 0),
      ('dataflows', 30.0, '▸', 0),
      ('storage', 30.0, '▸', 0),
    ];
    final vals = [
      ('supply_temp', '21.6 °C', c.good),
      ('return_temp', '24.1 °C', c.text1),
      ('fan_speed', '62 %', c.text1),
      ('valve_pos', '38 %', c.text1),
      ('filter_dp', '112 Pa', c.text1),
      ('alarm', 'false', c.text4),
    ];
    return ColoredBox(
      color: c.ground0,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 14,
          color: c.text1,
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.ground3)),
              ),
              child: Row(
                spacing: 18,
                children: [
                  const WyrmLogo(showStudio: false),
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.line2),
                    ),
                    alignment: .center,
                    child: const Text(
                      'plant via edge · central',
                      style: TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
                    ),
                  ),
                  for (final t in const [
                    'Explorer',
                    'Links',
                    'Flows',
                    'History',
                    'Access',
                    'Sites',
                    'Assistant',
                    'System',
                  ])
                    Text(
                      t,
                      style: TextStyle(
                        fontSize: 13,
                        color: t == 'Explorer' ? c.text1 : c.text3,
                      ),
                    ),
                  const Spacer(),
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: c.emberTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: .center,
                    child: Text(
                      'Review and apply · 3',
                      style: TextStyle(fontSize: 13, color: c.emberSoft),
                    ),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c.emberTint,
                      shape: BoxShape.circle,
                    ),
                    alignment: .center,
                    child: Text(
                      'OL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: .w600,
                        color: c.emberSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: .stretch,
                children: [
                  Container(
                    width: 340,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: c.ground3)),
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      spacing: 2,
                      children: [
                        for (final (n, pad, chev, kind) in tree)
                          Container(
                            color: kind == 2 ? c.emberFill : null,
                            padding: EdgeInsets.fromLTRB(pad, 6, 16, 6),
                            child: Row(
                              spacing: 8,
                              children: [
                                SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: chev.isEmpty
                                      ? null
                                      : CustomPaint(
                                          painter: _Chevron(
                                            c.muted,
                                            open: chev == '▾',
                                          ),
                                        ),
                                ),
                                Text(
                                  n,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: kind == 2 ? c.text1 : c.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 22,
                      ),
                      child: Column(
                        crossAxisAlignment: .stretch,
                        spacing: 10,
                        children: [
                          Text(
                            'wy/plant/downstream/modbus/tcp-line2/ahu1',
                            style: TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 12,
                              color: c.text4,
                            ),
                          ),
                          const Text(
                            'ahu1',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: .w600,
                            ),
                          ),
                          for (final (n, v, ink) in vals)
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: c.ground1,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: c.ground3),
                              ),
                              child: Row(
                                children: [
                                  Expanded(child: Text(n)),
                                  Text(
                                    v,
                                    style: TextStyle(
                                      fontFamily: AppFonts.mono,
                                      color: ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Board `UnlockLock`: the shell under the idle lock.
Widget lock() => const LockOverlay(
  card: LockCardVm(
    title: 'Studio is locked',
    text:
        'olena on plant · locked after 15 min without use. Values and the '
        'tree stay hidden; links, flows and the session keep running.',
    glyph: BiometricGlyph.finger,
    unlockLabel: 'Unlock with Touch ID',
    kept: '3 changes are waiting in Review and apply; they are kept.',
    usePassword: 'Use the password',
    logOut: 'Log out',
    passwordLabel: 'Password for olena',
    unlock: 'Unlock',
  ),
  onUnlock: _unlock,
  child: _Shell(),
);

void _unlock() {}

Widget _over(Widget dialog) => Stack(
  children: [
    const Positioned.fill(child: _Shell()),
    Positioned.fill(
      child: ColoredBox(
        color: StepUpDialog.barrier,
        child: Center(child: dialog),
      ),
    ),
  ],
);

/// Board `UnlockStepUp`.
Widget stepUp() => _over(
  StepUpDialog(
    vm: const StepUpDialogVm(
      title: 'Confirm it is you',
      lead:
          'Apply 3 changes on plant. Two of them are config, and plant asks '
          'for a fresh confirmation before config changes.',
      lines: [
        StepUpLineVm(
          level: 'config',
          text: 'add_device ahu2',
          key: 'tcp-line2',
        ),
        StepUpLineVm(
          level: 'config',
          text: 'add_watch_path supply_temp',
          key: 'sys/history/1min',
        ),
        StepUpLineVm(
          level: 'write',
          text: 'set fan_speed = 70 %',
          key: 'ahu1/fan_speed',
        ),
      ],
      glyph: BiometricGlyph.finger,
      device:
          'Touch ID signs this one request: plant gets a proof bound to these '
          '3 changes, and stays confirmed on this Mac for 5 minutes.',
      confirm: 'Confirm with Touch ID',
      usePassword: 'Use the password',
      cancel: 'Cancel',
      passwordLabel: 'Password for olena',
    ),
    onDevice: () {},
    onPassword: _none,
    onCancel: () {},
  ),
);

/// Board `UnlockApp` (Account › Security).
Widget security() => _over(
  SecurityDialog(
    vm: const SecurityDialogVm(
      title: 'Security',
      subtitle: 'olena · plant',
      onThis: 'On this Mac',
      unlockTitle: 'Unlock with Touch ID',
      unlockText:
          'A key in this Mac’s Secure Enclave, added 3 Nov. Off removes the '
          'key here and this Mac from your devices.',
      unlockOn: true,
      lockTitle: 'Lock Studio after',
      lockText:
          'Hides the tree and values; the session and Review and apply are '
          'kept. plant allows at most 30 min.',
      lockAfter: 15,
      lockChoices: [(0, 'Off'), (5, '5 min'), (15, '15 min'), (30, '30 min')],
      confirmTitle: 'Confirm before config changes',
      confirmText:
          'Set by plant (gateway.devices.step_up: config); you cannot turn it '
          'off here.',
      confirmOn: true,
      devicesTitle: 'Your devices on plant',
      devices: [
        SecurityDeviceVm(
          id: 'd1',
          os: 'mac',
          name: 'MacBook Pro · Studio',
          tag: 'this device',
          tagTone: Tone.good,
          detail: 'Touch ID · used now · added 3 Nov',
          action: 'Turn off',
          own: true,
        ),
        SecurityDeviceVm(
          id: 'd2',
          os: 'iOS',
          name: 'iPhone 15 · Studio',
          detail: 'Face ID · 2 days ago · added 28 Oct',
          action: 'Remove',
        ),
        SecurityDeviceVm(
          id: 'd3',
          os: 'win',
          name: 'ENG-LAPTOP-07 · Studio',
          tag: 'password due in 4 days',
          tagTone: Tone.warn,
          detail: 'Windows Hello · 26 days ago',
          action: 'Remove',
        ),
        SecurityDeviceVm(
          id: 'd4',
          os: 'and',
          name: 'Pixel 8 · Studio',
          tag: 'removed by ivan',
          tagTone: Tone.bad,
          detail:
              'fingerprint · removed 12 Nov · signs in with the password only',
          action: 'Forget',
        ),
      ],
      policy:
          'plant’s policy: devices on · up to 5 · password every 30 days · '
          'confirm config changes. An administrator sees and removes devices '
          'in Access › Users.',
      signOut: 'Sign out everywhere',
    ),
    onUnlock: _none,
    onPassword: _none,
    onLockAfter: _none,
    onDevice: _none,
    onSignOut: () {},
    onClose: () {},
  ),
);

/// Board `UnlockPlatforms`: the unlock on an iPhone and an Android phone
/// (Studio's account card, the system's sheet drawn as the board does) and
/// the matrix of the platforms.
Widget platforms() => const _Platforms();

class _Platforms extends StatelessWidget {
  const _Platforms();

  static const _rows = [
    (
      'macOS',
      'Touch ID',
      'P-256 key in the Secure Enclave, access control biometryCurrentSet; '
          'LocalAuthentication prompt. Apple Watch unlock is not offered (it '
          'is not biometric).',
      'Password of the gateway. Ends when fingerprints are added or removed.',
    ),
    (
      'Windows',
      'Windows Hello',
      'Key in the TPM through Windows Hello (KeyCredentialManager); face, '
          'fingerprint or the Hello PIN, as the PC is set up.',
      'Password of the gateway. Ends when Hello is reset or the PC leaves the '
          'account.',
    ),
    (
      'iOS · iPadOS',
      'Face ID / Touch ID',
      'Secure Enclave key, biometryCurrentSet; NSFaceIDUsageDescription text.',
      'Password of the gateway (never the iPhone passcode by default). Ends '
          'when faces or fingers change.',
    ),
    (
      'Android',
      'Fingerprint / face',
      'Android Keystore key (StrongBox when there is one), BIOMETRIC_STRONG, '
          'setInvalidatedByBiometricEnrollment. A face unlock of class 2 '
          'cannot open a key, so it is not offered.',
      'Password of the gateway; the screen PIN only if plant allows it '
          '(allow_device_credential). Ends on a new enrollment.',
    ),
    (
      'Linux',
      '— not offered',
      'No system prompt can bind a key (fprintd has no key store). Studio '
          'remembers the gateway and the user only.',
      'Password each time; the idle lock asks for the password too.',
    ),
    (
      'Kiosk · web',
      '— not offered',
      'Kiosk sessions are a gateway token for one view (no person). A future '
          'web build uses passkeys (WebAuthn), the same server side.',
      '—',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(String t, {double w = 0, Color? ink, bool strong = false}) {
      final text = Text(
        t,
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: ink ?? c.text2,
          fontWeight: strong ? .w600 : .w400,
        ),
      );
      return Padding(padding: const EdgeInsets.all(12), child: text);
    }

    return ColoredBox(
      color: c.ground0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        child: Row(
          crossAxisAlignment: .start,
          spacing: 40,
          children: [
            const _Phone(
              title: 'Face ID',
              hint: 'Look at the iPhone',
              caption: 'iPhone · Face ID (Touch ID on older ones)',
              glyph: BiometricGlyph.face,
              teal: false,
              radius: BorderRadius.all(Radius.circular(22)),
              sheet: Color(0xFF2A2D30),
            ),
            const _Phone(
              title: 'Unlock WYRM Studio',
              hint: 'Touch the fingerprint sensor',
              caption: 'Android · BiometricPrompt, strong class only',
              glyph: BiometricGlyph.finger,
              teal: true,
              radius: BorderRadius.vertical(
                top: Radius.circular(26),
                bottom: Radius.circular(18),
              ),
              sheet: Color(0xFF1F2326),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 16,
                children: [
                  Text(
                    'Biometric unlock on every platform',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.ground3),
                    ),
                    child: Table(
                      columnWidths: const {
                        0: FixedColumnWidth(104),
                        1: FixedColumnWidth(136),
                        2: FlexColumnWidth(1.25),
                        3: FlexColumnWidth(),
                      },
                      border: TableBorder(
                        horizontalInside: BorderSide(color: c.ground3),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: c.ground1),
                          children: [
                            for (final h in const [
                              'PLATFORM',
                              'CALLED IN STUDIO',
                              'KEY AND PROMPT',
                              'FALLS BACK TO / ENDS WHEN',
                            ])
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Text(
                                  h,
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 0.6,
                                    color: c.text4,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        for (final (p, n, k, f) in _rows)
                          TableRow(
                            children: [
                              cell(p, ink: c.text1, strong: true),
                              cell(
                                n,
                                ink: n.startsWith('—') ? c.muted : c.emberSoft,
                              ),
                              cell(k),
                              cell(f, ink: c.text3),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone({
    required this.title,
    required this.hint,
    required this.caption,
    required this.glyph,
    required this.teal,
    required this.radius,
    required this.sheet,
  });

  final String title;
  final String hint;
  final String caption;
  final BiometricGlyph glyph;
  final bool teal;
  final BorderRadius radius;
  final Color sheet;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = teal ? c.good : c.ember;
    return Column(
      spacing: 10,
      children: [
        Container(
          width: 300,
          height: 640,
          padding: const EdgeInsets.fromLTRB(22, 56, 22, 22),
          decoration: BoxDecoration(
            color: c.ground0,
            borderRadius: BorderRadius.circular(42),
            border: Border.all(color: c.ground3, width: 8),
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 18,
            children: [
              const Align(
                alignment: .centerLeft,
                child: WyrmLogo(showStudio: false),
              ),
              Text(
                'Welcome back',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: .w600,
                  color: c.text1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.ground1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.line1),
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c.emberTint,
                        shape: BoxShape.circle,
                      ),
                      alignment: .center,
                      child: Text(
                        'OL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: .w600,
                          color: c.emberSoft,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        Text(
                          'olena · engineer',
                          style: TextStyle(fontSize: 13, color: c.text1),
                        ),
                        Text(
                          'plant.local:8446',
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: c.text4,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: sheet, borderRadius: radius),
                child: Column(
                  spacing: 12,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: .w600,
                        color: c.text1,
                      ),
                    ),
                    Text(
                      'Sign in to plant as olena',
                      style: TextStyle(fontSize: 12, color: c.text3),
                    ),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 2),
                      ),
                      alignment: .center,
                      child: BiometricIcon(
                        glyph: glyph,
                        size: 32,
                        compact: true,
                        color: accent,
                      ),
                    ),
                    Text(hint, style: TextStyle(fontSize: 12, color: c.text4)),
                    Text(
                      'Use the password',
                      style: TextStyle(fontSize: 13, color: accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Text(caption, style: TextStyle(fontSize: 13, color: c.text3)),
      ],
    );
  }
}

/// The tree's ▾ / ▸ of the board (the bundled fonts have no such glyph).
class _Chevron extends CustomPainter {
  _Chevron(this.color, {required this.open});

  final Color color;
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final path = open
        ? (Path()
            ..moveTo(0, w * .25)
            ..lineTo(w, w * .25)
            ..lineTo(w / 2, w * .8))
        : (Path()
            ..moveTo(w * .25, 0)
            ..lineTo(w * .8, w / 2)
            ..lineTo(w * .25, w));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Chevron old) => old.color != color || old.open != open;
}
