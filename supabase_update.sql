-- 1. Tambah kolom ke tabel products (jika belum ada)
ALTER TABLE products ADD COLUMN IF NOT EXISTS cost_price NUMERIC DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS weight NUMERIC DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS weight_unit TEXT DEFAULT 'g';

-- 2. Fungsi RPC untuk update stok produk biasa
CREATE OR REPLACE FUNCTION decrement_stock(p_id BIGINT, p_qty INT)
RETURNS VOID AS $$
BEGIN
  UPDATE products
  SET stock = stock - p_qty
  WHERE id = p_id;
END;
$$ LANGUAGE plpgsql;

-- 3. Fungsi RPC untuk update stok dalam JSONB variants
CREATE OR REPLACE FUNCTION decrement_variant_stock(p_id BIGINT, v_name TEXT, p_qty INT)
RETURNS VOID AS $$
BEGIN
  UPDATE products
  SET variants = (
    SELECT jsonb_agg(
      CASE 
        WHEN (elem->>'name') = v_name 
        THEN elem || jsonb_build_object('stock', (elem->>'stock')::int - p_qty)
        ELSE elem 
      END
    )
    FROM jsonb_array_elements(variants) AS elem
  )
  WHERE id = p_id;
END;
$$ LANGUAGE plpgsql;
