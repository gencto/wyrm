import 'package:material_ui/material_ui.dart';
import 'package:ui/theme/shades.dart';

import '../connectors/security_dialog_connector.dart';

/// Opens Account › Security over [context] (from the avatar menu). Kept out
/// of the connector: a connector takes no `BuildContext` (studio-rules §4).
Future<void> showSecurityDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Shades.barrier,
  builder: (dialog) => Center(
    child: SecurityDialogConnector(close: () => Navigator.of(dialog).pop()),
  ),
);
