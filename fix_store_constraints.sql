-- ==============================================================================
-- SQL PERBAIKAN: Hapus check constraint toko & scope
-- Jalankan script ini di: Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ==============================================================================

-- 1. Hapus constraint kaku pada tabel inventory, transaksi, dan tabel lainnya
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_scope_check;
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_store_check;
ALTER TABLE public.inventory_daily DROP CONSTRAINT IF EXISTS inventory_daily_scope_check;
ALTER TABLE public.inventory_daily DROP CONSTRAINT IF EXISTS inventory_daily_store_check;
ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_scope_check;
ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_store_check;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_scope_check;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_store_check;
ALTER TABLE public.event_material_catalog DROP CONSTRAINT IF EXISTS event_material_catalog_scope_check;
ALTER TABLE public.event_material_catalog DROP CONSTRAINT IF EXISTS event_material_catalog_store_check;
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_scope_check;
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_store_check;
ALTER TABLE public.payroll DROP CONSTRAINT IF EXISTS payroll_scope_check;
ALTER TABLE public.payroll DROP CONSTRAINT IF EXISTS payroll_store_check;
ALTER TABLE public.payroll_daily DROP CONSTRAINT IF EXISTS payroll_daily_scope_check;
ALTER TABLE public.payroll_daily DROP CONSTRAINT IF EXISTS payroll_daily_store_check;
ALTER TABLE public.payroll_advances DROP CONSTRAINT IF EXISTS payroll_advances_scope_check;
ALTER TABLE public.payroll_advances DROP CONSTRAINT IF EXISTS payroll_advances_store_check;
ALTER TABLE public.payroll_monthly_payments DROP CONSTRAINT IF EXISTS payroll_monthly_payments_scope_check;
ALTER TABLE public.payroll_monthly_payments DROP CONSTRAINT IF EXISTS payroll_monthly_payments_store_check;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_scope_check;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_branch_check;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_branches_check;

-- 2. Bersihkan secara dinamis setiap check constraint yang masih memeriksa toko/cabang/scope
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
        tc.constraint_name ILIKE '%scope_check%'
        OR tc.constraint_name ILIKE '%store_check%'
        OR tc.constraint_name ILIKE '%branch_check%'
      )
  ) LOOP
    EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I', r.table_schema, r.table_name, r.constraint_name);
  END LOOP;
END $$;

-- 3. Pastikan tabel stores tersedia untuk menyimpan toko kustom secara cloud
CREATE TABLE IF NOT EXISTS public.stores (
  id text PRIMARY KEY,
  name text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Stores readable by authenticated" ON public.stores;
CREATE POLICY "Stores readable by authenticated"
ON public.stores FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "Stores manageable by admin" ON public.stores;
CREATE POLICY "Stores manageable by admin"
ON public.stores FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

GRANT ALL ON public.stores TO authenticated;

-- Refresh cache Supabase PostgREST
NOTIFY pgrst, 'reload schema';

