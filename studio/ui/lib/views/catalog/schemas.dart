import 'package:json_schema_builder/json_schema_builder.dart';

/// The schema pieces the parts of `wyrm:views/0.1` share. A part's schema
/// names every property a document may set and nothing else: no colour, no
/// font, no pixel size (docs/design/specs/genui-views.md §3.2).

/// `{"path": "/wy/…"}`.
Schema get pathSchema => S.object(
  properties: {'path': S.string()},
  required: ['path'],
  additionalProperties: false,
);

/// A number, or the path of one.
Schema get boundNumber => S.combined(anyOf: [S.number(), pathSchema]);

/// A text, or the path of one.
Schema get boundText => S.combined(anyOf: [S.string(), pathSchema]);

/// A bool, or the path of one.
Schema get boundBool => S.combined(anyOf: [S.boolean(), pathSchema]);

/// A value of any plain kind, or the path of one.
Schema get boundValue =>
    S.combined(anyOf: [S.number(), S.string(), S.boolean(), pathSchema]);

/// The children of a container: ids, or a template over a node's children.
Schema get childrenSchema => S.combined(
  anyOf: [
    S.list(items: S.string()),
    S.object(
      properties: {'path': S.string(), 'componentId': S.string()},
      required: ['path', 'componentId'],
      additionalProperties: false,
    ),
  ],
);

/// `{event: {name, context}}`; the context is the action's own.
Schema get actionSchema => S.object(
  properties: {
    'event': S.object(
      properties: {
        'name': S.string(
          enumValues: ['wyrm.set', 'wyrm.invoke', 'wyrm.open'],
        ),
        'context': S.object(additionalProperties: true),
      },
      required: ['name'],
      additionalProperties: false,
    ),
  },
  required: ['event'],
  additionalProperties: false,
);

/// `{path, equals}`.
Schema get enabledWhenSchema => S.object(
  properties: {
    'path': S.string(),
    'equals': S.combined(anyOf: [S.boolean(), S.number(), S.string()]),
  },
  required: ['path', 'equals'],
  additionalProperties: false,
);

/// `s`, `m`, `l`.
Schema get sizeSchema => S.string(enumValues: ['s', 'm', 'l']);

/// The properties of one part: only these, [required] among them.
Schema part(
  Map<String, Schema> properties, [
  List<String> required = const [],
]) => S.object(
  properties: properties,
  required: required,
  additionalProperties: false,
);
