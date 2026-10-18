-- Move every account in BICS to BSIT, then remove the BICS department.
-- Idempotent: ids are looked up by d_code; re-running with no BICS is a no-op.
DO $$
DECLARE
  v_bics bigint;
  v_bsit bigint;
  v_bsit_has_head boolean;
BEGIN
  SELECT id INTO v_bics FROM public.department_name WHERE d_code = 'BICS' AND d_name = 'BachelorInCybersecurity';
  SELECT id INTO v_bsit FROM public.department_name WHERE d_code = 'BSIT';
  IF v_bics IS NULL THEN
    RAISE NOTICE 'BICS not found; nothing to do.';
    RETURN;
  END IF;
  IF v_bsit IS NULL THEN
    RAISE NOTICE 'BSIT not found; aborting.';
    RETURN;
  END IF;

  -- enforce_one_department_head would reject moving a head into a department
  -- that already has a different head, so heads are skipped in that case.
  SELECT EXISTS (
    SELECT 1 FROM public.department_table
    WHERE "Department_name_ID" = v_bsit AND public.is_department_head_role(roles)
  ) INTO v_bsit_has_head;

  -- instructor_departments: merge duplicates first (unique on instructor_id, department_id).
  UPDATE public.instructor_departments b
     SET is_primary = b.is_primary OR i.is_primary
    FROM public.instructor_departments i
   WHERE i.department_id = v_bics AND b.department_id = v_bsit
     AND b.instructor_id = i.instructor_id
     AND (NOT v_bsit_has_head OR NOT EXISTS (
           SELECT 1 FROM public.department_table dt
            WHERE dt.user_id = i.instructor_id AND public.is_department_head_role(dt.roles)));
  DELETE FROM public.instructor_departments i
   WHERE i.department_id = v_bics
     AND EXISTS (SELECT 1 FROM public.instructor_departments b
                  WHERE b.department_id = v_bsit AND b.instructor_id = i.instructor_id)
     AND (NOT v_bsit_has_head OR NOT EXISTS (
           SELECT 1 FROM public.department_table dt
            WHERE dt.user_id = i.instructor_id AND public.is_department_head_role(dt.roles)));

  -- department_table (the sync_instructor_department trigger repoints the primary
  -- instructor_departments row; leftovers are handled below).
  UPDATE public.department_table
     SET "Department_name_ID" = v_bsit
   WHERE "Department_name_ID" = v_bics
     AND (NOT v_bsit_has_head OR NOT public.is_department_head_role(roles));

  -- Remaining instructor_departments rows still on BICS (non-primary, or skipped heads' rows excluded).
  UPDATE public.instructor_departments i
     SET department_id = v_bsit
   WHERE i.department_id = v_bics
     AND NOT EXISTS (SELECT 1 FROM public.instructor_departments b
                      WHERE b.department_id = v_bsit AND b.instructor_id = i.instructor_id)
     AND (NOT v_bsit_has_head OR NOT EXISTS (
           SELECT 1 FROM public.department_table dt
            WHERE dt.user_id = i.instructor_id AND dt.roles IS NOT NULL
              AND public.is_department_head_role(dt.roles)));

  -- instructor_department_terms (unique on term_id, instructor_id, department_id).
  DELETE FROM public.instructor_department_terms t
   WHERE t.department_id = v_bics
     AND EXISTS (SELECT 1 FROM public.instructor_department_terms b
                  WHERE b.department_id = v_bsit AND b.term_id = t.term_id
                    AND b.instructor_id = t.instructor_id);
  UPDATE public.instructor_department_terms
     SET department_id = v_bsit
   WHERE department_id = v_bics;

  -- Delete BICS only when nothing references it any more.
  IF NOT EXISTS (SELECT 1 FROM public.department_table WHERE "Department_name_ID" = v_bics)
     AND NOT EXISTS (SELECT 1 FROM public.instructor_departments WHERE department_id = v_bics)
     AND NOT EXISTS (SELECT 1 FROM public.instructor_department_terms WHERE department_id = v_bics)
     AND NOT EXISTS (SELECT 1 FROM public.subjects WHERE department_id = v_bics)
  THEN
    ALTER TABLE public.department_name DISABLE TRIGGER department_name_no_delete;
    DELETE FROM public.department_name WHERE id = v_bics;
    ALTER TABLE public.department_name ENABLE TRIGGER department_name_no_delete;
  ELSE
    RAISE NOTICE 'BICS left in place: still referenced (likely a department head blocked by BSIT having a head).';
  END IF;
END $$;

-- Verify afterwards (expect: 0 BICS rows/refs; 3 accounts listed under BSIT):
-- select (select count(*) from public.department_name where d_code='BICS') bics_rows,
--        (select count(*) from public.department_table dt join public.department_name d on d.id=dt."Department_name_ID" where d.d_code='BICS') dt_refs,
--        (select count(*) from public.instructor_departments i join public.department_name d on d.id=i.department_id where d.d_code='BICS') id_refs;
-- select dt.user_id, dt.roles, d.d_code from public.department_table dt join public.department_name d on d.id=dt."Department_name_ID"
--  where dt.user_id in ('0ff3bedd-b8a9-4318-a1ee-4cf9d7bd8aae','4b01927f-ffcb-43d4-9a16-fcb05754b9cb','20f621cf-f861-4e87-85af-9d7dca885e78');
