// A resilient wrapper around Node's global `fetch` for the Supabase clients.
//
// Node's fetch (undici) pools keep-alive sockets. During a carrier sync the
// admin client makes a few quick calls, then `downloadCarrierCsv` runs for 1-3
// min making NO Supabase requests. Supabase's edge (Cloudflare/Kong) closes the
// now-idle socket; the next call (`ingestCsv`'s first select) reuses the dead
// socket and undici throws the opaque `TypeError: fetch failed`
// (cause: UND_ERR_SOCKET, "other side closed"). The longer the scrape — i.e. the
// more pages — the likelier the socket is already gone. A bounded retry just
// opens a fresh connection and succeeds. We also retry transient HTTP statuses,
// and bound each attempt with a timeout so a genuinely hung request fails fast
// and retries instead of stalling the whole sync.

// Transient server/proxy responses worth one more attempt on a fresh connection.
const RETRYABLE_STATUS = new Set([408, 429, 502, 503, 504]);

export interface ResilientFetchOptions {
  /// Extra attempts after the first (so total tries = retries + 1). Default 2.
  retries?: number;
  /// Per-attempt deadline in ms (via AbortSignal.timeout). Default 30_000.
  timeoutMs?: number;
  /// Backoff unit in ms; delay before attempt N is baseDelayMs * N. Default 250.
  baseDelayMs?: number;
}

/// Builds a `fetch`-compatible function with retry + per-attempt timeout.
export function makeResilientFetch(
  opts: ResilientFetchOptions = {},
): typeof fetch {
  const retries = opts.retries ?? 2;
  const timeoutMs = opts.timeoutMs ?? 30_000;
  const baseDelayMs = opts.baseDelayMs ?? 250;

  const resilientFetch = async (
    input: Parameters<typeof fetch>[0],
    init?: Parameters<typeof fetch>[1],
  ): Promise<Response> => {
    const callerSignal = init?.signal ?? undefined;
    let lastErr: unknown;

    for (let attempt = 0; attempt <= retries; attempt++) {
      // Honour caller cancellation between attempts.
      if (callerSignal?.aborted) {
        throw callerSignal.reason ?? new DOMException("Aborted", "AbortError");
      }

      // Each attempt gets its own deadline; combine with the caller's signal so
      // an explicit cancel still propagates.
      const timeout = AbortSignal.timeout(timeoutMs);
      const signal = callerSignal
        ? AbortSignal.any([callerSignal, timeout])
        : timeout;

      try {
        const res = await fetch(input, { ...init, signal });
        if (RETRYABLE_STATUS.has(res.status) && attempt < retries) {
          // Drain so the dead connection can be reclaimed, then back off.
          await res.body?.cancel().catch(() => {});
          await delay(baseDelayMs * (attempt + 1));
          continue;
        }
        return res;
      } catch (err) {
        lastErr = err;
        // A caller-initiated cancel is final — never retry it.
        if (callerSignal?.aborted) throw err;
        if (attempt < retries) {
          await delay(baseDelayMs * (attempt + 1));
          continue;
        }
        throw err;
      }
    }
    // Unreachable (the loop returns or throws), but satisfies the type checker.
    throw lastErr;
  };

  return resilientFetch as typeof fetch;
}

/// The shared default instance used by the Supabase clients.
export const resilientFetch = makeResilientFetch();

/// Renders an error with its underlying cause/code so persisted sync failures
/// say *why* — e.g. `fetch failed (UND_ERR_SOCKET: other side closed)` instead
/// of the bare `fetch failed`.
export function describeError(e: unknown): string {
  if (!(e instanceof Error)) return String(e);
  const cause = (e as { cause?: unknown }).cause;
  if (cause instanceof Error) {
    const code = (cause as { code?: unknown }).code;
    const detail = code ? `${String(code)}: ${cause.message}` : cause.message;
    return detail && detail !== e.message ? `${e.message} (${detail})` : e.message;
  }
  if (cause != null) {
    const s = String(cause);
    return s && s !== e.message ? `${e.message} (${s})` : e.message;
  }
  return e.message;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
