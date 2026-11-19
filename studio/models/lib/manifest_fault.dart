/// What is wrong with a manifest a person brought (a package's
/// `wyrm-link.json`, a backup's `manifest.json`), as a kind: `ui` says it
/// in the language on screen.
enum ManifestFault {
  /// The file is not JSON.
  notJson,

  /// The file nests deeper than a manifest may.
  tooDeep,

  /// The file is JSON, and not an object.
  notObject,

  /// The file has a field the format does not have.
  unknownField,

  /// A field the format needs is not there.
  missing,

  /// A field is there in a form the format does not give it.
  wrongForm,

  /// A field holds a name this Studio does not know (a mode, a seal, a
  /// section).
  unknownName,
}
