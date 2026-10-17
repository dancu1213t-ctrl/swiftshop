-- Weekly prices apply to future renewals; existing charges and per-order fees remain unchanged.
begin;
update public.swift_merchant_rates set name=case plan when 'pro' then 'Pro' else name end, weekly_cents=case plan when 'basic' then 650 when 'pro' then 850 when 'premium' then 950 end where plan in ('basic','pro','premium');
commit;
