import 'dart:convert';

import 'package:models/json_value.dart';

// A config value as the flow editor shows it: the text its editor starts
// with, a short mark for a structure, the rows of a list of maps.

/// A config value (JSON) as the text its editor starts with: nothing for
/// none, a text as itself, a map or a list as indented JSON, anything else
/// as JSON.
String jsonEditText(JsonValue v) => switch (v) {
  JsonNull() => '',
  JsonText(:final text) => text,
  JsonMap() || JsonList() => const JsonEncoder.withIndent('  ').convert(v.raw),
  JsonBool() || JsonNumber() => jsonEncode(v.raw),
};

/// What a field shows for a map or a list it holds, in short (`{…}`,
/// `[…]`); null for anything else, an empty one too, and for a live value
/// that is no JSON (bytes: its own text shows it).
String? jsonShortText(Object? v) => switch (JsonValue.tryOf(v)) {
  JsonMap(:final fields) when fields.isNotEmpty => '{…}',
  JsonList(:final items) when items.isNotEmpty => '[…]',
  _ => null,
};

/// The items of a list parameter as rows of texts by key: a text as it
/// is, another value as JSON. A value that is no list of maps gives no
/// rows.
List<Map<String, String>> listRowsIn(JsonValue v) => [
  if (v case JsonList(:final items))
    for (final item in items)
      if (item case JsonMap(:final fields))
        {
          for (final MapEntry(:key, :value) in fields.entries)
            key: switch (value) {
              JsonNull() => '',
              JsonText(:final text) => text,
              _ => jsonEncode(value.raw),
            },
        },
];
