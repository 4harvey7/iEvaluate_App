-- ============================================================================
-- Migration: Comprehensive Security Hardening
-- Version: 20240130000026
--
-- WARNING: Run this in your Supabase SQL Editor (Dashboard → SQL Editor)
--
-- Addresses:
-- 1. CRITICAL: Drops "Admins can manage own verification" on admin_verifications.
--    The previous policy allowed any authenticated user to SELECT and UPDATE
--    their own 2FA/OTP codes via PostgREST! Edge Functions use the service role
--    and bypass RLS automatically, so no authenticated/anon policy is needed.
-- 2. HIGH: Prevents account_status, email, and university_id tampering on
--    user_info by non-admin callers (prevents self-approval of pending accounts).
-- 3. HIGH: Restricts Sao_users insertion/update to prevent non-admins from
--    self-assigning the SAO_ADMIN role during signup or API tampering.
-- 4. MEDIUM: Restricts system_settings updates to SAO_ADMIN only.
-- 5. MEDIUM: Tightens sast_all_raw_data_survey DELETE policy to prevent
--    arbitrary deletion of unassigned records (instructor_ID IS NULL).
-- ============================================================================


-- ── 1. Harden admin_verifications (Fix OTP Tamper / Leak) ───────────────────
-- Only Edge Functions (Service Role) should touch OTP records.
-- Drop any permissive policies for authenticated users.

ALTER TABLE public.admin_verifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage own verification" ON public.admin_verifications;
DROP POLICY IF EXISTS "Users can manage own verification" ON public.admin_verifications;
DROP POLICY IF EXISTS "admin_verifications_all" ON public.admin_verifications;


-- ── 2. Prevent Privilege Escalation on user_info ─────────────────────────────
-- Normal users can update their first_name, last_name, address, etc.
-- But they must NEVER be allowed to change account_status to 'approved' or alter
-- email/university_id/id unless they are an SAO Admin or Service Role.

CREATE OR REPLACE FUNCTION public.protect_user_info_fields()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Service role always allowed
  IF current_user = 'service_role' OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- If caller is not an SAO admin, prevent mutating sensitive governance fields
  IF NOT public.is_sao_admin() THEN
    IF NEW.account_status IS DISTINCT FROM OLD.account_status THEN
      RAISE EXCEPTION 'Forbidden: You cannot modify your own account status.';
    END IF;

    IF NEW.university_id IS DISTINCT FROM OLD.university_id THEN
      RAISE EXCEPTION 'Forbidden: You cannot modify your university ID.';
    END IF;

    IF NEW.email IS DISTINCT FROM OLD.email THEN
      RAISE EXCEPTION 'Forbidden: Primary email address cannot be changed directly.';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id THEN
      RAISE EXCEPTION 'Forbidden: User ID is immutable.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_user_info_fields ON public.user_info;
CREATE TRIGGER trg_protect_user_info_fields
  BEFORE UPDATE ON public.user_info
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_user_info_fields();


-- ── 3. Prevent Self-Assigning SAO_ADMIN Role in Sao_users ───────────────────
-- SAO_ADMIN is the master role that approves accounts and controls settings.
-- No unprivileged user may insert or update themselves into the SAO_ADMIN role.

CREATE OR REPLACE FUNCTION public.protect_sao_users_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role_name text;
BEGIN
  -- Service role always allowed
  IF current_user = 'service_role' OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  SELECT r."Roles" INTO v_role_name FROM public.roles r WHERE r.id = NEW.role_id;

  IF UPPER(COALESCE(v_role_name, '')) = 'SAO_ADMIN' AND NOT public.is_sao_admin() THEN
    RAISE EXCEPTION 'Forbidden: SAO_ADMIN accounts must be created by an existing administrator.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_sao_users_insert ON public."Sao_users";
CREATE TRIGGER trg_protect_sao_users_insert
  BEFORE INSERT OR UPDATE ON public."Sao_users"
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_sao_users_insert();


-- ── 4. Explicit RLS for system_settings ──────────────────────────────────────
-- Everyone can read active term, but only SAO_ADMIN can alter system settings.

ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Everyone can view system settings" ON public.system_settings;
CREATE POLICY "Everyone can view system settings"
  ON public.system_settings FOR SELECT
  TO authenticated, anon
  USING (true);

DROP POLICY IF EXISTS "SAO admins can update system settings" ON public.system_settings;
CREATE POLICY "SAO admins can update system settings"
  ON public.system_settings FOR UPDATE
  TO authenticated
  USING (public.is_sao_admin())
  WITH CHECK (public.is_sao_admin());

DROP POLICY IF EXISTS "SAO admins can insert system settings" ON public.system_settings;
CREATE POLICY "SAO admins can insert system settings"
  ON public.system_settings FOR INSERT
  TO authenticated
  WITH CHECK (public.is_sao_admin());


-- ── 5. Scope sast_all_raw_data_survey DELETE Policy ──────────────────────────
-- Remove the open loophole where 'OR instructor_ID IS NULL' allowed any
-- logged-in user to wipe unassigned raw survey records.

DROP POLICY IF EXISTS "SAO office and gatherers can delete raw results" ON public.sast_all_raw_data_survey;

CREATE POLICY "SAO office and gatherers can delete raw results"
  ON public.sast_all_raw_data_survey
  FOR DELETE
  TO authenticated
  USING (
    -- Gatherer who submitted it
    auth.uid() = sao_staff_id
    OR
    -- Any SAO staff or admin
    EXISTS (
      SELECT 1
      FROM public."Sao_users" su
      JOIN public.roles r ON r.id = su.role_id
      WHERE su.user_id = auth.uid()
        AND r."Roles" IN ('SAO_ADMIN', 'SAO_STAFF')
    )
  );


-- ============================================================================
-- Verification:
-- 1. Check policies on admin_verifications:
--    SELECT * FROM pg_policies WHERE tablename = 'admin_verifications';
--    -- Expect ZERO rows (service role only).
-- 2. Check triggers on user_info:
--    SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.user_info'::regclass;
--    -- Expect trg_protect_user_info_fields to be present.
-- ============================================================================
