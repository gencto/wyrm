import 'package:localization/localization.dart';

/// A byte count as a person reads it: `812 B`, `48 KiB`, `3.1 MiB`,
/// `1.2 GiB`. Kept for the callers that still format in `app`; a widget
/// calls [Formats.bytes] itself (studio-rules §5).
String bytesText(int bytes) => Formats.bytes(bytes);
