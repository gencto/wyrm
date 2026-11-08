import 'package:flutter/material.dart';

// TODO(frx): flesh out the Sites page. Keep it a dumb, store-agnostic
// widget — wire state in through SitesPageConnector (app package).
class SitesPage extends StatelessWidget {
  const SitesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sites')),
    body: const Center(child: Text('Sites — coming soon')),
  );
}
