import 'package:equatable/equatable.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/code_text.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

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

  static const _triangle = '''
<svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2"
  stroke-linecap="round" stroke-linejoin="round">
  <path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18h.01"/>
</svg>''';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              padding: const EdgeInsets.only(top: 1),
              child: SvgPicture.string(
                _triangle,
                width: 18,
                height: 18,
                colorFilter: ColorFilter.mode(c.warn, BlendMode.srcIn),
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
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                  CodeText(
                    vm.body,
                    style: TextStyle(fontSize: 13, height: 1.5, color: c.text2),
                  ),
                  if (vm.action case final a?)
                    InkWell(
                      onTap: onAction,
                      child: Text(
                        a,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
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
