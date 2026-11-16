import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_def.dart';
import 'package:models/block_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';
import 'block_def.dart';
import 'decoded.dart';

// The site's library of custom blocks (`dataflows` ▸ `list_blocks`,
// `get_block`, `put_block`, spec 06 0.2.24, ADR 0040 §3).

/// One row of `list_blocks`: `{name, version, description?, inputs,
/// outputs}`. [Invalid] when it is no map or has no `name`.
Decoded<BlockInfo> blockInfoOf(Value v) {
  if (v is! VMap) {
    return const Invalid('library block', '', 'not a map');
  }
  final name = switch (v['name']) {
    VStr(:final v) when v.isNotEmpty => v,
    _ => null,
  };
  if (name == null) {
    return const Invalid('library block', 'name', 'missing');
  }
  return Valid(
    BlockInfo(
      name: name,
      version: integer(v['version']) ?? 0,
      description: str(v['description']),
      inputs: [
        if (v['inputs'] case VArray(:final v))
          for (final x in v) ?str(x),
      ].lock,
      outputs: [
        if (v['outputs'] case VArray(:final v))
          for (final x in v) ?str(x),
      ].lock,
    ),
  );
}

/// The rows `list_blocks` answers: one array of rows, or the rows one by
/// one. Each row is [blockInfoOf]; one that does not read is left out with
/// a warning. Sorted by name.
List<BlockInfo> blockListOf(List<Value> rows, {required String where}) {
  final list = switch (rows) {
    [VArray(:final v)] => v,
    _ => rows,
  };
  return [
    for (final r in list) ?blockInfoOf(r).orWarn(where),
  ]..sort((a, b) => a.name.compareTo(b.name));
}

/// `get_block`'s answer `{name, version, def, requires}`: the block's
/// definition and those of the library blocks it uses, decoded (a flow
/// copies them into its `blocks`).
final class LibraryBlock {
  const LibraryBlock({
    required this.version,
    required this.def,
    this.requires = const {},
  });

  final int version;
  final BlockDef def;
  final Map<String, BlockDef> requires;
}

/// `get_block`'s answer. [Invalid] when it is no map, has no whole
/// `version`, its `def` is no block definition ([blockDefOf]), or
/// `requires` is no map of them.
Decoded<LibraryBlock> libraryBlockOf(Value answer) {
  if (answer is! VMap) {
    return const Invalid('library block', '', 'not a map');
  }
  final version = integer(answer['version']);
  if (version == null) {
    return const Invalid('library block', 'version', 'not a whole number');
  }
  final def = switch (toDart(answer['def'])) {
    final Map<String, Object?> m => blockDefOf(m),
    _ => const Invalid<BlockDef>('library block', '', 'not a map'),
  };
  if (def case Invalid(:final field, :final reason)) {
    return Invalid(
      'library block',
      field.isEmpty ? 'def' : 'def.$field',
      reason,
    );
  }
  final requires = <String, BlockDef>{};
  switch (toDart(answer['requires'])) {
    case null:
      break;
    case final Map<String, Object?> m:
      for (final MapEntry(:key, :value) in m.entries) {
        switch (value) {
          case final Map<String, Object?> v:
            switch (blockDefOf(v)) {
              case Valid(value: final d):
                requires[key] = d;
              case Invalid(:final field, :final reason):
                return Invalid(
                  'library block',
                  field.isEmpty ? 'requires.$key' : 'requires.$key.$field',
                  reason,
                );
            }
          default:
            return Invalid('library block', 'requires.$key', 'not a map');
        }
      }
    default:
      return const Invalid('library block', 'requires', 'not a map');
  }
  return switch (def) {
    Valid(value: final d) => Valid(
      LibraryBlock(version: version, def: d, requires: requires),
    ),
    final Invalid<BlockDef> i => Invalid(i.shape, i.field, i.reason),
  };
}

/// The version `put_block` answers (`{version}`); [Invalid] without one.
Decoded<int> putBlockVersionOf(Value answer) => switch (integer(
  answer['version'],
)) {
  final v? => Valid(v),
  null => const Invalid('put_block answer', 'version', 'not a whole number'),
};

/// The arguments of `get_block` and `remove_block`: `{name}`.
Value nameArgs(String name) => VMap({'name': VStr(name)});

/// The arguments of `put_block`: `{name, def}`, the definition without
/// the editor's mark of where it came from.
Value putBlockArgs(String name, BlockDef def) => Value.from({
  'name': name,
  'def': blockDefJsonOf(def.copyWith(libraryVersion: null)),
});
