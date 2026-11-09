import 'package:flutter/material.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';

/// Shown under the top bar while the gateway socket is gone: the client
/// reconnects by itself; values on screen are the last ones received.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: .infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.warnTint,
        border: Border(bottom: BorderSide(color: c.warnLine)),
      ),
      child: Row(
        spacing: 10,
        children: [
          StateMark(mark: Mark.ring, color: c.warn),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: c.warn),
            ),
          ),
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.warn),
          ),
        ],
      ),
    );
  }
}
