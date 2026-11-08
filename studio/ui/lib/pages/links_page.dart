import 'package:flutter/material.dart';

// TODO(frx): flesh out the Links page. Keep it a dumb, store-agnostic
// widget — wire state in through LinksPageConnector (app package).
class LinksPage extends StatelessWidget {
  const LinksPage({required this.onTapLinkInstall, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Links')),
    body: const Center(child: Text('Links — coming soon')),
  );

  final void Function() onTapLinkInstall;
}
