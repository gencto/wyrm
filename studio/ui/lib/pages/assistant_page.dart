import 'package:flutter/material.dart';

// TODO(frx): flesh out the Assistant page. Keep it a dumb, store-agnostic
// widget — wire state in through AssistantPageConnector (app package).
class AssistantPage extends StatelessWidget {
  const AssistantPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Assistant')),
    body: const Center(child: Text('Assistant — coming soon')),
  );
}
