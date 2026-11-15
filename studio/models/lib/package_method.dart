/// How a custom package is brought to Add a link: a zip picked from disk
/// (`install_zip`), a zip at a URL (`install_url`), a Git repository with a
/// built package (`install_git`), or one WASM component (`install_wasm`).
enum PackageMethod {
  zip,
  url,
  git,
  wasm,
}
