import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// One row of an [ViewAlarmList].
final class ViewAlarmVm extends Equatable {
  const ViewAlarmVm({
    required this.time,
    required this.text,
    this.state = ViewState.alarm,
  });

  final String time;
  final String text;
  final ViewState state;

  @override
  List<Object?> get props => [time, text, state];
}

/// The `AlarmList` part of a view: the active alarms of a source. In the
/// prototype the rows are not read from the alarm link yet, so it draws
/// its title and the empty line.
class ViewAlarmList extends StatelessWidget {
  const ViewAlarmList({required this.title, this.rows = const [], super.key});

  final String title;
  final List<ViewAlarmVm> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = ViewScope.densityOf(context);
    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      spacing: 6,
      children: [
        if (title.isNotEmpty)
          Text(
            title,
            style: boardText(size: d.label + 1, weight: .w600, color: c.text1),
          ),
        if (rows.isEmpty)
          Text(
            S.current.viewsAlarmsNone,
            style: boardText(size: d.label, color: c.text4),
          ),
        for (final r in rows)
          Row(
            spacing: 10,
            children: [
              Text(
                r.time,
                style: boardText(size: d.label, color: c.text4, code: true),
              ),
              Expanded(
                child: Text(
                  r.text,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: boardText(size: d.label, color: r.state.of(c)),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
