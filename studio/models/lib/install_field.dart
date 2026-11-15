/// A field of Add a link the broker can name when it refuses an install
/// (docs/design/specs/errors.md §3, *Back to the form*): the link's name,
/// the package URL, the Git repository's URL, the Git ref.
enum InstallField {
  name,
  url,
  git,
  ref,
}
