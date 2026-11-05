-- ==============================================================================
-- SQL PERBAIKAN: Hapus check constraint inventory_scope_check & batasan toko
-- Jalankan script ini di: Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ==============================================================================

-- 1. Hapus constraint kaku & kolom scope pada tabel inventory & inventory_daily
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_scope_check CASCADE;
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_store_check CASCADE;
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_event_id_fkey CASCADE;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS scope CASCADE;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS event_id text;

ALTER TABLE public.inventory_daily DROP CONSTRAINT IF EXISTS inventory_daily_scope_check CASCADE;
ALTER TABLE public.inventory_daily DROP CONSTRAINT IF EXISTS inventory_daily_store_check CASCADE;
ALTER TABLE public.inventory_daily DROP CONSTRAINT IF EXISTS inventory_daily_event_id_fkey CASCADE;
ALTER TABLE public.inventory_daily DROP COLUMN IF EXISTS scope CASCADE;
ALTER TABLE public.inventory_daily ADD COLUMN IF NOT EXISTS event_id text;

-- Tabel lain (jika masih ada dari versi sebelumnya)
ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_scope_check CASCADE;
ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_store_check CASCADE;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_scope_check CASCADE;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_store_check CASCADE;
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_scope_check CASCADE;
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_store_check CASCADE;
ALTER TABLE public.payroll DROP CONSTRAINT IF EXISTS payroll_scope_check CASCADE;
ALTER TABLE public.payroll DROP CONSTRAINT IF EXISTS payroll_store_check CASCADE;
ALTER TABLE public.payroll_daily DROP CONSTRAINT IF EXISTS payroll_daily_scope_check CASCADE;
ALTER TABLE public.payroll_daily DROP CONSTRAINT IF EXISTS payroll_daily_store_check CASCADE;
ALTER TABLE public.payroll_advances DROP CONSTRAINT IF EXISTS payroll_advances_scope_check CASCADE;
ALTER TABLE public.payroll_advances DROP CONSTRAINT IF EXISTS payroll_advances_store_check CASCADE;
ALTER TABLE public.payroll_monthly_payments DROP CONSTRAINT IF EXISTS payroll_monthly_payments_scope_check CASCADE;
ALTER TABLE public.payroll_monthly_payments DROP CONSTRAINT IF EXISTS payroll_monthly_payments_store_check CASCADE;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_scope_check CASCADE;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_branch_check CASCADE;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_branches_check CASCADE;

-- 2. Bersihkan secara otomatis seluruh check constraint yang membatasi toko/cabang/scope
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

-- 3. Pastikan tabel stores tersedia untuk pendaftaran toko baru
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

-- 4. Reload cache schema PostgREST Supabase
NOTIFY pgrst, 'reload schema';
