-- ============================================================
-- Migration: address_locations (barangay picker for registration)
-- Run this in your Supabase SQL Editor (Dashboard -> SQL Editor -> New Query)
-- ============================================================
-- Backs the barangay typeahead on registration step 1. The registration screen
-- fetches this once on open -- the same trip it already makes for departments
-- and roles -- and filters locally, so the suggestions appear as you type with
-- no request per keystroke.
--
-- WHY A TABLE AND NOT AN ADDRESS API
-- The address is a display-only record: registration writes it, and the only
-- reader is one row in the admin user-details modal. Nothing searches, filters,
-- maps or geocodes it. Paying Google Places per lookup -- and proxying it
-- through an edge function to keep the API key out of the APK -- would be a lot
-- of moving parts for a field that only ever gets printed. A table costs
-- nothing, works on a bad connection, and the SAO can correct it themselves.
--
-- Storage is unchanged: user_info.address stays a single text column, and the
-- app composes "Purok 3, Lamacan, Argao, Cebu" before saving. No schema change
-- to user_info, and every existing address keeps working.
--
-- ⚠ VERIFY THE SEED BELOW
-- The barangay names seeded at the bottom are the ones for Argao as I
-- understand them, and they have NOT been checked against the Philippine
-- Statistics Authority's official PSGC list. Treat them as a starting point,
-- not as authoritative: correct any spelling and add the municipalities your
-- staff actually commute from. Nobody is ever blocked by a gap -- the picker
-- accepts free text for anything not listed -- but a misspelt barangay will sit
-- in the records until it is fixed.
--
-- To add more in bulk: Dashboard -> Table Editor -> address_locations ->
-- Insert -> Import data from CSV, with columns
-- barangay,municipality,province,is_campus_area
-- ============================================================

CREATE TABLE IF NOT EXISTS public.address_locations (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at     timestamptz NOT NULL DEFAULT now(),
  barangay       text NOT NULL,
  municipality   text NOT NULL,
  province       text NOT NULL DEFAULT 'Cebu',
  -- Sorted to the top of the suggestions. The campus is in Argao, so that is
  -- where nearly every member of staff lives; without this they would have to
  -- scroll past alphabetically-earlier places from other towns.
  is_campus_area boolean NOT NULL DEFAULT false,
  CONSTRAINT address_locations_unique UNIQUE (barangay, municipality, province)
);

COMMENT ON TABLE public.address_locations IS
  'Barangay list for the registration address picker. Display-only data: the '
  'app composes a single string into user_info.address. Safe to edit and '
  'extend from the Table Editor.';

-- Case-insensitive lookup, in case the filtering ever moves server-side.
CREATE INDEX IF NOT EXISTS address_locations_barangay_idx
  ON public.address_locations (lower(barangay));
CREATE INDEX IF NOT EXISTS address_locations_municipality_idx
  ON public.address_locations (lower(municipality));

-- ------------------------------------------------------------
-- Read access
-- ------------------------------------------------------------
-- Registration happens before anyone is signed in, so anon needs SELECT. This
-- is a public list of place names -- no personal data -- so unlike user_info
-- there is nothing here worth restricting.
ALTER TABLE public.address_locations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'address_locations'
      AND policyname = 'Anyone can read address locations'
  ) THEN
    CREATE POLICY "Anyone can read address locations"
      ON public.address_locations
      FOR SELECT
      TO anon, authenticated
      USING (true);
  END IF;
END $$;

-- ------------------------------------------------------------
-- Starter seed: Argao, Cebu  (⚠ verify against PSGC before relying on it)
-- ------------------------------------------------------------
-- ON CONFLICT DO NOTHING so this migration is safe to re-run and will not
-- clobber corrections made in the Table Editor.
INSERT INTO public.address_locations (barangay, municipality, province, is_campus_area)
VALUES
  ('Poblacion',   'Argao', 'Cebu', true),
  ('Balaas',      'Argao', 'Cebu', true),
  ('Balisong',    'Argao', 'Cebu', true),
  ('Binlod',      'Argao', 'Cebu', true),
  ('Bogo',        'Argao', 'Cebu', true),
  ('Bug-ot',      'Argao', 'Cebu', true),
  ('Bulasa',      'Argao', 'Cebu', true),
  ('Butong',      'Argao', 'Cebu', true),
  ('Calagasan',   'Argao', 'Cebu', true),
  ('Canbantug',   'Argao', 'Cebu', true),
  ('Canbanua',    'Argao', 'Cebu', true),
  ('Candabong',   'Argao', 'Cebu', true),
  ('Casay',       'Argao', 'Cebu', true),
  ('Catang',      'Argao', 'Cebu', true),
  ('Colawin',     'Argao', 'Cebu', true),
  ('Conalum',     'Argao', 'Cebu', true),
  ('Guiwanon',    'Argao', 'Cebu', true),
  ('Gutlang',     'Argao', 'Cebu', true),
  ('Jampang',     'Argao', 'Cebu', true),
  ('Jomgao',      'Argao', 'Cebu', true),
  ('Lamacan',     'Argao', 'Cebu', true),
  ('Langtad',     'Argao', 'Cebu', true),
  ('Langub',      'Argao', 'Cebu', true),
  ('Lapay',       'Argao', 'Cebu', true),
  ('Lengigon',    'Argao', 'Cebu', true),
  ('Linut-od',    'Argao', 'Cebu', true),
  ('Mabasa',      'Argao', 'Cebu', true),
  ('Mandilikit',  'Argao', 'Cebu', true),
  ('Mompeller',   'Argao', 'Cebu', true),
  ('Panadtaran',  'Argao', 'Cebu', true),
  ('Sua',         'Argao', 'Cebu', true),
  ('Sumaguan',    'Argao', 'Cebu', true),
  ('Tabayag',     'Argao', 'Cebu', true),
  ('Talaga',      'Argao', 'Cebu', true),
  ('Talaytay',    'Argao', 'Cebu', true),
  ('Talo-ot',     'Argao', 'Cebu', true),
  ('Tiguib',      'Argao', 'Cebu', true),
  ('Tulang',      'Argao', 'Cebu', true),
  ('Tulic',       'Argao', 'Cebu', true),
  ('Ubaub',       'Argao', 'Cebu', true),
  ('Usmad',       'Argao', 'Cebu', true)
ON CONFLICT (barangay, municipality, province) DO NOTHING;

-- Neighbouring towns staff commonly commute from. Only the town centres are
-- seeded -- add their barangays as you find you need them.
INSERT INTO public.address_locations (barangay, municipality, province, is_campus_area)
VALUES
  ('Poblacion', 'Dalaguete',  'Cebu', false),
  ('Poblacion', 'Sibonga',    'Cebu', false),
  ('Poblacion', 'Carcar',     'Cebu', false),
  ('Poblacion', 'Alcoy',      'Cebu', false),
  ('Poblacion', 'Boljoon',    'Cebu', false),
  ('Poblacion', 'Oslob',      'Cebu', false),
  ('Poblacion', 'Cebu City',  'Cebu', false)
ON CONFLICT (barangay, municipality, province) DO NOTHING;
