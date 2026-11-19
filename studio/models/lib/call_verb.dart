/// What a call does, as an error's title says it (`You can’t deploy …`,
/// `Installing … failed`): each `KnownCall` names its verb; a call Studio
/// does not know by name (any action of a link) is [run].
enum CallVerb {
  deploy,
  install,
  write,
  read,
  list,
  remove,
  save,
  start,
  stop,
  open,
  logIn,
  run,
}
