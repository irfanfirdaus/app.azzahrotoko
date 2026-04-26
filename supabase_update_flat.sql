-- MIGRASI KE STRUKTUR FLAT (Opsi 1)
-- Menghapus data lama (Opsional, tapi disarankan agar tidak konflik)
-- TRUNCATE TABLE products;

-- 1. Tambah kolom pendukung grouping
ALTER TABLE products ADD COLUMN IF NOT EXISTS parent_sku TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS variant_name TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_parent BOOLEAN DEFAULT FALSE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS variant_options JSONB DEFAULT '[]';

-- 2. Update RPC decrement_stock agar lebih simpel (berdasarkan SKU)
-- Kita tidak lagi butuh decrement_variant_stock (JSONB)
CREATE OR REPLACE FUNCTION decrement_stock_by_sku(p_sku TEXT, p_qty INT)
RETURNS VOID AS $$
BEGIN
  UPDATE products
  SET stock = stock - p_qty
  WHERE sku = p_sku;
END;
$$ LANGUAGE plpgsql;

-- 3. Indeks untuk performa grouping
CREATE INDEX IF NOT EXISTS idx_products_parent_sku ON products(parent_sku);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);

-- 4. Status Pembayaran
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'Completed';
