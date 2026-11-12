import 'package:material_ui/material_ui.dart';

/// A round dot in a status colour, with an optional halo ring of the same
/// colour at 15 % (the gateway field of the log-in board: dot 8, halo 4;
/// a recent-gateway chip: dot 6, no halo).
class StatusDot extends StatelessWidget {
  const StatusDot({
    required this.color,
    this.size = 8,
    this.halo = 0,
    super.key,
  });

  final Color color;
  final double size;

  /// The width of the ring around the dot; 0 for none.
  final double halo;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: .circle,
      color: color,
      boxShadow: [
        if (halo > 0)
          BoxShadow(color: color.withValues(alpha: .15), spreadRadius: halo),
      ],
    ),
  );
}
