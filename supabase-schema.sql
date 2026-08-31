-- Beth Torah Message Board SaaS - Supabase schema
-- Run this ONCE in Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  phone text,
  role text not null default 'member' check (role in ('member','master')),
  created_at timestamptz not null default now()
);

create table if not exists public.synagogues (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references public.profiles(user_id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,39}$'),
  synagogue_name text not null,
  rabbi_name text default '',
  status text not null default 'pending' check (status in ('pending','trial','active','suspended','deleted')),
  price_monthly_cents integer not null default 0 check (price_monthly_cents >= 0),
  trial_starts_at timestamptz,
  trial_ends_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.synagogue_settings (
  synagogue_id uuid primary key references public.synagogues(id) on delete cascade,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create or replace function public.is_master()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.role='master');
$$;

create or replace function public.member_has_access(p_synagogue_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.synagogues s
    where s.id=p_synagogue_id
      and (
        s.status='active'
        or (s.status='trial' and s.trial_ends_at is not null and now() < s.trial_ends_at)
      )
  );
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_syn_name text;
  v_rabbi text;
begin
  v_syn_name := coalesce(nullif(new.raw_user_meta_data->>'synagogue_name',''),'New Synagogue');
  v_rabbi := coalesce(new.raw_user_meta_data->>'rabbi_name','');
  v_slug := lower(coalesce(nullif(new.raw_user_meta_data->>'board_slug',''),'syn-' || substr(new.id::text,1,8)));

  insert into public.profiles(user_id,email,full_name,phone,role)
  values(new.id,new.email,new.raw_user_meta_data->>'full_name',new.raw_user_meta_data->>'phone','member')
  on conflict (user_id) do nothing;

  insert into public.synagogues(owner_user_id,slug,synagogue_name,rabbi_name,status)
  values(new.id,v_slug,v_syn_name,v_rabbi,'pending');

  insert into public.synagogue_settings(synagogue_id,settings)
  select s.id, jsonb_build_object('synagogue',v_syn_name,'rabbi',v_rabbi)
  from public.synagogues s where s.owner_user_id=new.id
  on conflict (synagogue_id) do nothing;

  return new;
exception
  when unique_violation then
    raise exception 'That Board ID is already in use. Please choose another.';
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.synagogues enable row level security;
alter table public.synagogue_settings enable row level security;

revoke all on public.profiles from anon, authenticated;
revoke all on public.synagogues from anon, authenticated;
revoke all on public.synagogue_settings from anon, authenticated;

grant select on public.profiles to authenticated;
grant select, update on public.synagogues to authenticated;
grant select, insert, update on public.synagogue_settings to authenticated;

drop policy if exists profiles_select_self_or_master on public.profiles;
create policy profiles_select_self_or_master on public.profiles
for select to authenticated
using (user_id=(select auth.uid()) or public.is_master());

drop policy if exists synagogues_select_owner_or_master on public.synagogues;
create policy synagogues_select_owner_or_master on public.synagogues
for select to authenticated
using (owner_user_id=(select auth.uid()) or public.is_master());

drop policy if exists synagogues_update_master on public.synagogues;
create policy synagogues_update_master on public.synagogues
for update to authenticated
using (public.is_master())
with check (public.is_master());

drop policy if exists synagogues_update_owner_identity on public.synagogues;
create policy synagogues_update_owner_identity on public.synagogues
for update to authenticated
using (owner_user_id=(select auth.uid()) and public.member_has_access(id))
with check (owner_user_id=(select auth.uid()) and public.member_has_access(id));

drop policy if exists settings_select_owner_or_master on public.synagogue_settings;
create policy settings_select_owner_or_master on public.synagogue_settings
for select to authenticated
using (
  public.is_master()
  or exists(
    select 1 from public.synagogues s
    where s.id=synagogue_id and s.owner_user_id=(select auth.uid())
  )
);

drop policy if exists settings_insert_owner_or_master on public.synagogue_settings;
create policy settings_insert_owner_or_master on public.synagogue_settings
for insert to authenticated
with check (
  public.is_master()
  or exists(
    select 1 from public.synagogues s
    where s.id=synagogue_id and s.owner_user_id=(select auth.uid()) and public.member_has_access(s.id)
  )
);

drop policy if exists settings_update_owner_or_master on public.synagogue_settings;
create policy settings_update_owner_or_master on public.synagogue_settings
for update to authenticated
using (
  public.is_master()
  or exists(
    select 1 from public.synagogues s
    where s.id=synagogue_id and s.owner_user_id=(select auth.uid()) and public.member_has_access(s.id)
  )
)
with check (
  public.is_master()
  or exists(
    select 1 from public.synagogues s
    where s.id=synagogue_id and s.owner_user_id=(select auth.uid()) and public.member_has_access(s.id)
  )
);

-- Public board lookup. It only returns boards that are currently entitled to display.
create or replace function public.get_public_board(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'synagogue_id',s.id,
    'slug',s.slug,
    'synagogue_name',s.synagogue_name,
    'rabbi_name',s.rabbi_name,
    'status',s.status,
    'trial_ends_at',s.trial_ends_at,
    'settings',coalesce(ss.settings,'{}'::jsonb)
  )
  from public.synagogues s
  left join public.synagogue_settings ss on ss.synagogue_id=s.id
  where s.slug=p_slug
    and (
      s.status='active'
      or (s.status='trial' and s.trial_ends_at is not null and now()<s.trial_ends_at)
    )
  limit 1;
$$;

grant execute on function public.get_public_board(text) to anon, authenticated;

-- AFTER you register YOUR OWN account, make yourself the master.
-- Replace the email below with your actual login email and run this one statement:
-- update public.profiles set role='master' where email='YOUR_EMAIL_HERE';
