import 'package:equatable/equatable.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

/// Why a control is off: the user lacks [level] on [key] (docs/studio.md
/// §2 rule 8: shown, never hidden). [key] is relative to the site
/// (`dataflows/tank`), as the words show it; `ui` says the sentence.
final class NeedsRight extends Equatable {
  const NeedsRight(this.level, this.key);

  final Perm level;
  final String key;

  @override
  List<Object?> get props => [level, key];
}
