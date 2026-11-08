import 'package:flutter/material.dart';

// TODO(frx): flesh out the Flows page. Keep it a dumb, store-agnostic
// widget — wire state in through FlowsPageConnector (app package).
class FlowsPage extends StatelessWidget {
  const FlowsPage({required this.onTapFlowEditor, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Flows')),
    body: const Center(child: Text('Flows — coming soon')),
  );

  final void Function(String) onTapFlowEditor;
}
