import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/restore_check.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// The answer of `restore_check`.
RestoreCheck restoreCheckOf(Value v) => RestoreCheck(
  site: str(v['site']) ?? '',
  sameSite: boolean(v['same_site']) ?? false,
  created: str(v['created']) ?? '',
  broker: str(v['broker']) ?? '',
  sealed: str(v['sealed']) ?? 'none',
  schemas: {
    if (v['schemas'] case VMap(:final v))
      for (final e in v.entries)
        e.key: (
          integer(e.value['backup']) ?? 0,
          integer(e.value['here']) ?? 0,
        ),
  }.lock,
  sections: {
    if (v['sections'] case VMap(:final v))
      for (final e in v.entries) e.key: integer(e.value) ?? 0,
  }.lock,
  keys: str(v['keys']) ?? 'none',
  keysDiffer: strings(v['keys_differ']).lock,
  controlOpensHere: boolean(v['control_opens_here']) ?? true,
  links: {
    if (v['links'] case VMap(:final v))
      for (final e in v.entries) e.key: str(e.value) ?? '',
  }.lock,
  problems: strings(v['problems']).lock,
  notes: strings(v['notes']).lock,
);
