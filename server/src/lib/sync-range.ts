// Computes the date range each carrier sync should request, so we fetch only
// what's new instead of the portal's whole-current-month default (which grows
// all month). Anchored at the last *successful* sync minus an overlap buffer
// (dedupe makes the re-fetch a safe no-op and catches late-arriving invoices);
// the first-ever sync uses a lookback window.
//
// Dates are civil (calendar) dates in Asia/Taipei — the portal's timezone and
// the tz the scrape context pins — represented as {year, month, day} so the
// datepicker navigation in scrape.ts is unambiguous.

const TAIPEI = "Asia/Taipei";

export interface CivilDate {
  year: number;
  month: number; // 1-12
  day: number; // 1-31
}

export interface SyncRange {
  from: CivilDate;
  to: CivilDate;
}

export interface SyncRangeOptions {
  overlapDays: number;
  lookbackDays: number;
}

export function computeSyncRange(
  lastSyncedAt: Date | null,
  now: Date,
  opts: SyncRangeOptions,
): SyncRange {
  const to = toTaipeiCivil(now);
  const from = lastSyncedAt
    ? minusDays(toTaipeiCivil(lastSyncedAt), opts.overlapDays)
    : minusDays(to, opts.lookbackDays);
  return { from, to };
}

/// Whole-month distance from `a` to `b` (positive if `b` is later). Used to
/// page a month-navigating datepicker by arrow clicks rather than reading its
/// (possibly ROC-formatted) header.
export function monthDelta(a: CivilDate, b: CivilDate): number {
  return (b.year - a.year) * 12 + (b.month - a.month);
}

function toTaipeiCivil(d: Date): CivilDate {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: TAIPEI,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(d);
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value);
  return { year: get("year"), month: get("month"), day: get("day") };
}

// Day arithmetic via a UTC instant at the civil date's midnight — Taiwan has no
// DST, so this is exact and free of timezone drift.
function minusDays(c: CivilDate, days: number): CivilDate {
  const d = new Date(Date.UTC(c.year, c.month - 1, c.day));
  d.setUTCDate(d.getUTCDate() - days);
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() };
}
