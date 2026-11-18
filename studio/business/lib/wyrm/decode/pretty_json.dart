import 'dart:convert';

/// [v] (a wire value as plain Dart) as indented JSON, for showing; bytes
/// as base64.
String prettyJson(Object? v) => JsonEncoder.withIndent(
  '  ',
  (o) => o is List<int> ? base64Encode(o) : '$o',
).convert(v);
