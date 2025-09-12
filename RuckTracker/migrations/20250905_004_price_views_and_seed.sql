-- Seed categories (idempotent upserts)
insert into gear_categories (slug, name)
values
  ('rucks','Backpacks / Rucks'),
  ('ruck_plates','Ruck Plates / Weights'),
  ('weighted_vests','Weighted Vests'),
  ('devices','Devices & Sensors'),
  ('shoes','Shoes'),
  ('socks','Socks'),
  ('ruck_straps','Ruck Straps & Handles'),
  ('accessories','Accessories'),
  ('clothing_outerwear','Clothing & Outerwear')
on conflict (slug) do update set name = excluded.name;

-- Latest base price per SKU
create or replace view view_gear_latest_prices as
select p.sku_id,
       first_value(p.price_minor) over (partition by p.sku_id order by p.recorded_at desc) as latest_price_minor,
       first_value(p.recorded_at) over (partition by p.sku_id order by p.recorded_at desc) as latest_recorded_at
from gear_prices p;

-- Effective latest price applying active discounts (prefer best final price)
create or replace view view_gear_effective_latest_prices as
with latest as (
  select distinct on (lp.sku_id)
    lp.sku_id, lp.latest_price_minor, lp.latest_recorded_at
  from view_gear_latest_prices lp
), discounts as (
  select d.id, d.sku_id, d.gear_item_id, d.percent, d.fixed_minor
  from gear_discounts d
  where d.is_active = true and (d.valid_until is null or d.valid_until > now())
)
select
  s.id as sku_id,
  l.latest_price_minor as base_minor,
  case
    when d.fixed_minor is not null then greatest(l.latest_price_minor - d.fixed_minor, 0)
    when d.percent is not null then (l.latest_price_minor * (100 - d.percent))::bigint / 100
    else l.latest_price_minor
  end as effective_minor,
  l.latest_recorded_at, d.id as discount_id
from gear_skus s
left join latest l on l.sku_id = s.id
left join discounts d on d.sku_id = s.id or d.gear_item_id = s.gear_item_id
where s.is_active = true;

-- Item summary rollup (first image + price min/avg/max across active SKUs)
create or replace view view_gear_item_summary as
with active_skus as (
  select s.id as sku_id, s.gear_item_id
  from gear_skus s where s.is_active = true
), prices as (
  select e.sku_id, e.effective_minor
  from view_gear_effective_latest_prices e
)
select gi.id as gear_item_id,
       gi.name,
       gi.brand,
       gi.model,
       gi.default_image_url,
       gc.slug as category_slug,
       (select min(p.effective_minor) from prices p join active_skus a on a.sku_id = p.sku_id where a.gear_item_id = gi.id) as price_min_minor,
       (select avg(p.effective_minor) from prices p join active_skus a on a.sku_id = p.sku_id where a.gear_item_id = gi.id) as price_avg_minor,
       (select max(p.effective_minor) from prices p join active_skus a on a.sku_id = p.sku_id where a.gear_item_id = gi.id) as price_max_minor
from gear_items gi
left join gear_categories gc on gc.id = gi.category_id
where gi.is_active = true;

