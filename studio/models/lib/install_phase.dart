/// Where an install of Add a link is: sent and not answered, installed, or
/// not installed (the broker's `success: false` or a refusal).
enum InstallPhase {
  installing,
  done,
  failed,
}
