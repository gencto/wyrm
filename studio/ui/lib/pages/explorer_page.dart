import 'package:flutter/material.dart';

// TODO(frx): flesh out the Explorer page. Keep it a dumb, store-agnostic
// widget — wire state in through ExplorerPageConnector (app package).
class ExplorerPage extends StatelessWidget {
  const ExplorerPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Explorer')),
    body: const Center(child: Text('Explorer — coming soon')),
  );
}
