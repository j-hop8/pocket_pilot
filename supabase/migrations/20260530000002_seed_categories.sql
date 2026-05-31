-- Seed the v1 category enum (spec: AI Auto-Categorization). Idempotent.
INSERT INTO categories (key, label) VALUES
  ('groceries',     'Groceries 超市'),
  ('dining',        'Dining 餐飲'),
  ('transport',     'Transport 交通'),
  ('entertainment', 'Entertainment 娛樂'),
  ('health',        'Health 醫療健康'),
  ('utilities',     'Utilities 水電費'),
  ('shopping',      'Shopping 購物'),
  ('education',     'Education 教育'),
  ('travel',        'Travel 旅遊'),
  ('other',         'Other 其他')
ON CONFLICT (key) DO NOTHING;
