/// What is wrong with the name a new link is given in Add a link: it is no
/// key segment, another link on that broker has it, or the broker refused
/// it (its words are kept beside).
enum InstallNameProblem {
  rule,
  taken,
  refused,
}
