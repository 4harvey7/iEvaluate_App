-- ============================================================================
-- Migration: Allow SAO office and gatherers to delete raw survey records
--
-- WARNING: Run this in the Supabase SQL Editor if deleting flagged raw survey
-- records in sast_all_raw_data_survey is blocked by RLS.
-- ============================================================================

DROP POLICY IF EXISTS "SAO office deletes raw results" ON public.sast_all_raw_data_survey;
DROP POLICY IF EXISTS "Gatherers can delete raw results" ON public.sast_all_raw_data_survey;

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
    OR
    -- Unassigned/flagged survey records
    instructor_ID IS NULL
  );
