/// The tabs of the node on screen in Explorer (docs/design/specs/
/// explorer.md "Frames by node kind"): a device has its points, a flow
/// its state and actions, any other node its children.
enum ExplorerTab {
  points,
  children,
  params,
  actions,
  history,
  audit,
}
