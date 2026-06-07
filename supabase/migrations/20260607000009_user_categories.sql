-- Per-user, user-editable categories.
-- Categories stop being shared reference data and become per-user owned (same
-- pattern as invoices, see 20260531000005_auth_per_user). Each user gets their
-- own copy of the defaults so they can rename / restyle / delete them, and can
-- add their own. Custom appearance (icon + color) is stored on the row; built-in
-- rows leave icon/color NULL and fall back to the in-app style map keyed by `key`.
-- Idempotent — safe on `db push` and `db reset`.

-- 1. Ownership + appearance columns. DEFAULT auth.uid() lets inserts self-fill
--    the owner from the JWT (no app change needed for the WITH CHECK).
ALTER TABLE categories ADD COLUMN IF NOT EXISTS user_id UUID
  REFERENCES auth.users(id) ON DELETE CASCADE DEFAULT auth.uid();
ALTER TABLE categories ADD COLUMN IF NOT EXISTS icon  TEXT;  -- icon name; NULL = use code map
ALTER TABLE categories ADD COLUMN IF NOT EXISTS color TEXT;  -- '#RRGGBB'; NULL = use code map

-- 2. `key` is unique per user now, not globally (two users can both have 'groceries').
ALTER TABLE categories DROP CONSTRAINT IF EXISTS categories_key_key;
CREATE UNIQUE INDEX IF NOT EXISTS categories_user_key ON categories(user_id, key);

-- 3. Deleting a category that past records use must not fail: null the references
--    (the UI renders a null category as "Uncategorized").
ALTER TABLE invoices      DROP CONSTRAINT IF EXISTS invoices_category_id_fkey;
ALTER TABLE invoices      ADD  CONSTRAINT invoices_category_id_fkey
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;
ALTER TABLE invoice_items DROP CONSTRAINT IF EXISTS invoice_items_category_id_fkey;
ALTER TABLE invoice_items ADD  CONSTRAINT invoice_items_category_id_fkey
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;

-- 4. Migrate existing shared rows (user_id IS NULL) into per-user copies and
--    repoint each user's invoices/items, then drop the shared rows. With the FK
--    now ON DELETE SET NULL, any straggler references self-clear instead of
--    blocking the delete.
DO $$
DECLARE
  u       RECORD;
  c       RECORD;
  new_id  INTEGER;
BEGIN
  IF EXISTS (SELECT 1 FROM categories WHERE user_id IS NULL) THEN
    FOR u IN SELECT id FROM auth.users LOOP
      FOR c IN SELECT id, key, label, kind FROM categories WHERE user_id IS NULL LOOP
        INSERT INTO categories (key, label, kind, user_id)
        VALUES (c.key, c.label, c.kind, u.id)
        RETURNING id INTO new_id;

        UPDATE invoices      SET category_id = new_id
          WHERE user_id = u.id AND category_id = c.id;
        UPDATE invoice_items SET category_id = new_id
          WHERE user_id = u.id AND category_id = c.id;
      END LOOP;
    END LOOP;

    DELETE FROM categories WHERE user_id IS NULL;
  END IF;
END $$;

-- 5. RLS: each user sees and manages only their own categories. Replaces the
--    read-only "categories readable" policy from the auth migration.
DROP POLICY IF EXISTS "categories readable" ON categories;
DROP POLICY IF EXISTS "demo all access"     ON categories;
CREATE POLICY "own categories" ON categories
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
