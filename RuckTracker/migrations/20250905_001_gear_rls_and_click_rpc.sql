-- Enable RLS (idempotent) and define policies for gear tables
-- Uses IF EXISTS checks to avoid failing when tables are not yet created

do $$ begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_items') then
    execute 'alter table public.gear_items enable row level security';
    -- read active items
    begin execute 'create policy catalog_read_items on public.gear_items for select using (is_active = true)'; exception when duplicate_object then null; end;
    -- service/admin write
    begin execute 'create policy catalog_write_items on public.gear_items for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_categories') then
    execute 'alter table public.gear_categories enable row level security';
    begin execute 'create policy catalog_read_categories on public.gear_categories for select using (true)'; exception when duplicate_object then null; end;
    begin execute 'create policy catalog_write_categories on public.gear_categories for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_skus') then
    execute 'alter table public.gear_skus enable row level security';
    begin execute 'create policy catalog_read_skus on public.gear_skus for select using (is_active = true)'; exception when duplicate_object then null; end;
    begin execute 'create policy catalog_write_skus on public.gear_skus for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_prices') then
    execute 'alter table public.gear_prices enable row level security';
    begin execute 'create policy catalog_read_prices on public.gear_prices for select using (true)'; exception when duplicate_object then null; end;
    begin execute 'create policy catalog_write_prices on public.gear_prices for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_images') then
    execute 'alter table public.gear_images enable row level security';
    begin execute 'create policy catalog_read_images on public.gear_images for select using (true)'; exception when duplicate_object then null; end;
    begin execute 'create policy catalog_write_images on public.gear_images for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_item_tags') then
    execute 'alter table public.gear_item_tags enable row level security';
    begin execute 'create policy catalog_read_tags on public.gear_item_tags for select using (true)'; exception when duplicate_object then null; end;
    begin execute 'create policy catalog_write_tags on public.gear_item_tags for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_discounts') then
    execute 'alter table public.gear_discounts enable row level security';
    begin execute 'create policy discounts_admin on public.gear_discounts for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='user_gear') then
    execute 'alter table public.user_gear enable row level security';
    begin execute 'create policy user_gear_read on public.user_gear for select using (user_id = auth.uid())'; exception when duplicate_object then null; end;
    begin execute 'create policy user_gear_insert on public.user_gear for insert with check (user_id = auth.uid())'; exception when duplicate_object then null; end;
    begin execute 'create policy user_gear_update on public.user_gear for update using (user_id = auth.uid()) with check (user_id = auth.uid())'; exception when duplicate_object then null; end;
    begin execute 'create policy user_gear_delete on public.user_gear for delete using (user_id = auth.uid())'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_comments') then
    execute 'alter table public.gear_comments enable row level security';
    begin execute 'create policy comments_read on public.gear_comments for select using (true)'; exception when duplicate_object then null; end;
    begin execute 'create policy comments_insert on public.gear_comments for insert with check (user_id = auth.uid())'; exception when duplicate_object then null; end;
    begin execute 'create policy comments_update on public.gear_comments for update using (user_id = auth.uid()) with check (user_id = auth.uid())'; exception when duplicate_object then null; end;
    begin execute 'create policy comments_delete on public.gear_comments for delete using (user_id = auth.uid())'; exception when duplicate_object then null; end;
    begin execute 'create policy comments_admin_all on public.gear_comments for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_referrals') then
    execute 'alter table public.gear_referrals enable row level security';
    begin execute 'create policy referrals_admin on public.gear_referrals for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='retailer_discount_codes') then
    execute 'alter table public.retailer_discount_codes enable row level security';
    begin execute 'create policy retailer_codes_admin on public.retailer_discount_codes for all to service_role using (true) with check (true)'; exception when duplicate_object then null; end;
  end if;

  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='gear_referral_clicks') then
    execute 'alter table public.gear_referral_clicks enable row level security';
    -- insert via service or RPC only; no public read
    begin execute 'create policy clicks_insert_server on public.gear_referral_clicks for insert to service_role with check (true)'; exception when duplicate_object then null; end;
    revoke select on public.gear_referral_clicks from public;
    revoke select on public.gear_referral_clicks from anon;
    revoke select on public.gear_referral_clicks from authenticated;
  end if;
end $$;

-- Secure RPC for logging referral clicks from clients (optional)
-- Clients pass a precomputed ip_hash; server enforces minimal required fields
do $$ begin
  if exists (select 1 from pg_proc where proname = 'log_gear_click') then
    -- already exists
    null;
  else
    execute $outer$
      create or replace function public.log_gear_click(
        p_sku_id uuid,
        p_gear_item_id uuid,
        p_retailer text,
        p_code text,
        p_referral_id uuid,
        p_region_code text,
        p_currency_code text,
        p_target_url text,
        p_user_agent text,
        p_ip_hash text
      ) returns void
      language plpgsql
      security definer
      set search_path = public
      as $body$
      begin
        insert into public.gear_referral_clicks (
          sku_id, gear_item_id, retailer, code, referral_id,
          user_id, clicked_at, region_code, currency_code, target_url,
          user_agent, ip_hash
        ) values (
          p_sku_id, p_gear_item_id, p_retailer, p_code, p_referral_id,
          auth.uid(), now(), p_region_code, p_currency_code, p_target_url,
          left(coalesce(p_user_agent, ''), 512), p_ip_hash
        );
      end;
      $body$;
    $outer$;
    grant execute on function public.log_gear_click(uuid, uuid, text, text, uuid, text, text, text, text, text) to authenticated;
  end if;
end $$;
