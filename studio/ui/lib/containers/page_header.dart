import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import 'refresh_frame.dart';

/// A workspace's title (26/600), one line under it, and its one primary
/// action on the right. Inside a refreshing [RefreshFrame] the line under the
/// title ends in its status (`· Updating…`, 12 `text4`): the workspace's
/// status line (docs/studio.md §6.7).
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = RefreshScope.statusOf(context);
    return Row(
      crossAxisAlignment: .start,
      spacing: 16,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 6,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null || status != null)
                Text.rich(
                  TextSpan(
                    children: [
                      if (subtitle case final s?) TextSpan(text: s),
                      if (status case final u?)
                        TextSpan(
                          text: subtitle == null ? u : '  ·  $u',
                          style: TextStyle(fontSize: 12, color: c.text4),
                        ),
                    ],
                  ),
                  style: TextStyle(fontSize: 14, color: c.text3),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
