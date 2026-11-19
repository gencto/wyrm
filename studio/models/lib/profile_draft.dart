import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart' hide JsonValue;
import 'package:wyrm_core/wyrm_core.dart';

import 'json_value.dart';

part 'profile_draft.freezed.dart';

@freezed
abstract class ProfileDraft with _$ProfileDraft {
  /// A profile as a person wrote it in a JSON file (specs/system.md): its
  /// `~meta` in words. Each field is of its type or not there; `cfg` and
  /// `attr` hold JSON as the file writes it.
  const factory ProfileDraft({
    /// `extends`: the profile it inherits.
    String? parent,
    TypeCode? type,
    String? unit,

    /// `enum`: the names of its values.
    IList<String>? enumValues,
    String? display,
    IList<String>? children,
    IMap<String, JsonValue>? cfg,
    IMap<String, JsonValue>? attr,
  }) = _ProfileDraft;
}
