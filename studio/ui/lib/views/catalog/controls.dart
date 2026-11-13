import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:material_ui/material_ui.dart';

import '../../buttons/button.dart';
import '../view_slider.dart';
import '../view_style.dart';
import '../view_switch.dart';
import 'bind.dart';
import 'schemas.dart';

int? _int(Object? v) => switch (v) {
  final num n => n.toInt(),
  _ => null,
};

/// `Switch`: a bool point and the action that writes the other value
/// (`{"path": "$value"}` in its context).
final Schema switchSchema = part(
  {
    'label': S.string(),
    'value': boundBool,
    'action': actionSchema,
    'confirm': S.string(),
    'enabledWhen': enabledWhenSchema,
  },
  ['value'],
);

final switchItem = CatalogItem(
  name: 'Switch',
  dataSchema: switchSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final action = data['action'];
    return ViewBind(
      dataContext: item.dataContext,
      props: [data['value'], ...enabledProps(data['enabledWhen'])],
      builder: (context, v) => ViewSwitch(
        label: data['label'] as String? ?? '',
        value: boolOf(v[0]),
        onChanged: action != null && isEnabled(data['enabledWhen'], v[1], v[2])
            ? (on) => fireAction(
                item,
                action,
                value: on,
                confirm: data['confirm'] as String?,
              )
            : null,
      ),
    );
  },
);

/// `Slider`: a number point in a range and the action that writes the
/// value the user lets go of.
final Schema sliderSchema = part(
  {
    'label': S.string(),
    'value': boundNumber,
    'min': S.number(),
    'max': S.number(),
    'step': S.number(),
    'unit': S.string(),
    'action': actionSchema,
    'confirm': S.string(),
    'enabledWhen': enabledWhenSchema,
  },
  ['value', 'min', 'max'],
);

final sliderItem = CatalogItem(
  name: 'Slider',
  dataSchema: sliderSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final action = data['action'];
    final step = numberOf(data['step']);
    return ViewBind(
      dataContext: item.dataContext,
      props: [
        data['value'],
        ...metaOf(item.dataContext, data['value']).take(2),
        ...enabledProps(data['enabledWhen']),
      ],
      builder: (context, v) => ViewSlider(
        vm: ViewSliderVm(
          label: data['label'] as String? ?? '',
          value: numberOf(v[0]),
          min: numberOf(data['min']) ?? 0,
          max: numberOf(data['max']) ?? 100,
          step: step,
          unit: data['unit'] as String? ?? v[1]?.toString() ?? '',
          decimals:
              _int(v[2]) ??
              (step != null && step == step.roundToDouble() ? 0 : 1),
          enabled: action != null && isEnabled(data['enabledWhen'], v[3], v[4]),
        ),
        onCommit: (value) => fireAction(
          item,
          action,
          value: value,
          confirm: data['confirm'] as String?,
        ),
      ),
    );
  },
);

/// `Button`: a labelled action. `variant` is its role (primary, neutral,
/// danger), never a colour.
final Schema buttonSchema = part(
  {
    'label': S.string(),
    'variant': S.string(enumValues: ['primary', 'neutral', 'danger']),
    'confirm': S.string(),
    'enabledWhen': enabledWhenSchema,
    'action': actionSchema,
  },
  ['label', 'action'],
);

final buttonItem = CatalogItem(
  name: 'Button',
  dataSchema: buttonSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final danger = data['variant'] == 'danger';
    return ViewBind(
      dataContext: item.dataContext,
      props: enabledProps(data['enabledWhen']),
      builder: (context, v) {
        final d = ViewScope.densityOf(context);
        final label = data['label'] as String? ?? '';
        final onPressed = isEnabled(data['enabledWhen'], v[0], v[1])
            ? () => fireAction(
                item,
                data['action'],
                confirm: data['confirm'] as String?,
                danger: danger,
              )
            : null;
        return SizedBox(
          height: d.button,
          child: switch (data['variant']) {
            'primary' => Button.primary(
              label: label,
              onPressed: onPressed,
              expand: true,
              fontSize: d.label + 1,
            ),
            'danger' => Button.danger(
              label: label,
              onPressed: onPressed,
              expand: true,
              fontSize: d.label + 1,
            ),
            _ => Button.secondary(
              label: label,
              onPressed: onPressed,
              expand: true,
              fontSize: d.label + 1,
            ),
          },
        );
      },
    );
  },
);
