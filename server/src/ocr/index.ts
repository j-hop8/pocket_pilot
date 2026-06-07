// OCR is wrapped behind this interface so callers (the scraper's CAPTCHA solver
// today, the receipt scanner in Phase 2) never depend on the engine. The only
// implementation today is Tesseract.js (./tesseract), per the open-source-OCR
// decision — but a different engine can be dropped in without touching callers.

export interface OcrService {
  /// Read a numeric image CAPTCHA, returning only the digit string (may be the
  /// wrong length on a misread — the caller shape-gates + retries).
  solveCaptcha(image: Buffer): Promise<string>;

  /// General text extraction from a document/receipt image (Phase 2: receipts).
  extractText(image: Buffer): Promise<string>;

  /// Release engine resources (Tesseract worker). Safe to call on shutdown.
  dispose(): Promise<void>;
}
