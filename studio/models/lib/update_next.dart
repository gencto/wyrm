/// What the primary button of the update sheet does at its stage: update
/// from the repository, update from a file, roll back, open the log, open
/// the link.
enum UpdateNext {
  update,
  file,
  rollback,
  log,
  open,
}
