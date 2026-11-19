import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Studio's version, in the log-in footer and the about lines
/// (`app/pubspec.yaml`).
const studioVersion = '1.0';

/// The version of the system Studio runs on (`15.1` of `Version 15.1
/// (Build 24B83)`); null on the web and when the system names none.
String? hostOsVersion() => kIsWeb
    ? null
    : RegExp(
        r'\d+(\.\d+)+',
      ).firstMatch(Platform.operatingSystemVersion)?.group(0);
