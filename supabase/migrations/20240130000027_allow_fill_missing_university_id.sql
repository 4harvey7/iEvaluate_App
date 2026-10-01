-- ============================================================================
-- Migration: Let a user fill in their OWN missing university ID, once
-- Version: 20240130000027
--
-- WARNING: Run this in your Supabase SQL Editor (Dashboard → SQL Editor)
--
-- The post-login "Complete your information" dialog asks users whose
-- user_info.university_id is NULL/blank to supply it. Migration 26's
-- trg_protect_user_info_fields refused ANY university_id change from a
-- non-admin, including NULL -> value, so that save could never succeed.
--
-- This keeps every protection from migration 26 and adds exactly one
-- exception: a non-admin may set university_id when the stored value is NULL
-- or blank. Once set it is locked again -- changing an existing ID still
-- requires an SAO admin. Uniqueness is still enforced by
-- user_info_university_id_unique_idx (migration 8).
--
-- Address needs no change: "Users can update own profile" already allows it.
-- ============================================================================

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

    -- Fill-once: allowed only when there was no ID before, and only by the
    -- account owner.
    IF NEW.university_id IS DISTINCT FROM OLD.university_id THEN
      IF NOT (
        NULLIF(btrim(COALESCE(OLD.university_id, '')), '') IS NULL
        AND NULLIF(btrim(COALESCE(NEW.university_id, '')), '') IS NOT NULL
        AND auth.uid() = OLD.id
      ) THEN
        RAISE EXCEPTION 'Forbidden: You cannot modify your university ID.';
      END IF;
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

-- Trigger from migration 26 already points at this function; recreated here
-- so this file is safe to run on its own.
DROP TRIGGER IF EXISTS trg_protect_user_info_fields ON public.user_info;
CREATE TRIGGER trg_protect_user_info_fields
  BEFORE UPDATE ON public.user_info
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_user_info_fields();
