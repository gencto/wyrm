enum LinksTab {
  local,

  /// The links whose package has a newer version (ADR 0048 §1); the tab is
  /// shown only while there is one.
  updates,
  remote,
  quarantine,
}
