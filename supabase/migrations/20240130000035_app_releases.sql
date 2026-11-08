-- In-app updates: one row per APK published on GitHub Releases.
-- The app reads the newest row (highest version_code) and offers the update
-- when it is newer than the installed build number (pubspec "+N").
-- Clients may only read; rows are added by an admin in the SQL editor
-- (service role / postgres bypass RLS), e.g.:
--
--   insert into public.app_releases (version_code, version_name, apk_url, sha256, notes, force)
--   values (2, '1.0.1',
--           'https://github.com/4harvey7/iEvaluate_App/releases/download/v1.0.1/app-release.apk',
--           '<sha256 of the apk, 64 hex chars>', 'What changed', false);

create table if not exists public.app_releases (
  id           bigint generated always as identity primary key,
  version_code int         not null unique,
  version_name text        not null,
  apk_url      text        not null,
  sha256       text        not null,
  notes        text,
  force        boolean     not null default false,
  created_at   timestamptz default now()
);

alter table public.app_releases enable row level security;

-- anon too: the check must work even before the session is refreshed.
create policy "app_releases_read" on public.app_releases
  for select to anon, authenticated using (true);

-- No insert/update/delete policy on purpose; also drop the default write grants.
revoke insert, update, delete, truncate on public.app_releases from anon, authenticated;
grant select on public.app_releases to anon, authenticated;
