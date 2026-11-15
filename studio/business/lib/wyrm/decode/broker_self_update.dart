import 'package:models/broker_self_update.dart';
import 'package:models/self_update_state.dart';

import 'decoded.dart';
import 'live_fields.dart';

const _shape = 'sys';

/// The keys below `sys` [brokerSelfUpdateOf] reads.
const selfUpdateKeys = [
  'version',
  'latest',
  'update_state',
  'update_mode',
  'update_last',
];

/// What the broker says of its own update (ADR 0048 §2.4), from [value]
/// (the live value of a key below `sys`, as plain Dart): `version`,
/// `latest` (empty text: none), `update_state` (default `none`),
/// `update_mode` (default `self`) and `update_last`. A value of another
/// shape is left at its default **and logged** with its key and [where].
BrokerSelfUpdate brokerSelfUpdateOf(
  Object? Function(String key) value,
  String where,
) => BrokerSelfUpdate(
  version: liveText(value('version'), _shape, 'version').orWarn(where) ?? '',
  latest: liveText(value('latest'), _shape, 'latest').orWarn(where) ?? '',
  state:
      _named(
        value('update_state'),
        SelfUpdateState.fromWire,
        'update_state',
      ).orWarn(where) ??
      SelfUpdateState.none,
  mode:
      _named(
        value('update_mode'),
        SelfUpdateMode.fromWire,
        'update_mode',
      ).orWarn(where) ??
      SelfUpdateMode.self,
  last: updateLastOf(value('update_last')).orWarn(where) ?? const UpdateLast(),
);

/// An empty text is no value (the broker clears these to `""`).
Decoded<E?> _named<E>(Object? v, E? Function(String) of, String field) =>
    v == '' ? const Valid(null) : liveName(v, of, _shape, field);

/// `sys/update_last`: a map of facts, each a text or a number (kept as
/// its digits). Absent: no facts.
Decoded<UpdateLast> updateLastOf(Object? v) {
  switch (v) {
    case null:
      return const Valid(UpdateLast());
    case final Map<String, Object?> m:
      String? fact(String k) => switch (m[k]) {
        null => null,
        final String s => s,
        final num n => '$n',
        final o => throw _Bad(k, o),
      };
      try {
        return Valid(
          UpdateLast(
            from: fact('from'),
            to: fact('to'),
            reason: fact('reason'),
            downS: fact('down_s'),
            linksBack: fact('links_back'),
            links: fact('links'),
            backS: fact('back_s'),
            rollbackUntil: fact('rollback_until'),
          ),
        );
      } on _Bad catch (b) {
        return Invalid('update_last', b.field, 'not a text or a number');
      }
    default:
      return const Invalid(_shape, 'update_last', 'not a map');
  }
}

final class _Bad implements Exception {
  const _Bad(this.field, this.value);

  final String field;
  final Object value;
}
