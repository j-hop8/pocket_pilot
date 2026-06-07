-- Income support. Records gain a `kind` ('expense' | 'income'); money stays stored
-- as positive cents and the sign is applied per kind at display/aggregation time, so
-- all existing rows (defaulting to 'expense') are unaffected. Categories also gain a
-- `kind` so income gets its own set, separate from the expense categories.
-- Idempotent — safe on `db push` and `db reset`.

ALTER TABLE invoices   ADD COLUMN IF NOT EXISTS kind VARCHAR(8) NOT NULL DEFAULT 'expense';
ALTER TABLE categories ADD COLUMN IF NOT EXISTS kind VARCHAR(8) NOT NULL DEFAULT 'expense';

CREATE INDEX IF NOT EXISTS idx_invoices_kind ON invoices(kind);

-- Income category set. `key` is UNIQUE and 'other' already exists as an expense
-- category, so income's catch-all is 'other_income'.
INSERT INTO categories (key, label, kind) VALUES
  ('salary',       'Salary 薪資',       'income'),
  ('bonus',        'Bonus 獎金',        'income'),
  ('investment',   'Investment 投資',   'income'),
  ('refund',       'Refund 退款',       'income'),
  ('gift',         'Gift 禮金',         'income'),
  ('other_income', 'Other income 其他收入', 'income')
ON CONFLICT (key) DO NOTHING;
