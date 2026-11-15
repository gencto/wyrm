import 'package:wyrm_client/wyrm_client.dart' show Perm;

/// A control the user may not use: it needs [level] on [path] (the key
/// below the site), which the user's grants do not reach (docs/studio.md
/// §2 rule 8: shown, never hidden). `ui` words it.
final class Lack {
  const Lack(this.level, this.path);

  final Perm level;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is Lack && other.level == level && other.path == path;

  @override
  int get hashCode => Object.hash(level, path);
}
