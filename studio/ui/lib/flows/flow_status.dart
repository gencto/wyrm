import 'package:localization/localization.dart';

/// Where the draft stands, said in the top bar: `Loading…`, `Deploying…`,
/// `Draft saved`, `Version 4 · deployed` (spec §1).
enum FlowStatusVm {
  loading,
  deploying,
  draft,
  deployed;

  /// The words, with the deployed [version].
  String label(int version) => switch (this) {
    loading => S.current.loading,
    deploying => S.current.deploying,
    draft => S.current.draftSaved,
    deployed => S.current.versionDeployed(version),
  };
}
