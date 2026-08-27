-- Run this script in the Supabase Dashboard SQL Editor.
-- It matches the profile upsert used by this Flutter project.

create table if not exists public.profiles (
  email text primary key,
  name text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

grant select, insert, update on table public.profiles to authenticated;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles for select
to authenticated
using (lower(email) = lower((select auth.jwt() ->> 'email')));

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles for insert
to authenticated
with check (lower(email) = lower((select auth.jwt() ->> 'email')));

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles for update
to authenticated
using (lower(email) = lower((select auth.jwt() ->> 'email')))
with check (lower(email) = lower((select auth.jwt() ->> 'email')));

create table if not exists public.saved_routes (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  subtitle text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.journeys (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  from_location text not null,
  to_location text not null,
  service text not null,
  duration_minutes integer not null,
  created_at timestamptz not null default now()
);

alter table public.saved_routes enable row level security;
alter table public.journeys enable row level security;

grant select, insert, update, delete on table public.saved_routes to authenticated;
grant select, insert, update, delete on table public.journeys to authenticated;

drop policy if exists "saved_routes_select_own" on public.saved_routes;
create policy "saved_routes_select_own"
on public.saved_routes for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "saved_routes_insert_own" on public.saved_routes;
create policy "saved_routes_insert_own"
on public.saved_routes for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "saved_routes_update_own" on public.saved_routes;
create policy "saved_routes_update_own"
on public.saved_routes for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "saved_routes_delete_own" on public.saved_routes;
create policy "saved_routes_delete_own"
on public.saved_routes for delete
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "journeys_select_own" on public.journeys;
create policy "journeys_select_own"
on public.journeys for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "journeys_insert_own" on public.journeys;
create policy "journeys_insert_own"
on public.journeys for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "journeys_update_own" on public.journeys;
create policy "journeys_update_own"
on public.journeys for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "journeys_delete_own" on public.journeys;
create policy "journeys_delete_own"
on public.journeys for delete
to authenticated
using (user_id = (select auth.uid()));
