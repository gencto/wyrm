import 'dart:convert';

/// What the text of *Edit params* is: one JSON object (the parameters to
/// stage), or why it is not (docs/design/specs/errors.md §2: said under
/// the field as it is typed).
sealed class LinkParamsText {
  const LinkParamsText();
}

/// One JSON object: the parameters.
final class ParamsObject extends LinkParamsText {
  const ParamsObject(this.params);

  final Map<String, Object?> params;
}

/// JSON, but not an object (a list, a number).
final class ParamsNotObject extends LinkParamsText {
  const ParamsNotObject();
}

/// Not JSON: the parser's words.
final class ParamsNotJson extends LinkParamsText {
  const ParamsNotJson(this.detail);

  final String detail;
}

/// [json] as *Edit params* reads it.
LinkParamsText linkParamsOf(String json) {
  final Object? v;
  try {
    v = jsonDecode(json);
  } on FormatException catch (e) {
    return ParamsNotJson(e.message.isEmpty ? 'not JSON' : e.message);
  }
  return v is Map<String, Object?> ? ParamsObject(v) : const ParamsNotObject();
}
