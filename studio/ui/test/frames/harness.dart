import 'package:material_ui/material_ui.dart';
import 'package:ui/theme/common.dart';

/// A frame in the Studio dark theme at the canvas's width.
Widget frame(Widget child, {ThemeData? theme}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme ?? darkTheme(),
  home: Scaffold(body: child),
);
