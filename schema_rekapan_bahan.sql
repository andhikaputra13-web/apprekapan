-- ==============================================================================
-- SCHEMA SUPABASE: SISTEM OPERASIONAL REKAPAN BAHAN
-- (Dashboard, Rekapan Bahan, Daftar Bahan, Data & Pengaturan)
-- Jalankan di Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ==============================================================================

-- 1. Hapus tabel-tabel lama yang tidak digunakan lagi (Pemasukan/Pengeluaran, Event, Gaji Karyawan)
DROP TABLE IF EXISTS public.transactions CASCADE;
DROP TABLE IF EXISTS public.events CASCADE;
DROP TABLE IF EXISTS public.event_material_catalog CASCADE;
DROP TABLE IF EXISTS public.employees CASCADE;
DROP TABLE IF EXISTS public.payroll CASCADE;
DROP TABLE IF EXISTS public.payroll_daily CASCADE;
DROP TABLE IF EXISTS public.payroll_advances CASCADE;
DROP TABLE IF EXISTS public.payroll_monthly_payments CASCADE;

-- 2. Hapus fungsi lama yang sudah tidak digunakan
DROP FUNCTION IF EXISTS public.can_manage_event_inventory(text) CASCADE;
DROP FUNCTION IF EXISTS public.can_access_event(text) CASCADE;
DROP FUNCTION IF EXISTS public.current_user_event() CASCADE;
DROP FUNCTION IF EXISTS public.is_event_employee() CASCADE;

-- 3. Tabel Profil Pengguna & Hak Akses
CREATE TABLE IF NOT EXISTS public.profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  role text NOT NULL DEFAULT 'employee',
  branch text,
  branches text[] NOT NULL DEFAULT '{}'::text[],
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('admin','owner','employee'));
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_branch_check;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_branches_check;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_scope_check;

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

-- 5. Tabel Daftar Bahan (Master Inventory Toko)
CREATE TABLE IF NOT EXISTS public.inventory (
  id text PRIMARY KEY,
  store text NOT NULL,
  name text NOT NULL,
  unit text NOT NULL,
  stock numeric(15,2) NOT NULL DEFAULT 0 CHECK (stock >= 0),
  min_stock numeric(15,2) NOT NULL DEFAULT 0 CHECK (min_stock >= 0),
  price numeric(15,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  note text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 6. Tabel Rekapan Bahan Harian (Closing Inventory)
CREATE TABLE IF NOT EXISTS public.inventory_daily (
  id text PRIMARY KEY,
  inventory_id text REFERENCES public.inventory(id) ON DELETE SET NULL,
  store text NOT NULL,
  record_date date NOT NULL,
  name text NOT NULL,
  unit text NOT NULL,
  opening_stock numeric(15,2) NOT NULL DEFAULT 0 CHECK (opening_stock >= 0),
  stock_in numeric(15,2) NOT NULL DEFAULT 0 CHECK (stock_in >= 0),
  closing_stock numeric(15,2) CHECK (closing_stock IS NULL OR closing_stock >= 0),
  used_stock numeric(15,2) NOT NULL DEFAULT 0 CHECK (used_stock >= 0),
  note text NOT NULL DEFAULT '',
  is_closed boolean NOT NULL DEFAULT false,
  closed_at timestamptz,
  closed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
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

-- 7. Functions & Security
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE user_id = auth.uid() AND role = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_owner()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE user_id = auth.uid() AND role = 'owner'
  );
$$;

CREATE OR REPLACE FUNCTION public.can_view_all()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_admin() OR public.is_owner();
$$;

CREATE OR REPLACE FUNCTION public.can_access_store(target_store text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE user_id = auth.uid()
        AND (
          (role = 'owner' AND target_store = ANY(COALESCE(branches, '{}'::text[])))
          OR (role = 'employee' AND branch IS NOT NULL AND branch = target_store)
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_inventory(target_store text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE user_id = auth.uid()
        AND role = 'employee'
        AND branch IS NOT NULL
        AND branch = target_store
    );
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
DECLARE
  target_store text;
BEGIN
  IF new_stock IS NULL OR new_stock < 0 THEN
    RAISE EXCEPTION 'Stok tidak valid';
  END IF;

  SELECT store INTO target_store
  FROM public.inventory
  WHERE id = target_inventory_id;

  IF target_store IS NULL THEN
    RAISE EXCEPTION 'Bahan tidak ditemukan';
  END IF;

  IF NOT (public.is_admin() OR public.can_manage_inventory(target_store)) THEN
    RAISE EXCEPTION 'Tidak memiliki akses mengubah stok toko ini';
  END IF;

  UPDATE public.inventory
  SET stock = new_stock,
      updated_at = COALESCE(target_updated_at, now())
  WHERE id = target_inventory_id;
END;
$$;

-- 8. Soft Delete & Audit Tables
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

ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS deleted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.inventory_daily ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE public.inventory_daily ADD COLUMN IF NOT EXISTS deleted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE OR REPLACE VIEW public.deleted_items AS
SELECT 'inventory' AS table_name, id, deleted_at, deleted_by, coalesce(store,'') AS store, coalesce(name,'Bahan') AS title, coalesce(note,'') AS detail FROM public.inventory WHERE deleted_at IS NOT NULL
UNION ALL SELECT 'inventory_daily', id, deleted_at, deleted_by, coalesce(store,''), coalesce(name,'Closing Bahan'), coalesce(note,'') FROM public.inventory_daily WHERE deleted_at IS NOT NULL;

-- 9. Row Level Security & Policies
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profiles readable by authenticated" ON public.profiles;
CREATE POLICY "Profiles readable by authenticated" ON public.profiles FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Profiles manageable by admin" ON public.profiles;
CREATE POLICY "Profiles manageable by admin" ON public.profiles FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Stores readable by authenticated" ON public.stores;
CREATE POLICY "Stores readable by authenticated" ON public.stores FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Stores manageable by admin" ON public.stores;
CREATE POLICY "Stores manageable by admin" ON public.stores FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Inventory readable by access" ON public.inventory;
CREATE POLICY "Inventory readable by access" ON public.inventory FOR SELECT TO authenticated USING (public.can_access_store(store));
DROP POLICY IF EXISTS "Inventory manageable by admin" ON public.inventory;
CREATE POLICY "Inventory manageable by admin" ON public.inventory FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Daily inventory readable by access" ON public.inventory_daily;
CREATE POLICY "Daily inventory readable by access" ON public.inventory_daily FOR SELECT TO authenticated USING (public.can_access_store(store));
DROP POLICY IF EXISTS "Daily inventory manageable" ON public.inventory_daily;
CREATE POLICY "Daily inventory manageable" ON public.inventory_daily FOR ALL TO authenticated USING (public.is_admin() OR public.can_manage_inventory(store)) WITH CHECK (public.is_admin() OR public.can_manage_inventory(store));

DROP POLICY IF EXISTS "Audit logs readable by admin" ON public.audit_logs;
CREATE POLICY "Audit logs readable by admin" ON public.audit_logs FOR SELECT TO authenticated USING (public.is_admin());

GRANT SELECT,INSERT,UPDATE,DELETE ON public.stores, public.inventory, public.inventory_daily, public.profiles, public.audit_logs TO authenticated;

NOTIFY pgrst, 'reload schema';
