-- Community member accounts + per-organization PayPal donations
-- Run this ONCE in Supabase SQL Editor after 20260901_registration_fields.sql.

create table if not exists public.organization_members (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  synagogue_id uuid not null references public.synagogues(id) on delete cascade,
  organization_slug text not null,
  full_name text not null default '',
  email text not null default '',
  phone text not null default '',
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists organization_members_synagogue_id_idx
  on public.organization_members(synagogue_id);

alter table public.organization_members enable row level security;

drop policy if exists "Members read own membership" on public.organization_members;
create policy "Members read own membership"
on public.organization_members for select
using (auth.uid() = user_id);

drop policy if exists "Organization owners read their members" on public.organization_members;
create policy "Organization owners read their members"
on public.organization_members for select
using (exists (
  select 1 from public.synagogues s
  where s.id = organization_members.synagogue_id
    and s.owner_user_id = auth.uid()
));

drop policy if exists "Organization owners update their members" on public.organization_members;
create policy "Organization owners update their members"
on public.organization_members for update
using (exists (
  select 1 from public.synagogues s
  where s.id = organization_members.synagogue_id
    and s.owner_user_id = auth.uid()
))
with check (exists (
  select 1 from public.synagogues s
  where s.id = organization_members.synagogue_id
    and s.owner_user_id = auth.uid()
));

-- Replace the registration trigger function so an Auth signup can create
-- either an organization-owner account or a sub-account for one congregation.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_name text;
  v_leader text;
  v_type text;
  v_settings jsonb;
  v_member_id text;
  v_synagogue_id uuid;
  v_account_type text;
begin
  v_account_type := lower(coalesce(new.raw_user_meta_data->>'account_type','organization_owner'));

  if v_account_type = 'organization_member' then
    v_slug := lower(trim(coalesce(new.raw_user_meta_data->>'organization_slug','')));
    select s.id into v_synagogue_id
    from public.synagogues s
    where lower(s.slug)=v_slug
    limit 1;

    if v_synagogue_id is null then
      raise exception 'Organization Board ID was not found.';
    end if;

    v_member_id := 'MEM-' || lpad(nextval('public.member_id_seq')::text,6,'0');
    insert into public.profiles(user_id,email,full_name,phone,role,member_id)
    values(
      new.id,new.email,new.raw_user_meta_data->>'full_name',
      coalesce(new.raw_user_meta_data->>'phone',''),'member',v_member_id
    )
    on conflict (user_id) do update set
      email=excluded.email,full_name=excluded.full_name,phone=excluded.phone,
      role='member';

    insert into public.organization_members(user_id,synagogue_id,organization_slug,full_name,email,phone,status)
    values(
      new.id,v_synagogue_id,v_slug,coalesce(new.raw_user_meta_data->>'full_name',''),
      new.email,coalesce(new.raw_user_meta_data->>'phone',''),'active'
    )
    on conflict (user_id) do update set
      synagogue_id=excluded.synagogue_id,organization_slug=excluded.organization_slug,full_name=excluded.full_name,
      email=excluded.email,phone=excluded.phone,updated_at=now();

    return new;
  end if;

  v_type := case when lower(coalesce(new.raw_user_meta_data->>'organization_type',''))='church' then 'church' else 'synagogue' end;
  v_name := coalesce(nullif(new.raw_user_meta_data->>'organization_name',''),nullif(new.raw_user_meta_data->>'synagogue_name',''),case when v_type='church' then 'New Church' else 'New Synagogue' end);
  v_leader := coalesce(new.raw_user_meta_data->>'leader_name',new.raw_user_meta_data->>'rabbi_name','');
  v_member_id := (case when v_type='church' then 'CHR-' else 'SYN-' end) || lpad(nextval('public.member_id_seq')::text,6,'0');
  v_slug := lower(coalesce(nullif(new.raw_user_meta_data->>'board_slug',''),(case when v_type='church' then 'church-' else 'syn-' end) || substr(new.id::text,1,8)));

  insert into public.profiles(
    user_id,email,full_name,phone,role,member_id,
    street_address,city,state_region,postal_code,country,
    heard_about,referred_by,referral_code
  ) values(
    new.id,new.email,new.raw_user_meta_data->>'full_name',new.raw_user_meta_data->>'phone','member',v_member_id,
    new.raw_user_meta_data->>'street_address',new.raw_user_meta_data->>'city',new.raw_user_meta_data->>'state_region',new.raw_user_meta_data->>'postal_code',new.raw_user_meta_data->>'country',
    new.raw_user_meta_data->>'heard_about',new.raw_user_meta_data->>'referred_by',new.raw_user_meta_data->>'referral_code'
  ) on conflict (user_id) do update set
    email=excluded.email,full_name=excluded.full_name,phone=excluded.phone,
    street_address=excluded.street_address,city=excluded.city,state_region=excluded.state_region,
    postal_code=excluded.postal_code,country=excluded.country,
    heard_about=excluded.heard_about,referred_by=excluded.referred_by,referral_code=excluded.referral_code;

  insert into public.synagogues(owner_user_id,slug,synagogue_name,rabbi_name,status)
  values(new.id,v_slug,v_name,v_leader,'pending');

  if v_type='church' then
    v_settings := jsonb_build_object('organization_type','church','church',v_name,'pastor',v_leader,'synagogue',v_name,'rabbi',v_leader,'paypalDonationUrl','','donateButtonLabel','Donate to Our Church');
  else
    v_settings := jsonb_build_object('organization_type','synagogue','synagogue',v_name,'rabbi',v_leader,'paypalDonationUrl','','donateButtonLabel','תרומה לבית הכנסת');
  end if;

  insert into public.synagogue_settings(synagogue_id,settings)
  select s.id,v_settings from public.synagogues s where s.owner_user_id=new.id
  on conflict (synagogue_id) do update set settings=excluded.settings,updated_at=now();

  return new;
exception when unique_violation then
  raise exception 'This email, Board ID, or other unique account value is already in use.';
end;
$$;

grant select on public.organization_members to authenticated;
