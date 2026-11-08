import 'package:flutter/material.dart';

// TODO(frx): flesh out the Access page. Keep it a dumb, store-agnostic
// widget — wire state in through AccessPageConnector (app package).
class AccessPage extends StatelessWidget {
  const AccessPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Access')),
    body: const Center(child: Text('Access — coming soon')),
  );
}
