import 'package:material_ui/material_ui.dart';

class BaseLinearIndicator extends StatelessWidget {
  const BaseLinearIndicator({super.key});

  @override
  Widget build(BuildContext context) => const LinearProgressIndicator(
    minHeight: 2,
    backgroundColor: Colors.transparent,
  );
}
