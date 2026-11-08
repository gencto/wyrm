/// What a node of the tree is, as Explorer chooses its frame
/// (docs/design/specs/explorer.md "Frames by node kind"): only a device
/// gets the points frame, a flow gets its own, the rest list their
/// children.
enum NodeKind { folder, link, connection, device, flow, storage, broker }
