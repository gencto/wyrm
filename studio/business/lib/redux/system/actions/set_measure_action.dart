import 'package:models/traffic_measure.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetMeasureAction extends Action {
  SetMeasureAction(this.measure);

  final TrafficMeasure measure;

  @override
  AppState reduce() => state.copyWith.system(measure: measure);
}
