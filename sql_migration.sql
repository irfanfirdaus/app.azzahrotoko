-- ============================================================
-- SQL MIGRATION: Sistem Loyalitas Pelanggan - Toko Azzahro
-- Jalankan di Supabase Dashboard > SQL Editor
-- ============================================================

-- 1. Tambah kolom ke tabel customers
ALTER TABLE customers 
  ADD COLUMN IF NOT EXISTS customer_code TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS points INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS identity_type TEXT,
  ADD COLUMN IF NOT EXISTS identity_number TEXT,
  ADD COLUMN IF NOT EXISTS birthplace TEXT;

-- 2. Tambah kolom ke tabel transactions
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS points_earned INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS points_redeemed INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS redeem_discount INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS notes_tx TEXT;

-- 2b. Tambah kolom baru ke tabel products
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS sub_category TEXT,
  ADD COLUMN IF NOT EXISTS promo_price INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS promo_percentage INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS etalase TEXT,
  ADD COLUMN IF NOT EXISTS is_po BOOLEAN NOT NULL DEFAULT FALSE;

-- 3. Buat tabel point_ledger (riwayat poin)
CREATE TABLE IF NOT EXISTS point_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id BIGINT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  transaction_id BIGINT REFERENCES transactions(id) ON DELETE SET NULL,
  type TEXT NOT NULL CHECK (type IN ('earn', 'redeem', 'redeem_discount', 'adjustment')),
  points INTEGER NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index untuk performa query per pelanggan
CREATE INDEX IF NOT EXISTS idx_point_ledger_customer_id ON point_ledger(customer_id);
CREATE INDEX IF NOT EXISTS idx_point_ledger_created_at ON point_ledger(created_at);

-- 4. Settings baru untuk sistem poin
-- (Diinsert via upsert, aman dijalankan berulang)
INSERT INTO settings (key, value) VALUES
  ('points_per_10k', '1'),
  ('points_to_rupiah', '100'),
  ('min_redeem_points', '50'),
  ('points_expire_months', '0')
ON CONFLICT (key) DO NOTHING;

-- 5. RPC: Generate customer_code otomatis
-- Format: AZR-YYMMDD-NNNN (urutan harian)
CREATE OR REPLACE FUNCTION generate_customer_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  today_str TEXT;
  seq_num   INTEGER;
  code      TEXT;
BEGIN
  today_str := TO_CHAR(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYMMDD');
  
  SELECT COUNT(*) + 1 INTO seq_num
  FROM customers
  WHERE customer_code LIKE 'AZR-' || today_str || '-%';
  
  code := 'AZR-' || today_str || '-' || LPAD(seq_num::TEXT, 4, '0');
  RETURN code;
END;
$$;

-- 6. RPC: Tambah poin ke pelanggan + catat ke ledger
-- Hapus versi lama jika ada untuk menghindari konflik tipe data (BigInt vs UUID)
DROP FUNCTION IF EXISTS add_customer_points(bigint, integer, text, bigint, text);
DROP FUNCTION IF EXISTS add_customer_points(uuid, integer, text, uuid, text);

CREATE OR REPLACE FUNCTION add_customer_points(
  p_customer_id BIGINT,
  p_points INTEGER,
  p_type TEXT,
  p_transaction_id BIGINT DEFAULT NULL,
  p_note TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update saldo poin di tabel customers
  UPDATE customers
  SET points = COALESCE(points, 0) + p_points
  WHERE id = p_customer_id;

  -- Catat ke ledger
  INSERT INTO point_ledger (customer_id, transaction_id, type, points, note)
  VALUES (p_customer_id, p_transaction_id, p_type, p_points, p_note);
END;
$$;

-- 7. Tabel Pesanan Online (Integrasi Katalog ke Kasir)
CREATE TABLE IF NOT EXISTS online_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_code TEXT UNIQUE NOT NULL,
  customer_name TEXT,
  customer_type TEXT DEFAULT 'Umum',
  customer_id_input TEXT,
  shipping_method TEXT DEFAULT 'pickup',
  items_json JSONB NOT NULL,
  total_amount INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processed', 'cancelled')),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Kebijakan RLS untuk online_orders
ALTER TABLE online_orders ENABLE ROW LEVEL SECURITY;

-- Izinkan siapa saja (anon) untuk membuat pesanan
DROP POLICY IF EXISTS "Enable insert for everyone" ON online_orders;
CREATE POLICY "Enable insert for everyone" ON online_orders FOR INSERT WITH CHECK (true);

-- Izinkan siapa saja (anon) untuk melihat pesanan (agar kasir bisa load data)
DROP POLICY IF EXISTS "Enable select for everyone" ON online_orders;
CREATE POLICY "Enable select for everyone" ON online_orders FOR SELECT USING (true);

-- Izinkan siapa saja (anon) untuk update (untuk ganti status ke processed)
DROP POLICY IF EXISTS "Enable update for everyone" ON online_orders;
CREATE POLICY "Enable update for everyone" ON online_orders FOR UPDATE USING (true);


-- ============================================================
-- SELESAI! Kembalikan ke aplikasi setelah menjalankan ini.
-- ============================================================
