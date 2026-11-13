import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'controls.dart';
import 'layout.dart';
import 'points.dart';

/// The id of the catalog a WYRM view is written against.
const wyrmCatalogId = 'wyrm:views/0.1';

/// The parts of `wyrm:views/0.1` (docs/design/specs/genui-views.md §3):
/// Studio's own widgets only, none of genui's `BasicCatalogItems`, so a
/// surface is drawn with the theme's tokens and the density of where it is
/// shown and a document can choose parts and variants, never looks.
Catalog wyrmCatalog() => Catalog(
  [
    columnItem,
    rowItem,
    cardItem,
    textItem,
    valueItem,
    lampItem,
    symbolItem,
    trendItem,
    alarmListItem,
    switchItem,
    sliderItem,
    buttonItem,
  ],
  catalogId: wyrmCatalogId,
);

/// Part name → the schema of the properties a document may set on it,
/// strict (`additionalProperties: false`). `CatalogItem.dataSchema` is not
/// used for checks: it adds `additionalProperties: true`, which lets a
/// colour or a font through.
Map<String, Schema> get wyrmPartSchemas => {
  'Column': columnSchema,
  'Row': rowSchema,
  'Card': cardSchema,
  'Text': textSchema,
  'Value': valueSchema,
  'Lamp': lampSchema,
  'Symbol': symbolSchema,
  'Trend': trendSchema,
  'AlarmList': alarmListSchema,
  'Switch': switchSchema,
  'Slider': sliderSchema,
  'Button': buttonSchema,
};

/// [wyrmPartSchemas] as plain JSON, for the checks in `business`.
Map<String, Object> wyrmCatalogSchemas() => {
  for (final e in wyrmPartSchemas.entries) e.key: e.value.value,
};
