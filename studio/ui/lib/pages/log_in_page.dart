import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../alerts/trust_card.dart';
import '../alerts/unreachable_alert.dart';
import '../buttons/find_network_button.dart';
import '../buttons/log_in_button.dart';
import '../buttons/recent_chip.dart';
import '../containers/discover_panel.dart';
import '../containers/login_hero.dart';
import '../containers/rise.dart';
import '../containers/shake.dart';
import '../containers/unlock_offer.dart';
import '../containers/unlock_panel.dart';
import '../containers/welcome_panel.dart';
import '../forms/base_form.dart';
import '../indicators/arc_spinner.dart';
import '../indicators/login_steps.dart';
import '../indicators/status_dot.dart';
import '../inputs/boxed_form_field.dart';
import '../inputs/check_row.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../shell/window_bar.dart';
import '../theme/extensions/colors.dart';
import '../theme/motion.dart';
import '../theme/typography.dart';

/// Log in to a WYRM user gateway: its URL, the user and the password
/// (docs/design/specs/login.md, boards `Login`, `LoginSigning`, `LoginWrong`,
/// `LoginUnreachable`, `LoginWelcome`).
///
/// The living hero on the left, the form on the right (stacked below 1080 px
/// wide). A gateway has users made by an administrator, so there is no
/// registration and no password reset here (docs/studio.md, phase 1).
class LogInPage extends StatefulWidget {
  const LogInPage({
    required this.gateway,
    required this.user,
    required this.password,
    required this.isWaiting,
    required this.onPressedLogIn,
    required this.version,
    this.standby,
    this.gatewayTone = Tone.neutral,
    this.gatewayNote,
    this.checking = false,
    this.onGatewayLeave,
    this.recent = const [],
    this.onRecent,
    this.remember,
    this.steps = const [],
    this.step = 0,
    this.wrong = false,
    this.unreachable,
    this.onRetry,
    this.onUseStandby,
    this.tls,
    this.standbyLabel,
    this.welcome,
    this.window = const WindowBarVm(),
    this.gatewayHint,
    this.onFind,
    this.discover,
    this.onLookAgain,
    this.onPick,
    this.onProbe,
    this.onOpenSettings,
    this.trust,
    this.onTrust,
    this.onCancelTrust,
    this.offer,
    this.onOfferUse,
    this.onOfferNotNow,
    this.onOfferDontAsk,
    this.unlock,
    this.reEnable,
    this.onUnlock,
    this.onAutoUnlock,
    this.onUsePassword,
    this.onAnotherAccount,
    this.tlsTone = Tone.good,
    super.key,
  });

  /// The main gateway URL (the first of the comma list).
  final FieldVm<String?> gateway;
  final FieldVm<String?> user;
  final FieldVm<String?> password;

  /// A log-in is in flight: the button is busy and the steps show.
  final bool isWaiting;
  final VoidCallback onPressedLogIn;

  /// `Studio <version> · <language>` at the footer's right, resolved. The
  /// board has no language or theme switchers on this page (owner decision
  /// 2026-11-08, docs/design/specs/login.md §3.8).
  final String version;

  /// The standby gateway URL (the second of the comma list); null hides
  /// `Add a standby gateway`.
  final FieldVm<String?>? standby;

  /// The gateway's last probe: good (answered), bad (no answer), neutral.
  final Tone gatewayTone;

  /// `<host> · answered in <n> ms` or `No answer from <host>`, resolved.
  final String? gatewayNote;

  /// The gateway is being probed: the spinner in the field.
  final bool checking;

  /// The gateway field lost the focus: probe it.
  final VoidCallback? onGatewayLeave;

  /// The recent gateways, newest first.
  final List<RecentChipVm> recent;

  /// A recent chip was tapped: its [RecentChipVm.id].
  final ValueChanged<String>? onRecent;

  /// `Remember the gateway and user on this computer`.
  final FieldVm<bool>? remember;

  /// The three steps of a log-in, resolved; shown while [isWaiting].
  final List<String> steps;

  /// The running step, 0-based.
  final int step;

  /// The gateway refused the user or the password: the password's border,
  /// the shake, the message and the focus back in the password.
  final bool wrong;

  /// The gateway did not answer: the alert above the form.
  final UnreachableAlertVm? unreachable;
  final VoidCallback? onRetry;
  final VoidCallback? onUseStandby;

  /// `TLS · certificate of the <site> CA` for an `https` gateway, resolved.
  final String? tls;

  /// `Standby: <host:port>` once one is set; null shows
  /// `Add a standby gateway`.
  final String? standbyLabel;

  /// Logged in, the tree is opening: the welcome in place of the form.
  final WelcomePanelVm? welcome;

  /// The frameless window's side of the page: its top 40 px (the hero's
  /// top padding) are the window's drag area (docs/studio.md §7.1).
  final WindowBarVm window;

  /// The gateway field's placeholder.
  final String? gatewayHint;

  /// `Find on this network` beside the gateway field toggles the panel
  /// (docs/design/specs/unlock-discover.md §4); null hides the button.
  final VoidCallback? onFind;

  /// The panel of found gateways, in place of the recent chips; null while
  /// it is closed.
  final DiscoverPanelVm? discover;
  final VoidCallback? onLookAgain;

  /// A found row was picked: its site.
  final ValueChanged<String>? onPick;
  final VoidCallback? onProbe;
  final VoidCallback? onOpenSettings;

  /// The certificate check of a found gateway, in place of the panel; the
  /// form below is dimmed until it is answered.
  final TrustCardVm? trust;
  final VoidCallback? onTrust;
  final VoidCallback? onCancelTrust;

  /// The lock of the footer's TLS line: good, or warn while the CA is not
  /// trusted yet.
  final Tone tlsTone;

  /// After a password login: `Unlock with <name> next time?` (board
  /// `UnlockOffer`) in place of the form, before the welcome.
  final UnlockOfferVm? offer;
  final VoidCallback? onOfferUse;
  final VoidCallback? onOfferNotNow;
  final VoidCallback? onOfferDontAsk;

  /// A device key is in play (boards `Unlock`, `UnlockFallback`,
  /// `UnlockChanged`, `UnlockSignedOut`, `UnlockLinux`): the account form
  /// in place of the fields. Its password is [password].
  final UnlockPanelVm? unlock;
  final FieldVm<bool>? reEnable;

  /// The round button and Enter; null while the key cannot be tried.
  final VoidCallback? onUnlock;

  /// The page's own prompt, once, when the window has or gets the focus
  /// (unlock-discover.md §2); the business side makes it once.
  final VoidCallback? onAutoUnlock;
  final VoidCallback? onUsePassword;
  final VoidCallback? onAnotherAccount;

  @override
  State<LogInPage> createState() => _LogInPageState();
}

class _LogInPageState extends State<LogInPage> {
  final _passwordFocus = FocusNode();
  var _standbyOpen = false;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // The window gets the focus: the one prompt the page opens by itself.
    _lifecycle = AppLifecycleListener(onResume: _auto);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) {
        _auto();
      }
    });
  }

  void _auto() {
    final u = widget.unlock;
    if (mounted && u != null && !u.password && widget.onUnlock != null) {
      widget.onAutoUnlock?.call();
    }
  }

  @override
  void didUpdateWidget(LogInPage old) {
    super.didUpdateWidget(old);
    // The unlock form came after the page opened (the device record is
    // read after the first frame).
    if (widget.unlock != null && old.unlock == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = WidgetsBinding.instance.lifecycleState;
        if (state == null || state == AppLifecycleState.resumed) {
          _auto();
        }
      });
    }
    // Focus back in the password once the refused log-in is over: while it
    // runs the field is disabled and cannot take the focus.
    final settled = widget.wrong && !widget.isWaiting;
    if (settled && !(old.wrong && !old.isWaiting)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _passwordFocus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.ground0,
      // The board's type: Plex Sans 14 in `text1` at the font's own line
      // height (CSS `normal`), not the theme's body style.
      body: DefaultTextStyle(
        style: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 14,
          color: c.text1,
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _body(context)),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 40,
              child: WindowBar(
                vm: widget.window,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The hero beside the form, or above it below 1080 px.
  Widget _body(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth >= 1080) {
        return Row(
          crossAxisAlignment: .stretch,
          children: [
            Expanded(
              child: LoginHero(underButtons: widget.window.leading > 0),
            ),
            // The boards *Discover…* give the form 40 more while the panel
            // or the trust card is open (560, content 460).
            SizedBox(width: _finding ? 560 : 520, child: _panel(context)),
          ],
        );
      }
      final small = box.maxWidth < 700;
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            SizedBox(
              // Under the window buttons the logo starts lower: the hero
              // grows by as much, so its text keeps its room.
              height: small
                  ? 220
                  : widget.window.leading > 0
                  ? 420 + LoginHero.buttonsClearance
                  : 420,
              child: LoginHero(
                size: small ? LoginHeroSize.small : LoginHeroSize.stacked,
                underButtons: widget.window.leading > 0,
              ),
            ),
            _form(context),
          ],
        ),
      );
    },
  );

  /// The form panel: padding 40 × 32, the content centred, at most 420 wide.
  Widget _panel(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: Center(child: _form(context)),
      ),
    ),
  );

  Widget _form(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _finding ? 460 : 420),
        child: AnimatedSwitcher(
          duration: reduceMotion(context) ? .zero : Motion.fadeOut,
          child: switch ((widget.welcome, widget.offer, widget.unlock)) {
            (final vm?, _, _) => Rise(
              key: const ValueKey('welcome'),
              child: WelcomePanel(vm: vm),
            ),
            (null, final offer?, _) => KeyedSubtree(
              key: const ValueKey('offer'),
              child: UnlockOffer(
                vm: offer,
                onUse: widget.onOfferUse ?? () {},
                onNotNow: widget.onOfferNotNow ?? () {},
                onDontAsk: widget.onOfferDontAsk ?? () {},
              ),
            ),
            (null, null, final unlock?) => KeyedSubtree(
              key: const ValueKey('unlock'),
              child: UnlockPanel(
                vm: unlock,
                passwordField: widget.password,
                reEnableField: widget.reEnable,
                onUnlock: widget.onUnlock,
                onLogIn: widget.onPressedLogIn,
                onAnother: widget.onAnotherAccount ?? () {},
                onUsePassword: widget.onUsePassword,
                busy: widget.isWaiting,
                wrong: widget.wrong,
                unreachable: widget.unreachable,
                onRetry: widget.onRetry,
                onUseStandby: widget.onUseStandby,
              ),
            ),
            _ => KeyedSubtree(
              key: const ValueKey('form'),
              child: _fields(context),
            ),
          },
        ),
      ),
    ),
  );

  Widget _fields(BuildContext context) {
    final c = context.colors;
    final busy = widget.isWaiting;
    return BaseForm(
      builder: (context, form) {
        void submit() {
          if (!busy && form.validateAndSave()) {
            widget.onPressedLogIn();
          }
        }

        return Column(
          crossAxisAlignment: .stretch,
          spacing: 22,
          children: [
            Rise(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 6,
                children: [
                  Text(
                    S.current.logIn,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: .w600,
                      letterSpacing: -.26,
                      color: c.text1,
                    ),
                  ),
                  Text(
                    S.current.logInLead,
                    style: TextStyle(fontSize: 14, color: c.text3),
                  ),
                ],
              ),
            ),
            if (widget.unreachable case final alert?)
              Rise(
                child: UnreachableAlert(
                  vm: alert,
                  onRetry: widget.onRetry ?? submit,
                  onStandby: widget.onUseStandby,
                ),
              ),
            Column(
              crossAxisAlignment: .stretch,
              spacing: 16,
              children: [
                Rise(order: 1, child: _gateway(context)),
                if (_finding)
                  Rise(
                    order: 2,
                    child: Opacity(
                      opacity: widget.trust == null ? 1 : .4,
                      child: Column(
                        crossAxisAlignment: .stretch,
                        spacing: 16,
                        children: [
                          // While the panel is open the form is the
                          // board's compact one: user and password side by
                          // side, Remember out of the way.
                          Row(
                            crossAxisAlignment: .start,
                            spacing: 12,
                            children: [
                              Expanded(child: _user()),
                              Expanded(child: _password(submit)),
                            ],
                          ),
                          LogInButton(onPressed: submit, busy: busy),
                          if (busy && widget.steps.isNotEmpty)
                            LoginSteps(
                              steps: widget.steps,
                              current: widget.step,
                            ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Rise(order: 2, child: _user()),
                  Rise(order: 3, child: _password(submit)),
                  if (widget.remember case final remember?)
                    Rise(
                      order: 4,
                      child: CheckRow(
                        vm: remember,
                        label: S.current.rememberGatewayAndUser,
                      ),
                    ),
                  Rise(
                    order: 4,
                    child: LogInButton(onPressed: submit, busy: busy),
                  ),
                  if (busy && widget.steps.isNotEmpty)
                    LoginSteps(steps: widget.steps, current: widget.step),
                ],
              ],
            ),
            Rise(order: 4, child: _footer(context)),
          ],
        );
      },
    );
  }

  /// The panel or the trust card is open.
  bool get _finding => widget.discover != null || widget.trust != null;

  Widget _user() => BoxedFormField(
    vm: widget.user,
    label: S.current.user,
    autofillHints: const [AutofillHints.username],
    textInputAction: .next,
  );

  Widget _password(VoidCallback submit) => Shake(
    trigger: widget.wrong ? true : null,
    child: BoxedFormField(
      vm: widget.password,
      label: S.current.password,
      obscure: true,
      alert: widget.wrong,
      focusNode: _passwordFocus,
      keyboardType: .visiblePassword,
      autofillHints: const [AutofillHints.password],
      textInputAction: .done,
      onSubmitted: (_) => submit(),
    ),
  );

  Widget _gateway(BuildContext context) {
    final c = context.colors;
    final dot = switch (widget.gatewayTone) {
      .good => c.good,
      .bad => c.bad,
      .warn => c.warn,
      _ => c.muted,
    };
    final bad = widget.gatewayTone == .bad;
    final warn = widget.gatewayTone == .warn;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        BoxedFormField(
          vm: widget.gateway,
          label: S.current.gateway,
          mono: true,
          alert: widget.unreachable != null,
          keyboardType: .url,
          autofillHints: const [AutofillHints.url],
          textInputAction: .next,
          onLeave: widget.onGatewayLeave,
          hint: widget.gatewayHint,
          border: warn ? TrustCard.border : null,
          leading: StatusDot(
            color: dot,
            halo: widget.gatewayTone == .neutral ? 0 : 4,
          ),
          beside: widget.onFind == null
              ? null
              : FindNetworkButton(
                  onPressed: widget.onFind,
                  open: widget.discover != null,
                ),
          trailing: widget.checking
              ? ArcSpinner(
                  color: c.text4,
                  label: S.current.checkingGateway,
                )
              : null,
        ),
        if (widget.gatewayNote case final note?)
          Text(
            note,
            style: TextStyle(fontSize: 12, color: bad ? c.badText : c.text4),
          ),
        if (widget.trust case final t?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TrustCard(
              vm: t,
              onTrust: widget.onTrust ?? () {},
              onCancel: widget.onCancelTrust ?? () {},
            ),
          )
        else if (widget.discover case final d?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DiscoverPanel(
              vm: d,
              onLookAgain: widget.onLookAgain ?? () {},
              onPick: widget.onPick ?? (_) {},
              onProbe: widget.onProbe ?? () {},
              onOpenSettings: widget.onOpenSettings,
            ),
          )
        else if (widget.recent.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in widget.recent)
                RecentChip(
                  vm: r,
                  onTap: widget.onRecent == null
                      ? null
                      : () => widget.onRecent!(r.id),
                ),
            ],
          ),
        if (_standbyOpen && widget.standby != null)
          BoxedFormField(
            vm: widget.standby!,
            label: S.current.standbyGateway,
            mono: true,
            keyboardType: .url,
            onLeave: widget.onGatewayLeave,
            leading: StatusDot(color: c.muted, halo: 4),
          ),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final c = context.colors;
    final note = TextStyle(fontSize: 12, color: c.text4);
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.ground3)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: .center,
            children: [
              if (widget.tls case final tls?)
                Row(
                  mainAxisSize: .min,
                  spacing: 6,
                  children: [
                    CustomPaint(
                      size: const Size.square(13),
                      painter: _Lock(
                        widget.tlsTone == .warn ? c.warn : c.good,
                      ),
                    ),
                    Text(tls, style: note),
                  ],
                ),
              if (widget.standby != null)
                InkWell(
                  onTap: () => setState(() => _standbyOpen = !_standbyOpen),
                  child: Text(
                    widget.standbyLabel ?? S.current.addStandby,
                    style: note.copyWith(
                      color: c.text2,
                      decoration: .underline,
                      decorationColor: c.text2,
                    ),
                  ),
                ),
            ],
          ),
          Align(
            alignment: .centerRight,
            child: Text(widget.version, style: note),
          ),
        ],
      ),
    );
  }
}

/// The board's lock: `M6 11h12v9H6z M8 11V7a4 4 0 0 1 8 0v4`, stroke 2.
class _Lock extends CustomPainter {
  _Lock(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas
      ..save()
      ..scale(k)
      ..drawPath(
        Path()
          ..addRect(const Rect.fromLTWH(6, 11, 12, 9))
          ..moveTo(8, 11)
          ..lineTo(8, 7)
          ..arcToPoint(const Offset(16, 7), radius: const Radius.circular(4))
          ..lineTo(16, 11),
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = 2
          ..strokeCap = .round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_Lock old) => old.color != color;
}
