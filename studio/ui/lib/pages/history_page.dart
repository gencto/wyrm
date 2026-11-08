import 'package:flutter/material.dart';

// TODO(frx): flesh out the History page. Keep it a dumb, store-agnostic
// widget — wire state in through HistoryPageConnector (app package).
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('History')),
    body: const Center(child: Text('History — coming soon')),
  );
}
