import 'package:models/driver_status.dart';
import 'package:models/flow_summary.dart';
import 'package:models/link_state.dart';

import '../mappers/value_text.dart';
import 'decoded.dart';

// Live samples as Explorer reads them. `LiveValue.value` holds a sample as
// plain Dart (the live values service turns the wire value into one); the
// shapes below are read from that form, once, here.

/// `sys/links/<id>/state`: an enum code (wyrm-admin `STATES`) or its name.
Decoded<LinkState> linkStateSampleOf(Object? v) => switch (v) {
  final int code => switch (LinkState.fromCode(code)) {
    final s? => Valid(s),
    null => const Invalid('link state', '', 'not a known code'),
  },
  final String name => switch (LinkState.fromWire(name)) {
    final s? => Valid(s),
    null => const Invalid('link state', '', 'not a known name'),
  },
  _ => const Invalid('link state', '', 'not a code or a name'),
};

/// A broker's `connected`: a bool.
Decoded<bool> brokerConnectedOf(Object? v) => switch (v) {
  final bool b => Valid(b),
  _ => const Invalid('broker connected', '', 'not a bool'),
};

/// A flow's `~val` (`{state, error, version, deployed_by, since}`) as a
/// [FlowSummary] of the flow [id]: state 0 runs, 2 is an error (its
/// `error` as the problem, empty when it gives none: `ui` words that), no
/// state is a draft never deployed; no value at all is one too. `since` is
/// µs since the epoch.
Decoded<FlowSummary> flowSampleOf(
  String id,
  Object? v, {
  String? description,
}) {
  final m = switch (v) {
    null => const <String, Object?>{},
    final Map<String, Object?> m => m,
    _ => null,
  };
  if (m == null) {
    return const Invalid('flow value', '', 'not a map');
  }
  int? whole(Object? x) => switch (x) {
    final int i => i,
    final double d when d == d.truncateToDouble() => d.toInt(),
    _ => null,
  };
  final state = whole(m['state']);
  final since = whole(m['since']);
  return Valid(
    FlowSummary(
      id: id,
      version: whole(m['version']),
      deployedBy: switch (m['deployed_by']) {
        final String s when s.isNotEmpty => s,
        _ => null,
      },
      problem: state == 2
          ? switch (m['error']) {
              final String e => e,
              _ => '',
            }
          : null,
      draft: state == null,
      description: description,
      running: state == 0,
      since: since == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(since, isUtc: true),
    ),
  );
}

/// A connection's or a device's framework `status` (ADR 0004): an index
/// into [choices] (its enum names) or a name. The name is the driver's own
/// word, kept as it is; the state is the one this client knows by it.
({String name, DriverStatus? status}) driverStatusSampleOf(
  Object? v,
  List<String> choices,
) {
  final name = valueText(v, choices: choices);
  return (name: name, status: DriverStatus.fromName(name));
}
