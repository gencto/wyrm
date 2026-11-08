import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';

/// The right panel (320–360): an [eyebrow] label, a [title], an optional
/// [header] below it, then [child]. One selection drives it.
class Inspector extends StatelessWidget {
  const Inspector({
    required this.title,
    required this.child,
    this.eyebrow,
    this.header,
    this.width = 340,
    this.onClose,
    super.key,
  });

  final String? eyebrow;
  final String title;
  final Widget? header;
  final Widget child;
  final double width;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(left: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line1)),
            ),
            child: Row(
              crossAxisAlignment: .start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 4,
                    children: [
                      if (eyebrow case final e?)
                        Text(
                          e.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: .w600,
                            letterSpacing: 0.72,
                            color: c.text3,
                          ),
                        ),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ?header,
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: Icon(Icons.close, size: 18, color: c.text3),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
