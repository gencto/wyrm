import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../buttons/button.dart';
import '../buttons/language_switcher.dart';
import '../buttons/theme_switcher.dart';
import '../containers/auth_from_container.dart';
import '../forms/base_form.dart';
import '../inputs/input_form_field.dart';
import '../inputs/password_form_field.dart';
import '../models/value_changed.dart';
import '../theme/spacing.dart';

/// Log in to a WYRM user gateway: its URL, the user and the password.
///
/// A gateway has users made by an administrator, so there is no registration
/// and no password reset here (docs/studio.md, phase 1).
class LogInPage extends StatelessWidget {
  const LogInPage({
    required this.gateway,
    required this.user,
    required this.password,
    required this.isWaiting,
    required this.onPressedLogIn,
    required this.theme,
    required this.language,
    super.key,
  });

  /// One URL, or several separated by commas for a site with a standby.
  final FieldVm<String?> gateway;
  final FieldVm<String?> user;
  final FieldVm<String?> password;

  /// A log-in is in flight: the button is disabled.
  final bool isWaiting;
  final VoidCallback onPressedLogIn;
  final FieldVm<ThemeMode> theme;

  /// Locale code — `en`, `uk`. See [LanguageSwitcher] for why the app state
  /// carries a code rather than a `Locale`.
  final FieldVm<String> language;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: BaseForm(
      builder: (context, form) {
        void submit() {
          if (!isWaiting && form.validateAndSave()) {
            onPressedLogIn();
          }
        }

        return AuthFormContainer(
          title: S.current.logIn,
          subtitle: S.current.logInSubtitle,
          trailing: Row(
            mainAxisSize: .min,
            spacing: AppSpacing.sm,
            children: [
              LanguageSwitcher(vm: language),
              ThemeSwitcher(vm: theme),
            ],
          ),
          children: [
            Gaps.lg,
            InputFormField(
              vm: gateway,
              labelText: S.current.gatewayUrl,
              hintText: S.current.gatewayUrlHint,
              prefixIcon: const Icon(Icons.dns_outlined),
              keyboardType: .url,
              autofillHints: const [AutofillHints.url],
              textInputAction: .next,
            ),
            Gaps.md,
            InputFormField(
              vm: user,
              labelText: S.current.user,
              prefixIcon: const Icon(Icons.person_outline),
              autofillHints: const [AutofillHints.username],
              textInputAction: .next,
            ),
            Gaps.md,
            PasswordFormField(
              vm: password,
              textInputAction: .done,
              onFieldSubmitted: (_) => submit(),
            ),
            Gaps.lg,
            Button.primary(
              label: S.current.logIn,
              onPressed: isWaiting ? null : submit,
            ),
          ],
        );
      },
    ),
  );
}
