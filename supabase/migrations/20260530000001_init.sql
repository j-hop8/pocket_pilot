-- PocketPilot schema (spec §4). Implements the four core tables + indexes.
-- gen_random_uuid() is built into Supabase Postgres (pgcrypto preloaded).

-- Categories reference table
CREATE TABLE categories (
  id    SERIAL PRIMARY KEY,
  key   VARCHAR(32) UNIQUE NOT NULL,   -- 'groceries', 'dining', etc.
  label VARCHAR(64) NOT NULL           -- 'Groceries 超市'
);

-- Invoice headers
CREATE TABLE invoices (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number VARCHAR(10) UNIQUE,   -- e.g. AA00000000 (null for OCR receipts)
  invoice_date   DATE NOT NULL,
  merchant_name  VARCHAR(255),
  seller_tax_id  VARCHAR(8),
  buyer_tax_id   VARCHAR(8),
  sales_amount   INTEGER,              -- pre-tax, TWD cents
  total_amount   INTEGER NOT NULL,     -- TWD cents
  currency       VARCHAR(3) DEFAULT 'TWD',
  category_id    INTEGER REFERENCES categories(id),
  source         VARCHAR(16) NOT NULL, -- 'carrier' | 'qr_scan' | 'ocr' | 'manual'
  raw_payload    JSONB,                -- original decoded data for re-parsing
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Line items
CREATE TABLE invoice_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id  UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  name        VARCHAR(255) NOT NULL,
  quantity    NUMERIC(10,3) DEFAULT 1,
  unit_price  INTEGER,                 -- TWD cents
  amount      INTEGER NOT NULL,        -- TWD cents
  category_id INTEGER REFERENCES categories(id),
  sort_order  SMALLINT DEFAULT 0
);

-- Carrier credentials (stored for future real API use)
CREATE TABLE carrier_config (
  id              SERIAL PRIMARY KEY,
  carrier_id      VARCHAR(16),         -- /XXXXXXX
  last_synced_at  TIMESTAMPTZ,
  last_sync_count INTEGER DEFAULT 0
);

-- Indexes
CREATE INDEX idx_invoices_date    ON invoices(invoice_date DESC);
CREATE INDEX idx_invoices_source  ON invoices(source);
CREATE INDEX idx_items_invoice_id ON invoice_items(invoice_id);
CREATE INDEX idx_items_category   ON invoice_items(category_id);
