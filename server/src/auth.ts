// Resolves the Supabase user id from a request's Bearer token by asking Supabase
// to validate it (same approach as the old Edge Function's userIdFromJwt). Simple
// and correct; can be swapped for local JWKS verification later if it shows up in
// latency.

import type { FastifyRequest } from "fastify";
import { clientForToken } from "./supabase";

export function bearerToken(req: FastifyRequest): string | null {
  const header = req.headers["authorization"];
  if (!header || Array.isArray(header)) return null;
  const m = header.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

/// Resolves both the user id and whether the session is an anonymous ("demo")
/// account from a Bearer token. Returns null when the token is invalid. Demo
/// users are blocked from carrier sync (they have no portal credentials and we
/// don't want them logging into the gov portal), so callers check `isAnonymous`.
export async function userFromToken(
  token: string,
): Promise<{ id: string; isAnonymous: boolean } | null> {
  const { data, error } = await clientForToken(token).auth.getUser();
  if (error || !data.user) return null;
  return { id: data.user.id, isAnonymous: data.user.is_anonymous === true };
}
