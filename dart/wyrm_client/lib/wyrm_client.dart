/// WYRM client: `list` / `subscribe` as streams, `set`, `invoke`, `meta`,
/// `children`, over the user gateway (WebSocket) or any [FrameTransport]
/// (the FFI binding in `wyrm_ffi` is one).
library;

export 'package:wyrm_core/wyrm_core.dart';

export 'src/api.dart';
export 'src/frames.dart';
export 'src/gateway.dart';
