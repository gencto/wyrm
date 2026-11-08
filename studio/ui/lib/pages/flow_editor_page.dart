import 'package:flutter/material.dart';

// TODO(frx): flesh out the FlowEditor page. Keep it a dumb, store-agnostic
// widget — wire state in through FlowEditorPageConnector (app package).
class FlowEditorPage extends StatelessWidget {
  const FlowEditorPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('FlowEditor')),
    body: Center(child: Text('id: $id')),
  );
}
