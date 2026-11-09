-- ==============================================================================
-- SCHEMA REKAPAN BAHAN SUPABASE (LENGKAP & BERSIH)
-- ==============================================================================

-- 1. Hapus tabel lama yang tidak digunakan
DROP TABLE IF EXISTS public.transactions CASCADE;
DROP TABLE IF EXISTS public.events CASCADE;
DROP TABLE IF EXISTS public.event_material_catalog CASCADE;
DROP TABLE IF EXISTS public.employees CASCADE;
DROP TABLE IF EXISTS public.payroll CASCADE;
DROP TABLE IF EXISTS public.payroll_daily CASCADE;
DROP TABLE IF EXISTS public.payroll_advances CASCADE;
DROP TABLE IF EXISTS public.payroll_monthly_payments CASCADE;

-- 2. Hapus fungsi lama
DROP FUNCTION IF EXISTS public.can_manage_event_inventory(text) CASCADE;
DROP FUNCTION IF EXISTS public.can_access_event(text) CASCADE;
DROP FUNCTION IF EXISTS public.current_user_event() CASCADE;
DROP FUNCTION IF EXISTS public.is_event_employee() CASCADE;

-- 3. Tabel Profil Pengguna & Hak Akses
CREATE TABLE IF NOT EXISTS public.profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  role text NOT NULL DEFAULT 'admin',
  branch text,
  branches text[] NOT NULL DEFAULT '{}'::text[],
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 4. Tabel Toko & Cabang
CREATE TABLE IF NOT EXISTS public.stores (
  id text PRIMARY KEY,
  name text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.stores (id, name) VALUES
  ('chickumbar-blok-m', 'Chickumbar Blok M'),
  ('susu-sore', 'Susu Sore'),
  ('hi-fruit', 'Hi Fruit'),
  ('ngayamin', 'Ngayamin'),
  ('chickumbar-barito', 'Chickumbar Barito')
ON CONFLICT (name) DO NOTHING;

-- 5. Tabel Daftar Bahan (Master Inventory)
CREATE TABLE IF NOT EXISTS public.inventory (
  id text PRIMARY KEY,
  store text NOT NULL,
  name text NOT NULL,
  unit text NOT NULL,
  stock numeric(15,2) NOT NULL DEFAULT 0,
  min_stock numeric(15,2) NOT NULL DEFAULT 0,
  price numeric(15,2) NOT NULL DEFAULT 0,
  note text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now(),
  event_id text,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

-- 6. Tabel Rekapan Bahan Harian (Closing Inventory)
CREATE TABLE IF NOT EXISTS public.inventory_daily (
  id text PRIMARY KEY,
  inventory_id text REFERENCES public.inventory(id) ON DELETE SET NULL,
  store text NOT NULL,
  record_date date NOT NULL,
  name text NOT NULL,
  unit text NOT NULL,
  opening_stock numeric(15,2) NOT NULL DEFAULT 0,
  stock_in numeric(15,2) NOT NULL DEFAULT 0,
  closing_stock numeric(15,2),
  used_stock numeric(15,2) NOT NULL DEFAULT 0,
  note text NOT NULL DEFAULT '',
  is_closed boolean NOT NULL DEFAULT false,
  closed_at timestamptz,
  closed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  event_id text,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS inventory_daily_inventory_date_uidx
  ON public.inventory_daily(inventory_id, record_date)
  WHERE inventory_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS inventory_daily_store_date_idx
  ON public.inventory_daily(store, record_date);

-- Hapus seluruh check constraint kaku & kolom scope lama pada inventory
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_store_check CASCADE;
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_scope_check CASCADE;
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_event_id_fkey CASCADE;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS scope CASCADE;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS event_id text;

ALTER TABLE public.inventory_daily DROP CONSTRAINT IF EXISTS inventory_daily_store_check CASCADE;
ALTER TABLE public.inventory_daily DROP CONSTRAINT IF EXISTS inventory_daily_scope_check CASCADE;
ALTER TABLE public.inventory_daily DROP CONSTRAINT IF EXISTS inventory_daily_event_id_fkey CASCADE;
ALTER TABLE public.inventory_daily DROP COLUMN IF EXISTS scope CASCADE;
ALTER TABLE public.inventory_daily ADD COLUMN IF NOT EXISTS event_id text;

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT tc.table_schema, tc.table_name, tc.constraint_name
    FROM information_schema.table_constraints tc
    WHERE tc.table_schema = 'public'
      AND tc.constraint_type = 'CHECK'
      AND (
        tc.constraint_name ILIKE '%scope%'
        OR tc.constraint_name ILIKE '%store%'
        OR tc.constraint_name ILIKE '%branch%'
      )
  ) LOOP
    EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I CASCADE', r.table_schema, r.table_name, r.constraint_name);
  END LOOP;
END $$;

-- 7. View soft-delete untuk panel Sampah
CREATE OR REPLACE VIEW public.deleted_items AS
SELECT 'inventory' AS table_name, id, deleted_at, deleted_by, coalesce(store,'') AS store, coalesce(name,'Bahan') AS title, coalesce(note,'') AS detail FROM public.inventory WHERE deleted_at IS NOT NULL
UNION ALL SELECT 'inventory_daily', id, deleted_at, deleted_by, coalesce(store,''), coalesce(name,'Closing Bahan'), coalesce(note,'') FROM public.inventory_daily WHERE deleted_at IS NOT NULL;

-- 8. Fungsi Security & Operasional
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT role = 'admin' FROM public.profiles WHERE user_id = auth.uid() LIMIT 1),
    true
  );
$$;

CREATE OR REPLACE FUNCTION public.is_owner()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT role = 'owner' FROM public.profiles WHERE user_id = auth.uid() LIMIT 1),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.can_view_all()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT true;
$$;

CREATE OR REPLACE FUNCTION public.can_access_store(target_store text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT true;
$$;

CREATE OR REPLACE FUNCTION public.can_manage_inventory(target_store text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT true;
$$;

CREATE OR REPLACE FUNCTION public.update_inventory_stock_after_closing(
  target_inventory_id text,
  new_stock numeric,
  target_updated_at timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF new_stock IS NULL OR new_stock < 0 THEN
    RAISE EXCEPTION 'Stok tidak valid';
  END IF;

  UPDATE public.inventory
  SET stock = new_stock,
      updated_at = COALESCE(target_updated_at, now())
  WHERE id = target_inventory_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_soft_deleted(target_table text, target_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF target_table = 'inventory' THEN
    UPDATE public.inventory SET deleted_at = NULL, deleted_by = NULL WHERE id = target_id;
  ELSIF target_table = 'inventory_daily' THEN
    UPDATE public.inventory_daily SET deleted_at = NULL, deleted_by = NULL WHERE id = target_id;
  END IF;
END;
$$;

-- 9. Soft Delete & Audit Tables
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action text NOT NULL,
  table_name text NOT NULL,
  record_id text NOT NULL,
  store text,
  performed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 10. Row Level Security & Policies Terbuka (authenticated & anon)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Stores readable by authenticated" ON public.stores;
DROP POLICY IF EXISTS "Stores manageable by admin" ON public.stores;
DROP POLICY IF EXISTS "Stores manageable by authenticated" ON public.stores;
DROP POLICY IF EXISTS "Stores all access" ON public.stores;
CREATE POLICY "Stores all access" ON public.stores FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Profiles readable by authenticated" ON public.profiles;
DROP POLICY IF EXISTS "Profiles manageable by admin" ON public.profiles;
DROP POLICY IF EXISTS "Profiles manageable by authenticated" ON public.profiles;
DROP POLICY IF EXISTS "Profiles all access" ON public.profiles;
CREATE POLICY "Profiles all access" ON public.profiles FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Inventory readable by access" ON public.inventory;
DROP POLICY IF EXISTS "Inventory readable by all authenticated" ON public.inventory;
DROP POLICY IF EXISTS "Inventory manageable by admin" ON public.inventory;
DROP POLICY IF EXISTS "Inventory manageable" ON public.inventory;
DROP POLICY IF EXISTS "Inventory manageable by all authenticated" ON public.inventory;
DROP POLICY IF EXISTS "Inventory all access" ON public.inventory;
CREATE POLICY "Inventory all access" ON public.inventory FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Daily inventory readable by access" ON public.inventory_daily;
DROP POLICY IF EXISTS "Daily inventory manageable" ON public.inventory_daily;
DROP POLICY IF EXISTS "Daily inventory all access" ON public.inventory_daily;
CREATE POLICY "Daily inventory all access" ON public.inventory_daily FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Audit logs readable by admin" ON public.audit_logs;
DROP POLICY IF EXISTS "Audit logs all access" ON public.audit_logs;
CREATE POLICY "Audit logs all access" ON public.audit_logs FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);

-- 11. Grant Permissions penuh
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO authenticated, anon;
GRANT SELECT ON public.deleted_items TO authenticated, anon;

-- 12. Aktifkan Supabase Realtime
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.stores;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.inventory;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.inventory_daily;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

NOTIFY pgrst, 'reload schema';
