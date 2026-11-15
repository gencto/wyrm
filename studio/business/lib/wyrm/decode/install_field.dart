import 'package:models/install_field.dart';

/// The field of Add a link that holds the parameter [param] the broker
/// named in a refusal (`url: host not reachable`): `id` and `name` are the
/// link's name; `url` is the Git repository's URL when the package came
/// from Git ([git]), else the package URL; `ref` the Git ref. Null for a
/// parameter no field of the wizard holds.
InstallField? installFieldOf(String param, {required bool git}) =>
    switch (param) {
      'id' || 'name' => InstallField.name,
      'url' => git ? InstallField.git : InstallField.url,
      'ref' => InstallField.ref,
      _ => null,
    };
