import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where a characterization test writes the words it sees instead of
/// comparing them (`WORDS_DUMP=<file> flutter test …`): the words files
/// were generated once from the screen this way, then kept by hand.
final String? _dump = Platform.environment['WORDS_DUMP'];

final _seen = <String, List<String>>{};

/// Compares [actual] with [expected], the words of the state [name]; when
/// dumping, records [actual] under [name] instead.
void expectWordsOf(String name, List<String> actual, List<String> expected) {
  if (_dump case final path?) {
    _seen[name] = actual;
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_seen),
    );
    return;
  }
  expect(actual, expected, reason: name);
}
