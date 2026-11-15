import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// With `DUMP_WORDS=1` in the environment the words tests print what the
/// screen shows instead of checking it: how the expected lists of a
/// characterization test were written once, before a rewrite.
final dumpWords = Platform.environment['DUMP_WORDS'] == '1';

/// Checks that [got] are the words [name] expects in [expected], or prints
/// them under [name] when [dumpWords].
void expectWords(
  String name,
  List<String> got,
  Map<String, List<String>> expected,
) {
  if (dumpWords) {
    // One line per state, to paste.
    stdout.writeln('WORDS ${jsonEncode(name)}: ${jsonEncode(got)},');
    return;
  }
  expect(got, expected[name], reason: name);
}
