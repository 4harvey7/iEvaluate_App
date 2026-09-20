-- ============================================================
-- Migration: Account Self-Delete RLS
-- Description: Allows a user (account owner) to delete their
--              own row from public.user_info. The cascade on
--              auth.users will handle removing the auth record
--              when called via a server-side Edge Function with
--              the service role (auth.admin.deleteUser).
-- ============================================================

-- --------------------------------------------------------------
-- 1. Add DELETE policy on user_info
--    An authenticated user may only delete the row where
--    user_info.id matches their own auth.uid().
-- --------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'user_info'
      AND policyname = 'Users can delete own account'
  ) THEN
    CREATE POLICY "Users can delete own account"
      ON public.user_info
      FOR DELETE
      USING (auth.uid() = id);
  END IF;
END $$;

-- --------------------------------------------------------------
-- 2. Add DELETE policy on department_table
--    A user can delete their own department_table row so that
--    the FK constraint does not block the user_info deletion
--    when deleting via the client (without cascade).
-- --------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'department_table'
      AND policyname = 'Users can delete own department entry'
  ) THEN
    CREATE POLICY "Users can delete own department entry"
      ON public.department_table
      FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- --------------------------------------------------------------
-- 3. Add DELETE policy on Sao_users
--    Mirrors the above for SAO-role users so their linked rows
--    can also be cleaned up before deleting user_info.
-- --------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'Sao_users'
      AND policyname = 'Users can delete own Sao_users entry'
  ) THEN
    CREATE POLICY "Users can delete own Sao_users entry"
      ON public."Sao_users"
      FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- --------------------------------------------------------------
-- NOTE ON auth.users DELETION
-- Deleting from public.user_info does NOT automatically delete
-- the auth.users record (the FK is references, not ON DELETE CASCADE
-- from auth ? public).
-- To fully remove the user from Supabase Auth you MUST call:
--
--   supabase.auth.admin.deleteUser(userId)   <- from an Edge Function
--                                               using the SERVICE ROLE key
--
-- Recommended flow (client -> Edge Function -> Supabase Admin API):
--   1. User taps "Delete Account" in the app.
--   2. App calls an Edge Function (e.g. /delete-account) with the
--      user JWT in the Authorization header.
--   3. Edge Function verifies the JWT, then calls:
--        auth.admin.deleteUser(uid)
--      This deletes auth.users and cascades to public.user_info.
-- --------------------------------------------------------------
