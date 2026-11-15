import 'package:models/flow_summary.dart';

import '../decode/flow_val.dart';

/// A flow's `~val` as a live sample hands it (`{state, error, version,
/// deployed_by, since}` as plain Dart) read as a [FlowSummary], the way
/// `RetrieveFlowsAction` reads it: state 0 runs, 2 is an error, no state
/// is a draft never deployed. A value that is no map reads as none, with a
/// warning ([flowValOf]).
FlowSummary flowSummaryOfValue(
  String id,
  Object? value, {
  String? description,
}) => flowSummaryOfVal(
  id,
  flowValOf(value).orWarn('flow $id') ?? const FlowVal(),
  description: description,
);
