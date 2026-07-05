-- Travel feature: trips, multi-currency receipt fields, and an FX-rate cache.
--
-- A trip carries a date range + destination currency. While a trip is active,
-- scanned receipts are read in the local currency, converted to TWD (the home
-- currency every dashboard/budget sums) at the day's rate, and the original
-- amount / currency / rate are kept alongside. The extractor also returns
-- translations of the merchant + item names into the user's app language.
--
-- Idempotent so it is safe on `db push` / `db reset`.

-- 1. Trips — per-user, owned via DEFAULT auth.uid() (same pattern as invoices,
--    so inserts need no extra app columns: the column self-fills from the JWT
--    before the RLS WITH CHECK runs).
CREATE TABLE IF NOT EXISTS trips (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
                  DEFAULT auth.uid(),
  name          VARCHAR(255) NOT NULL,
  country_code  VARCHAR(2)  NOT NULL,   -- ISO 3166-1 alpha-2, e.g. 'JP'
  currency_code VARCHAR(3)  NOT NULL,   -- ISO 4217, e.g. 'JPY'
  start_date    DATE NOT NULL,
  end_date      DATE NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trips_user  ON trips(user_id);
CREATE INDEX IF NOT EXISTS idx_trips_dates ON trips(user_id, start_date, end_date);

ALTER TABLE trips ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own trips" ON trips;
CREATE POLICY "own trips" ON trips
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- 2. Multi-currency + translation columns on invoices/items. All nullable so
--    existing rows and the domestic scan path are untouched: `total_amount`
--    stays TWD cents (converted) and `currency` stays 'TWD', keeping every
--    existing aggregation correct. The foreign figures live in the new columns.
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS trip_id UUID REFERENCES trips(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS original_amount INTEGER,        -- foreign minor units (×100 fixed point)
  ADD COLUMN IF NOT EXISTS original_currency VARCHAR(3),    -- e.g. 'JPY'; null when TWD
  ADD COLUMN IF NOT EXISTS fx_rate NUMERIC(18,6),          -- foreign → TWD rate actually used
  ADD COLUMN IF NOT EXISTS merchant_name_translated VARCHAR(255);

CREATE INDEX IF NOT EXISTS idx_invoices_trip ON invoices(trip_id);

ALTER TABLE invoice_items
  ADD COLUMN IF NOT EXISTS name_translated VARCHAR(255);

-- 3. FX-rate cache — shared reference data written only by the exchange-rate
--    Edge Function (service role, which bypasses RLS, mirroring how
--    global_extraction_usage is touched). Any signed-in user may read it.
--    `rate` is `base → quote` on `rate_date` (e.g. base=JPY, quote=TWD).
CREATE TABLE IF NOT EXISTS fx_rates (
  base       VARCHAR(3) NOT NULL,
  quote      VARCHAR(3) NOT NULL,
  rate_date  DATE NOT NULL,
  rate       NUMERIC(18,6) NOT NULL,
  fetched_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (base, quote, rate_date)
);

ALTER TABLE fx_rates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fx_rates readable" ON fx_rates;
CREATE POLICY "fx_rates readable" ON fx_rates
  FOR SELECT TO authenticated USING (true);
