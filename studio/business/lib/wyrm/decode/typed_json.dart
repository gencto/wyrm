import 'dart:convert';

import 'package:models/json_value.dart';

import 'decoded.dart';

const _shape = 'typed JSON';

/// [text] typed into an editor of the flow editor, decoded as JSON: the
/// value it is, nested no deeper than [JsonValue.maxDepth]. [Invalid] when
/// it is no JSON, or nests deeper (a person can type, or paste, a value
/// nested without end; the field's check runs during a build, so nothing
/// here throws).
///
/// The text of a field comes in here, once: its error mark
/// (`fieldEditError`) and what it saves (`typedText`) read the same
/// answer, so a value that is refused never reaches a config.
Decoded<JsonValue> typedJsonOf(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return const Invalid(_shape, '', 'not JSON');
  }
  return switch (JsonValue.tryOf(json)) {
    final j? => Valid(j),
    null => const Invalid(_shape, '', 'nested too deep'),
  };
}
