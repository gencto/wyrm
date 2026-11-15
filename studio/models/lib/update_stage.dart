/// Which screen the update sheet of a package shows: the review, the
/// progress of an update, its result, or only the restore points (a
/// package never updated here).
enum UpdateStage {
  review,
  progress,
  result,
  points,
}
