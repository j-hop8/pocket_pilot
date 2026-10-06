# T-004: AI fallback when an e-invoice QR can't be read

**Goal:** When a photographed 電子發票證明聯's QR can't be decoded, read the receipt with
the existing AI receipt extractor instead of failing silently, and make failed scan
rows say why.

**Background:** A real TSUTAYA receipt (FM-02316916) fails on photo import: its dense
left QR is printed with half-density/dithered modules that blur to grey in a photo,
so BarcodeDetector, zxing-wasm (all binarizers) and pure-Dart zxing all fail the
Reed-Solomon check; the right QR is just `**`. The job ends `failed` with no message
and a "讀取中…" label. The printed invoice number / date / total are legible, so the
Gemini `extract-receipt` path (already used by the 收據 tab) can read it.

**Files in scope:** `lib/features/scan/scan_queue.dart`,
`lib/features/scan/scan_progress_overlay.dart`, `lib/core/strings.dart`,
`test/einvoice_ai_fallback_test.dart` (new), this ticket.

**Do NOT touch:** the QR decode pipeline itself, the Edge Function, DB schema.

**Acceptance criteria:**
- [x] Photo e-invoice job with no decodable QR falls back to AI extraction and saves
      (same dedup on invoice number, stored as editable `ocr`)
- [x] A readable QR never calls the AI extractor (no quota spent)
- [x] Fallback failure → failed row with a clear "QR unreadable" message; daily-cap →
      a message that says both
- [x] Failed rows with nothing parsed show "讀取失敗" / "Couldn't read", not "讀取中…"
- [x] Unit tests cover fallback success, failure, limit, and the no-fallback case

**Verify:** `flutter analyze && flutter test`

**Owner:** claude
