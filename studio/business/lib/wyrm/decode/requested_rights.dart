import 'package:models/requested_right.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

const _shape = 'package manifest';

/// The rights a package's manifest asks for (`wyrm-link.json` as plain
/// JSON): its [capabilities] (`net`, `store_mb`, `memory_mb`, `call_ms`)
/// and its [requester] grants (`{path, level}`). A field of another type
/// is [Invalid] with its name.
Decoded<List<RequestedRight>> requestedRightsOf(
  Object? capabilities,
  Object? requester,
) {
  final rights = <RequestedRight>[];
  switch (capabilities) {
    case null:
      break;
    case final Map<String, Object?> c:
      switch (c['net']) {
        case null:
          break;
        case final List<Object?> n when n.every((e) => e is String):
          if (n.isNotEmpty) {
            rights.add(RequestedRight.network(n.cast<String>()));
          }
        default:
          return const Invalid(
            _shape,
            'capabilities.net',
            'not a list of texts',
          );
      }
      for (final (field, right) in <(String, RequestedRight Function(int))>[
        ('store_mb', RequestedRight.store),
        ('memory_mb', RequestedRight.memory),
        ('call_ms', RequestedRight.call),
      ]) {
        switch (c[field]) {
          case null:
            break;
          case final int n:
            rights.add(right(n));
          default:
            return Invalid(_shape, 'capabilities.$field', 'not a whole number');
        }
      }
    default:
      return const Invalid(_shape, 'capabilities', 'not a map');
  }
  switch (requester) {
    case null:
      break;
    case final List<Object?> grants:
      for (final g in grants) {
        if (g case {'path': final String path, 'level': final String level}) {
          final perm = Perm.fromWire(level);
          if (perm == null) {
            return const Invalid(_shape, 'requester.level', 'not a level');
          }
          rights.add(RequestedRight.grant(level: perm, path: path));
        } else {
          return const Invalid(_shape, 'requester', 'not a {path, level}');
        }
      }
    default:
      return const Invalid(_shape, 'requester', 'not a list');
  }
  return Valid(rights);
}
