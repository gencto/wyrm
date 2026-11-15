/// Where Add a link takes a new link from (docs/studio.md §7.3): the
/// official list (a built-in driver or a repository package), a package
/// the user brings, or a link backup (`.wyrm-link`, ADR 0048 §3.5).
enum InstallPath {
  official,
  custom,
  backup,
}
