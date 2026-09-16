-- THREE SEPARATE ROLES: MASTER ADMIN / SYNAGOGUE OWNER / MEMBER
create extension if not exists pgcrypto;
alter table public.synagogues add column if not exists owner_user_id uuid references auth.users(id);
alter table public.synagogues add column if not exists status text default 'pending';
alter table public.synagogues add column if not exists donation_url text;

create table if not exists public.app_profiles(
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('master_admin','synagogue_owner','member')),
 status text not null default 'pending' check(status in ('pending','approved','suspended')),
 synagogue_id uuid references public.synagogues(id) on delete cascade,
 full_name text, created_at timestamptz not null default now()
);
create table if not exists public.synagogue_members(
 id uuid primary key default gen_random_uuid(),
 synagogue_id uuid not null references public.synagogues(id) on delete cascade,
 auth_user_id uuid unique references auth.users(id) on delete cascade,
 full_name text not null, login_email text not null, phone text,
 status text not null default 'pending' check(status in ('pending','approved','suspended')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(synagogue_id,login_email)
);

create or replace function public.handle_app_user() returns trigger language plpgsql security definer set search_path=public as $$
declare r text; sid uuid; nm text; ph text;
begin
 r:=coalesce(new.raw_user_meta_data->>'role','member');
 if r not in ('member','synagogue_owner') then r:='member'; end if;
 sid:=nullif(new.raw_user_meta_data->>'synagogue_id','')::uuid;
 nm:=coalesce(new.raw_user_meta_data->>'full_name',new.email); ph:=coalesce(new.raw_user_meta_data->>'phone','');
 insert into public.app_profiles(user_id,role,status,synagogue_id,full_name) values(new.id,r,'pending',sid,nm) on conflict(user_id) do nothing;
 if r='member' and sid is not null then insert into public.synagogue_members(synagogue_id,auth_user_id,full_name,login_email,phone,status) values(sid,new.id,nm,new.email,ph,'pending') on conflict(synagogue_id,login_email) do nothing; end if;
 return new;
end $$;
drop trigger if exists on_auth_user_created_app on auth.users;
create trigger on_auth_user_created_app after insert on auth.users for each row execute function public.handle_app_user();

create or replace function public.is_master() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.app_profiles where user_id=auth.uid() and role='master_admin' and status='approved')$$;
create or replace function public.owns_synagogue(sid uuid) returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.app_profiles where user_id=auth.uid() and role='synagogue_owner' and status='approved' and synagogue_id=sid)$$;

alter table public.app_profiles enable row level security;
alter table public.synagogue_members enable row level security;
alter table public.synagogues enable row level security;

drop policy if exists profiles_read on public.app_profiles;
create policy profiles_read on public.app_profiles for select to authenticated using(user_id=auth.uid() or public.is_master());
drop policy if exists profiles_master_update on public.app_profiles;
create policy profiles_master_update on public.app_profiles for update to authenticated using(public.is_master()) with check(public.is_master());

drop policy if exists syn_read on public.synagogues;
create policy syn_read on public.synagogues for select to anon,authenticated using(status='approved' or public.is_master() or owner_user_id=auth.uid());
drop policy if exists syn_master on public.synagogues;
create policy syn_master on public.synagogues for all to authenticated using(public.is_master()) with check(public.is_master());
drop policy if exists syn_owner_update on public.synagogues;
create policy syn_owner_update on public.synagogues for update to authenticated using(public.owns_synagogue(id)) with check(public.owns_synagogue(id));

drop policy if exists members_read on public.synagogue_members;
create policy members_read on public.synagogue_members for select to authenticated using(public.owns_synagogue(synagogue_id) or auth_user_id=auth.uid() or public.is_master());
drop policy if exists members_update on public.synagogue_members;
create policy members_update on public.synagogue_members for update to authenticated using(public.owns_synagogue(synagogue_id) or public.is_master()) with check(public.owns_synagogue(synagogue_id) or public.is_master());
drop policy if exists members_delete on public.synagogue_members;
create policy members_delete on public.synagogue_members for delete to authenticated using(public.owns_synagogue(synagogue_id) or public.is_master());

-- AFTER creating your own Auth account, replace YOUR_EMAIL_HERE and run:
-- insert into public.app_profiles(user_id,role,status,full_name)
-- select id,'master_admin','approved',email from auth.users where lower(email)=lower('YOUR_EMAIL_HERE')
-- on conflict(user_id) do update set role='master_admin',status='approved';
