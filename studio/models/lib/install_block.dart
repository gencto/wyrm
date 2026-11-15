/// Why Add a link offers no *Continue* (or *Install*) on its step: nothing
/// picked from the official list, nothing brought, a check failed, no name,
/// a name with a problem, rights not accepted, no config on the broker's
/// `sys/links`.
enum InstallBlock {
  pickOne,
  bringOne,
  checkFailed,
  nameIt,
  nameProblem,
  acceptFirst,
  needsConfig,
}
