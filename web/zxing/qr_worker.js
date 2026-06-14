// Off-main-thread e-invoice QR decoder.
//
// Flutter web runs Dart on the one browser main thread, so the pure-Dart zxing
// pipeline freezes the UI while it grinds. This worker runs the WASM build of
// zxing (zxing-wasm) instead, so the JPEG decode + QR scan happen on a real
// background thread and the page (and the reading mascot) stay smooth.
//
// A *classic* worker loading the self-contained IIFE bundle via importScripts —
// no ES-module graph to vendor, and it works on any static host regardless of
// .mjs MIME handling.
//
// Protocol:
//   main → worker:  { id: number, bytes: ArrayBuffer }   (bytes transferred)
//   worker → main:  { id, payloads: [{ text, bytes: Uint8Array }] }
//                or  { id, error: string }
//
// We return each symbol's raw `bytes` as well as `text` so the Dart side can
// re-apply its Big5 recovery (MOF item names are often Big5, not UTF-8).

importScripts('zxing_reader.js'); // exposes the `ZXingWASM` global

ZXingWASM.setZXingModuleOverrides({
  // Resolve the .wasm next to this worker (base-href safe — works whether the
  // app is served from "/" or a sub-path).
  locateFile: (path, prefix) =>
    path.endsWith('.wasm')
      ? new URL('./zxing_reader.wasm', self.location.href).href
      : prefix + path,
});

self.onmessage = async (event) => {
  const { id, bytes } = event.data || {};
  try {
    const blob = new Blob([bytes]);
    // A 電子發票證明聯 carries two QRs side by side; readBarcodes returns every
    // symbol in one pass (zxing-wasm decodes the image file itself), so unlike
    // the single-pass Dart zxing we don't need to crop the halves ourselves.
    const results = await ZXingWASM.readBarcodes(blob, {
      formats: ['QRCode'],
      tryHarder: true,
      tryInvert: true,
      maxNumberOfSymbols: 4,
    });
    const payloads = [];
    for (const r of results) {
      if (r && r.bytes && r.bytes.length) {
        payloads.push({ text: r.text || '', bytes: r.bytes });
      }
    }
    self.postMessage({ id, payloads });
  } catch (err) {
    self.postMessage({ id, error: String((err && err.message) || err) });
  }
};
