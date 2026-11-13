import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/extensions/colors.dart';
import '../../theme/typography.dart';
import '../view_card.dart';
import '../view_style.dart';
import 'bind.dart';
import 'schemas.dart';

/// `Column`: its children one under another, as wide as the column.
final Schema columnSchema = part({'children': childrenSchema}, ['children']);

final columnItem = CatalogItem(
  name: 'Column',
  dataSchema: columnSchema,
  widgetBuilder: (item) => childrenOf(
    item,
    (item.data as JsonMap)['children'],
    (children) => Builder(
      builder: (context) => Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: ViewScope.densityOf(context).gap,
        children: children,
      ),
    ),
  ),
);

/// `Row`: its children side by side, sharing the width by `weights` (equal
/// without them). On a phone a row is a column: the document does not
/// decide where it is shown.
final Schema rowSchema = part(
  {
    'children': childrenSchema,
    'weights': S.list(items: S.integer()),
  },
  ['children'],
);

final rowItem = CatalogItem(
  name: 'Row',
  dataSchema: rowSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final weights = data['weights'];
    return childrenOf(
      item,
      data['children'],
      (children) => Builder(
        builder: (context) {
          final d = ViewScope.densityOf(context);
          if (d.narrow) {
            return Column(
              crossAxisAlignment: .stretch,
              mainAxisSize: .min,
              spacing: d.gap,
              children: children,
            );
          }
          return Row(
            crossAxisAlignment: .start,
            spacing: d.gap,
            children: [
              for (final (i, child) in children.indexed)
                Expanded(
                  flex: switch (weights) {
                    final List<Object?> w
                        when i < w.length &&
                            w[i] is int &&
                            (w[i]! as int) > 0 =>
                      w[i]! as int,
                    _ => 1,
                  },
                  child: child,
                ),
            ],
          );
        },
      ),
    );
  },
);

/// `Card`: a titled group; with an `action` the whole card is a button
/// (it opens a page).
final Schema cardSchema = part({
  'title': boundText,
  'variant': S.string(enumValues: ['plain', 'outlined']),
  'emphasis': S.string(enumValues: ['normal', 'key']),
  'children': childrenSchema,
  'action': actionSchema,
});

final cardItem = CatalogItem(
  name: 'Card',
  dataSchema: cardSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final action = data['action'];
    return ViewBind(
      dataContext: item.dataContext,
      props: [data['title']],
      builder: (context, v) => ViewCard(
        title: v[0]?.toString() ?? '',
        outlined: data['variant'] == 'outlined',
        emphasized: data['emphasis'] == 'key',
        onTap: action == null ? null : () => fireAction(item, action),
        child: childrenOf(
          item,
          data['children'] ?? const <Object?>[],
          (children) => Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            spacing: ViewScope.densityOf(context).gap,
            children: children,
          ),
        ),
      ),
    );
  },
);

/// `Text`: words. `variant` picks a step of the type scale; the size in
/// pixels is the theme's.
final Schema textSchema = part(
  {
    'text': boundText,
    'variant': S.string(enumValues: ['h1', 'h2', 'h3', 'body', 'caption']),
  },
  ['text'],
);

final textItem = CatalogItem(
  name: 'Text',
  dataSchema: textSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    return ViewBind(
      dataContext: item.dataContext,
      props: [data['text']],
      builder: (context, v) {
        final c = context.colors;
        final d = ViewScope.densityOf(context);
        final up = d == .desktop || d == .phone ? 0.0 : 4.0;
        return Text(
          v[0]?.toString() ?? '',
          style: switch (data['variant']) {
            'h1' => boardText(size: 26 + up, weight: .w600, color: c.text1),
            'h2' => boardText(size: 20 + up, weight: .w600, color: c.text1),
            'h3' => boardText(size: 16 + up, weight: .w600, color: c.text1),
            'caption' => boardText(size: 12 + up / 2, color: c.text4),
            _ => boardText(size: d.label + 1, color: c.text2, height: 1.45),
          },
        );
      },
    );
  },
);
