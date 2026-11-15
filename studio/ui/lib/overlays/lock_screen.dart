import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/unlock_method.dart';
import 'lock_overlay.dart';

/// Why the lock is still on after a try.
sealed class LockProblem extends Equatable {
  const LockProblem();

  /// The gateway refused the password.
  const factory LockProblem.wrongPassword() = LockWrongPassword;

  /// Another refusal, in the gateway's words.
  const factory LockProblem.said(String text) = LockSaid;

  String get text => switch (this) {
    LockWrongPassword() => S.current.lockWrongPassword,
    LockSaid(:final text) => text,
  };
}

final class LockWrongPassword extends LockProblem {
  const LockWrongPassword();
  @override
  List<Object?> get props => const [];
}

final class LockSaid extends LockProblem {
  const LockSaid(this.text);
  @override
  final String text;
  @override
  List<Object?> get props => [text];
}

/// The idle lock as typed values (ADR 0050 §1.4, board `UnlockLock`).
final class LockScreenVm extends Equatable {
  const LockScreenVm({
    required this.user,
    required this.site,
    required this.lockAfter,
    required this.method,
    this.kept = 0,
    this.problem,
    this.checking = false,
    this.passwordOnly = false,
  });

  final String user;
  final String site;

  /// The idle minutes it locked after.
  final int lockAfter;
  final UnlockMethod method;

  /// The changes waiting in *Review and apply*.
  final int kept;
  final LockProblem? problem;

  /// The key or the password is being checked.
  final bool checking;

  /// No key here (or it stopped working): the password at once.
  final bool passwordOnly;

  @override
  List<Object?> get props => [
    user,
    site,
    lockAfter,
    method,
    kept,
    problem,
    checking,
    passwordOnly,
  ];
}

/// The idle lock over [child] from typed values: it words them and draws
/// them with [LockOverlay]; null [vm] is a Studio that is not locked.
class LockScreen extends StatelessWidget {
  const LockScreen({
    required this.child,
    this.vm,
    this.onUnlock,
    this.onPassword,
    this.onLogOut,
    this.onActivity,
    super.key,
  });

  final Widget child;
  final LockScreenVm? vm;

  /// The key; null when there is none.
  final VoidCallback? onUnlock;
  final ValueChanged<String>? onPassword;
  final VoidCallback? onLogOut;
  final VoidCallback? onActivity;

  @override
  Widget build(BuildContext context) => LockOverlay(
    card: switch (vm) {
      final v? => _card(v),
      null => null,
    },
    onUnlock: onUnlock,
    onPassword: onPassword,
    onLogOut: onLogOut,
    onActivity: onActivity,
    child: child,
  );

  static LockCardVm _card(LockScreenVm v) {
    final s = S.current;
    return LockCardVm(
      title: s.lockTitle,
      text: s.lockText(v.user, v.site, v.lockAfter),
      glyph: v.method.glyph,
      unlockLabel: s.unlockWith(v.method.label),
      kept: v.kept == 0 ? null : s.lockKept(v.kept),
      usePassword: s.unlockUsePassword,
      logOut: s.logOut,
      passwordLabel: s.unlockPasswordFor(v.user),
      unlock: s.lockUnlock,
      error: v.problem?.text,
      checking: v.checking,
      passwordOnly: v.passwordOnly,
    );
  }
}
