-- Recurring monthly budgets: an optional overall cap plus per-expense-category
-- limits. A budget is set once and compared against the spending of whichever
-- month the dashboard is showing (no per-month rows). Same per-user ownership
-- pattern as categories (see 20260607000009_user_categories).
-- Idempotent — safe on `db push` and `db reset`.

CREATE TABLE IF NOT EXISTS budgets (
  id          SERIAL PRIMARY KEY,
  -- DEFAULT auth.uid() lets inserts self-fill the owner from the JWT.
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE DEFAULT auth.uid(),
  -- NULL = the overall budget. ON DELETE CASCADE (not SET NULL): deleting a
  -- category drops its budget, and NULL is reserved to mean "overall".
  category_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
  amount      INTEGER NOT NULL CHECK (amount > 0),  -- monthly limit, TWD cents
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- One budget per category, and a single overall (NULL category) budget per user.
-- Partial indexes because a plain UNIQUE(user_id, category_id) treats NULLs as
-- distinct, which would allow multiple overall budgets.
CREATE UNIQUE INDEX IF NOT EXISTS budgets_user_category
  ON budgets(user_id, category_id) WHERE category_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS budgets_user_overall
  ON budgets(user_id) WHERE category_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_budgets_user ON budgets(user_id);

-- RLS: each user sees and manages only their own budgets.
ALTER TABLE budgets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "own budgets" ON budgets;
CREATE POLICY "own budgets" ON budgets
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
