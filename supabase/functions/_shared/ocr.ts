// Reusable OCR via Google Gemini vision API (free tier: 1,500 req/day).
//
// Use extractText() for general document/receipt/e-invoice reading.
// Use solveCaptcha() for numeric image CAPTCHAs.
//
// Requires GOOGLE_AI_API_KEY to be set as a Supabase secret.

import { GoogleGenerativeAI } from "npm:@google/generative-ai";

type ImageMediaType = "image/png" | "image/jpeg" | "image/gif" | "image/webp";

/// Extract text from an image using Gemini vision.
/// [imageBase64] is the raw bytes encoded as base64.
/// [prompt] describes what to extract (e.g. "read the total amount").
export async function extractText(
  imageBase64: string,
  prompt: string,
  mediaType: ImageMediaType = "image/png",
): Promise<string> {
  const genAI = new GoogleGenerativeAI(Deno.env.get("GOOGLE_AI_API_KEY")!);
  const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
  const result = await model.generateContent([
    { inlineData: { data: imageBase64, mimeType: mediaType } },
    prompt,
  ]);
  return result.response.text().trim();
}

/// Solve a numeric image CAPTCHA. Returns only the digit string.
export async function solveCaptcha(
  imageBase64: string,
  mediaType: ImageMediaType = "image/png",
): Promise<string> {
  const answer = await extractText(
    imageBase64,
    "This is a CAPTCHA image containing only digits. Reply with ONLY the digits — no spaces, no explanation.",
    mediaType,
  );
  return answer.replace(/\D/g, "");
}
