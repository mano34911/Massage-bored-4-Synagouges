-- Add PayPal subscription tracking to synagogue accounts.
-- Safe to run once in Supabase SQL Editor.

alter table public.synagogues
  add column if not exists paypal_subscription_id text,
  add column if not exists paypal_plan_id text,
  add column if not exists paypal_subscription_status text,
  add column if not exists paypal_payer_email text,
  add column if not exists paypal_verified_at timestamptz,
  add column if not exists last_payment_at timestamptz;

create unique index if not exists synagogues_paypal_subscription_id_uidx
  on public.synagogues(paypal_subscription_id)
  where paypal_subscription_id is not null;
