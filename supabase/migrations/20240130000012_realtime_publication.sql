-- 20240130000012_realtime_publication.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`.
-- supabase_migrations.schema_migrations is empty on this project, so a push
-- would try to replay every earlier migration.
--
-- TERM CHANGES NEVER REACHED THE APP, AND NEITHER DID INTERVENTION ALERTS
--
-- SystemSettingsService.streamSettings() has always been correct Dart --
-- lib/core/services/system_settings_service.dart opens a Realtime stream on
-- system_settings, and the dashboards subscribe to it. But the publication
-- Realtime reads from was empty:
--
--   select * from pg_publication_tables where pubname = 'supabase_realtime';
--   -> 0 rows
--
-- With no table in the publication Postgres sends no WAL rows to Realtime, so
-- the stream yields its initial snapshot and then goes silent for the life of
-- the app. The SAO admin's term change was landing in the database and never
-- being announced, which is why every screen kept showing the previous term
-- until it happened to be rebuilt. The instructor dashboard's
-- intervention_reports channel was dead for the same reason.
--
-- user_info is deliberately NOT added. It carries two permissive
-- `USING (true)` SELECT policies, so putting it on the publication would
-- broadcast every profile change -- names, emails, university ids -- to every
-- subscribed client. Profile edits are refreshed client-side instead.


-- Idempotent: ALTER PUBLICATION ... ADD TABLE errors if the table is already a
-- member, so each add is guarded.
do $$
declare
  t text;
begin
  for t in
    select unnest(array['system_settings', 'academic_terms', 'intervention_reports'])
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
      raise notice 'added public.% to supabase_realtime', t;
    else
      raise notice 'public.% already in supabase_realtime', t;
    end if;
  end loop;
end $$;

-- The instructor dashboard subscribes with a filter on instructor_id, a
-- non-primary-key column. Without FULL replica identity, UPDATE and DELETE
-- events carry only the primary key in the old row, so the filter cannot match
-- and RLS cannot be evaluated against the pre-change row.
alter table public.intervention_reports replica identity full;


-- ── Verification ─────────────────────────────────────────────────────────────
-- Expect three rows: academic_terms, intervention_reports, system_settings.
--   select schemaname, tablename from pg_publication_tables
--    where pubname = 'supabase_realtime' order by tablename;
--
-- Then, in the app: change the term as SAO admin on one device and watch a
-- second device already sitting on a dashboard. It should show the
-- "Updating term…" scrim and reload without being touched.
