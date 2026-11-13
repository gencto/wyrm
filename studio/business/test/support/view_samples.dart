import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// The samples of the views lab, read from `docs/design/genui` (what
/// `app/assets/views` is a copy of).
String viewSample(String file) {
  for (final dir in ['../docs/design/genui', 'docs/design/genui']) {
    final f = File('$dir/$file');
    if (f.existsSync()) {
      return f.readAsStringSync();
    }
  }
  throw StateError('no sample $file');
}

/// An asset bundle that answers `assets/views/<file>` from the samples.
class SampleBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    utf8.encode(viewSample(key.split('/').last)),
  );
}
