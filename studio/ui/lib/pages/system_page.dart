import 'package:flutter/material.dart';

// TODO(frx): flesh out the System page. Keep it a dumb, store-agnostic
// widget — wire state in through SystemPageConnector (app package).
class SystemPage extends StatelessWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('System')),
    body: const Center(child: Text('System — coming soon')),
  );
}
