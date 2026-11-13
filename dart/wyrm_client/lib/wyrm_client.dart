/// WYRM client: `list` / `subscribe` as streams, `set`, `invoke`, `meta`,
/// `children`, over the user gateway (WebSocket) or any [FrameTransport]
/// (the FFI binding in `wyrm_ffi` is one).
library;

export 'package:wyrm_core/wyrm_core.dart';

export 'src/api.dart';
export 'src/frames.dart';
// The gateway transport: `dart:io` everywhere but in a browser, where it
// is `fetch` and the browser's WebSocket (same classes, same API).
export 'src/gateway.dart' if (dart.library.js_interop) 'src/gateway_web.dart';
export 'src/reconnect.dart';
