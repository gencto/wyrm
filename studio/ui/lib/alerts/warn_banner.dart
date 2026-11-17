import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../indicators/code_text.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// What [WarnBanner] says.
final class WarnBannerVm extends Equatable {
  const WarnBannerVm({
    required this.title,
    required this.body,
    this.action,
  });

  final String title;

  /// A sentence or two; code between backticks.
  final String body;

  /// The link under the body (`Open the audit record ›`), or none.
  final String? action;

  @override
  List<Object?> get props => [title, body, action];
}

/// An amber banner across the page: something is wrong now and here is
/// where to look (board `SystemAvailLag`).
class WarnBanner extends StatelessWidget {
  const WarnBanner({required this.vm, this.onAction, super.key});

  final WarnBannerVm vm;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: Insets.notice,
        decoration: BoxDecoration(
          color: c.warnTint,
          border: .all(color: c.warnLine),
          borderRadius: Radii.card,
        ),
        child: Row(
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            Padding(
              padding: Insets.iconInRow,
              child: AppIconView(
                AppIcon.uiCaution,
                size: IconSizes.lg,
                color: c.warn,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Text(
                    vm.title,
                    style: TextStyle(
                      fontSize: FontSizes.md,
                      height: LineHeights.body,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                  CodeText(
                    vm.body,
                    style: TextStyle(
                      fontSize: FontSizes.md,
                      height: LineHeights.body,
                      color: c.text2,
                    ),
                  ),
                  if (vm.action case final a?)
                    InkWell(
                      onTap: onAction,
                      child: Text(
                        a,
                        style: TextStyle(
                          fontSize: FontSizes.md,
                          height: LineHeights.body,
                          color: c.emberSoft,
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
