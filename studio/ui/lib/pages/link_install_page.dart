import 'package:flutter/material.dart';

// TODO(frx): flesh out the LinkInstall page. Keep it a dumb, store-agnostic
// widget — wire state in through LinkInstallPageConnector (app package).
class LinkInstallPage extends StatelessWidget {
  const LinkInstallPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LinkInstall')),
    body: const Center(child: Text('LinkInstall — coming soon')),
  );
}
