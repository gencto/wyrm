import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';

/// A workspace's title (26/600), one line under it, and its one primary
/// action on the right.
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
              if (subtitle case final s?)
                Text(s, style: TextStyle(fontSize: 14, color: c.text3)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
