// Exposes [WebCameraView]: the real `getUserMedia` + capture implementation on
// the web, and a no-op stub elsewhere (it is only built behind `kIsWeb`).
export 'web_camera_view_stub.dart'
    if (dart.library.js_interop) 'web_camera_view_web.dart';
