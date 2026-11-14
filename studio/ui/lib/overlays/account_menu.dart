import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/language_switcher.dart';
import '../buttons/theme_switcher.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What the account menu shows: who is logged in, the language and the
/// theme in use.
final class AccountMenuVm extends Equatable {
  const AccountMenuVm({
    required this.user,
    required this.role,
    required this.locale,
    required this.theme,
  });

  final String user;
  final String role;

  /// The language code in use (`en`, `uk`).
  final String locale;
  final ThemeMode theme;

  @override
  List<Object?> get props => [user, role, locale, theme];
}

/// The account menu of the top bar's avatar (owner decision 2026-11-09):
/// the node menu's frame (300 wide, radius 10, `ground2`, `line3`), the
/// user and the role at the top, then `Language` (the endonyms) and
/// `Theme` (moon, sun), then `Log out`. A language or a theme picked
/// applies at once and the menu stays open, showing it; `Log out` closes it.
class AccountMenu extends StatefulWidget {
  const AccountMenu({
    required this.vm,
    required this.onLanguage,
    required this.onTheme,
    required this.onLogOut,
    this.onSecurity,
    super.key,
  });

  final AccountMenuVm vm;
  final ValueChanged<String> onLanguage;
  final ValueChanged<ThemeMode> onTheme;
  final VoidCallback onLogOut;

  /// `Security` (ADR 0050, board `UnlockApp`): above `Log out`; null hides
  /// it.
  final VoidCallback? onSecurity;

  /// Opens the menu under the avatar whose bottom right corner is [at]
  /// (global).
  static Future<void> show(
    BuildContext context, {
    required Offset at,
    required AccountMenuVm vm,
    required ValueChanged<String> onLanguage,
    required ValueChanged<ThemeMode> onTheme,
    required VoidCallback onLogOut,
    VoidCallback? onSecurity,
  }) => showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      return Stack(
        children: [
          Positioned(
            left: (at.dx - 300).clamp(8, size.width - 308),
            top: at.dy + 6,
            child: AccountMenu(
              vm: vm,
              onLanguage: onLanguage,
              onTheme: onTheme,
              onLogOut: () {
                Navigator.of(context).pop();
                onLogOut();
              },
              onSecurity: onSecurity == null
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      onSecurity();
                    },
            ),
          ),
        ],
      );
    },
  );

  @override
  State<AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends State<AccountMenu> {
  // The menu outlives the frame it was opened from: what is picked shows
  // here until it closes.
  late String _locale = widget.vm.locale;
  late ThemeMode _theme = widget.vm.theme;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    // The menu's own words follow a language picked in it: a new locale
    // rebuilds what depends on it.
    Localizations.localeOf(context);
    final s = S.current;
    Widget label(String text) => Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: .w600,
        letterSpacing: 0.66,
        color: c.text4,
      ),
    );
    return Material(
      color: c.ground2,
      elevation: 12,
      shadowColor: c.ground0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: c.line3),
      ),
      clipBehavior: .antiAlias,
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      vm.user,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: mono(weight: .w600, color: c.text1),
                    ),
                    Text(
                      vm.role,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: TextStyle(fontSize: 12, color: c.text4),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.line1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Column(
                  crossAxisAlignment: .stretch,
                  spacing: 8,
                  children: [
                    label(s.menuLanguage),
                    LanguageSwitcher(
                      vm: FieldVm(
                        value: _locale,
                        onChanged: (v) {
                          setState(() => _locale = v);
                          widget.onLanguage(v);
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    label(s.menuTheme),
                    ThemeSwitcher(
                      vm: FieldVm(
                        value: _theme,
                        onChanged: (v) {
                          setState(() => _theme = v);
                          widget.onTheme(v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 21, color: c.line1),
              if (widget.onSecurity case final security?)
                InkWell(
                  onTap: security,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: .centerLeft,
                    child: Text(
                      s.securityMenu,
                      style: TextStyle(fontSize: 14, color: c.text1),
                    ),
                  ),
                ),
              InkWell(
                onTap: widget.onLogOut,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: .centerLeft,
                  child: Text(
                    s.logOut,
                    style: TextStyle(fontSize: 14, color: c.text1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
