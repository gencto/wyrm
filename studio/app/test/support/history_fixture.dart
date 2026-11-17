import 'package:business/redux/app_state.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/logging_type.dart';
import 'package:models/watch_group.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'screen_app.dart';

/// `wy/plant/sys/history`.
const hist = '$plant/sys/history';

/// Two points of `plc1`.
const t1 = '$plant/downstream/plc1/t1';
const t2 = '$plant/downstream/plc1/t2';

/// The watch groups of `plant`: one recording on change, one every 5 s.
final groupsOfPlant = [
  WatchGroup(
    name: 'boiler-1',
    loggingType: LoggingType.pointChange,
    flush: 5,
    watchIds: ['w1', 'w2'].lock,
    keys: [t1, t2].lock,
  ),
  WatchGroup(
    name: 'tank',
    loggingType: LoggingType.interval,
    interval: 5,
    flush: 2.5,
    watchIds: ['w1'].lock,
    keys: ['$plant/downstream/tank/level'].lock,
  ),
];

/// [s] with the groups of `plant` and the historian's values; [selected]
/// picked with its [points] on the trend.
AppState withGroups(
  AppState s, {
  bool groups = true,
  String? selected,
  List<String> points = const [],
}) => s.copyWith(
  historian: s.historian.copyWith(
    groups: groups ? groupsOfPlant.lock : const IListConst([]),
    selected: selected,
    points: points.lock,
    stats: IMap(const {
      'database_size': '1530',
      'series': '3',
      'retention_days': '90',
      'rows_written': '12000',
      'oldest_day': '2026-08-01',
    }),
  ),
);

/// What the fake broker holds for History: the rows of t1 and t2, the
/// group's actions and their answers.
void historyBroker(FakeWyrmApi api) {
  final t0 = DateTime.utc(2026, 11, 12).microsecondsSinceEpoch;
  const hour = 3600 * 1000000;
  api
    ..histories[t1] = [
      for (var i = 0; i < 6; i++)
        HistRow(t0 + i * hour, VFloat(20.5 + i), Quality.good),
    ]
    ..histories[t2] = [
      for (var i = 0; i < 6; i++) HistRow(t0 + i * hour, VInt(40 + i)),
    ]
    ..metas[t1] = NodeMeta(ty: TypeCode.number, unit: const TText('°C'))
    ..metas[hist] = NodeMeta(
      actions: {
        'add_watch_group': ActionMeta(
          level: Perm.config,
          params: {'name': ParamMeta(ty: TypeCode.string, required: true)},
        ),
        'purge': ActionMeta(level: Perm.config),
      },
    )
    ..metas['$hist/boiler-1'] = NodeMeta(
      actions: {
        'remove': ActionMeta(level: Perm.config),
        'edit': ActionMeta(
          level: Perm.config,
          params: {'interval': ParamMeta(ty: TypeCode.number)},
        ),
        'add_watch_path': ActionMeta(
          level: Perm.config,
          params: {'path': ParamMeta(ty: TypeCode.string, required: true)},
        ),
      },
    )
    ..metas['$hist/boiler-1/w1'] = NodeMeta(
      actions: {'unsubscribe': ActionMeta(level: Perm.config)},
    )
    ..invokes['$hist/boiler-1 ▸ remove'] = const [VNull()]
    ..invokes['$hist/boiler-1/w1 ▸ unsubscribe'] = const [VNull()]
    ..invokes['$hist ▸ add_watch_group'] = const [VNull()];
}
