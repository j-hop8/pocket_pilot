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

export async function userIdFromToken(token: string): Promise<string | null> {
  const { data, error } = await clientForToken(token).auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}
