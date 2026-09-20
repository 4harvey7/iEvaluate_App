-- 20240130000015_protect_assignments_with_results.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`.
--
-- An instructor_subjects row is the only thing linking an instructor to a
-- subject for a term. Deleting one destroys no evaluation data -- nothing has a
-- foreign key to that table -- but it is what "My Subjects", the subject report
-- and the student-feedback screen are built from. So once students have filled
-- out forms for that instructor and subject, removing the assignment leaves
-- those results sitting in the database with no route to them from the app.
-- They still count toward the instructor's overall score (overall_total_survey
-- is keyed on instructor and term, not subject), so the numbers stay right
-- while the evidence behind them becomes unreachable.
--
-- That has already happened once here: WEBDEV 201 / 1st Semester 2026-2027 has
-- a management_results and performance_results row with no matching assignment.
--
-- THE RULE
-- Refuse the delete when results exist for that exact (instructor, subject,
-- term). Allow it when none do -- a mis-assignment noticed before any form is
-- scanned is a normal correction, and with subjects themselves now
-- undeletable it is the only way to undo one.
--
-- 49 of the 51 assignments currently carry results, so in practice this makes
-- almost every existing assignment permanent, which is the intent.
--
-- Enforced here rather than only in the app because instructor_subjects is
-- reachable through the REST API with the publishable key and an SAO admin
-- session -- a check in Dart alone would be advisory.

create or replace function public.forbid_assignment_delete_with_results()
returns trigger language plpgsql as $$
declare
  n_mgmt int;
  n_perf int;
  n_remarks int;
  subj text;
begin
  select count(*) into n_mgmt from public.management_results r
   where r.instructor_id = old.instructor_id
     and r.subject_id    = old.subject_id
     and r.term_id       = old.term_id;

  select count(*) into n_perf from public.performance_results r
   where r.instructor_id = old.instructor_id
     and r.subject_id    = old.subject_id
     and r.term_id       = old.term_id;

  select count(*) into n_remarks from public.student_remarks r
   where r.instructor_id = old.instructor_id
     and r.subject_id    = old.subject_id
     and r.term_id       = old.term_id;

  if n_mgmt + n_perf + n_remarks = 0 then
    return old; -- nothing collected yet, this is a correction
  end if;

  select coalesce(s.subject_code, '?') into subj
    from public.subjects s where s.id = old.subject_id;

  raise exception
    'Cannot remove this instructor from %: % evaluation record(s) have already '
    'been collected for this term (% management, % performance, % remarks). '
    'Removing the assignment would leave those results unreachable in the app '
    'while still counting toward the instructor''s score. Correct the scanned '
    'data instead, or leave the assignment in place.',
    subj, n_mgmt + n_perf + n_remarks, n_mgmt, n_perf, n_remarks
    using errcode = 'restrict_violation';
end $$;

drop trigger if exists instructor_subjects_protect_results on public.instructor_subjects;
create trigger instructor_subjects_protect_results
  before delete on public.instructor_subjects
  for each row execute function public.forbid_assignment_delete_with_results();


-- ── Verification ─────────────────────────────────────────────────────────────
-- 1. An assignment WITH results must refuse deletion:
--      begin;
--      delete from public.instructor_subjects i
--       where exists (select 1 from public.management_results r
--                      where r.instructor_id=i.instructor_id
--                        and r.subject_id=i.subject_id
--                        and r.term_id=i.term_id);
--      rollback;   -- expect: restrict_violation
--
-- 2. Count how many assignments are now protected vs still removable:
--      select count(*) filter (where has_results) as protected,
--             count(*) filter (where not has_results) as removable
--        from (select exists (select 1 from public.management_results r
--                             where r.instructor_id=i.instructor_id
--                               and r.subject_id=i.subject_id
--                               and r.term_id=i.term_id) as has_results
--                from public.instructor_subjects i) t;
