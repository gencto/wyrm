import 'package:models/flow_summary.dart';

import '../decode/flow_val.dart';

/// A flow's `~val` as a live sample hands it (`{state, error, version,
/// deployed_by, since}` as plain Dart) read as a [FlowSummary], the way
/// `RetrieveFlowsAction` reads it: state 0 runs, 2 is an error, no state
/// is a draft never deployed. A value Studio cannot read gives a summary
/// that says so, with a warning ([flowSummaryOf]).
FlowSummary flowSummaryOfValue(
  String id,
  Object? value, {
  String? description,
}) => flowSummaryOf(
  id,
  flowValOf(value),
  where: 'flow $id',
  description: description,
);
