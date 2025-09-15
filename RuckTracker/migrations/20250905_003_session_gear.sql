-- Session Gear linking and usage aggregation views

-- Table to associate gear (curated or external) with a ruck session
create table if not exists ruck_session_gear (
  id uuid primary key default gen_random_uuid(),
  session_id integer not null references ruck_session(id) on delete cascade,
  user_id uuid not null,
  role text not null check (role in ('ruck','plate','shoes','device','accessory')),
  gear_item_id uuid references gear_items(id),
  external_product_id uuid references external_products(id),
  carried_weight_kg numeric(6,2), -- optional; applies to roles where weight is relevant
  created_at timestamptz not null default now(),
  -- Ensure exactly one reference is set
  check ((gear_item_id is not null) or (external_product_id is not null))
);
create index if not exists idx_rsg_session on ruck_session_gear(session_id);
create index if not exists idx_rsg_user on ruck_session_gear(user_id);
create index if not exists idx_rsg_role on ruck_session_gear(role);

-- RLS: owner-only access based on ruck_session.user_id
alter table ruck_session_gear enable row level security;
do $$ begin
  begin
    execute $pol$
      create policy rsg_owner_select on ruck_session_gear
        for select using (
          exists (
            select 1 from ruck_session rs
            where rs.id = session_id and rs.user_id = auth.uid()
          )
        )
    $pol$;
  exception when duplicate_object then null; end;
  begin
    execute $pol$
      create policy rsg_owner_write on ruck_session_gear
        for all using (
          exists (
            select 1 from ruck_session rs
            where rs.id = session_id and rs.user_id = auth.uid()
          )
        )
        with check (
          exists (
            select 1 from ruck_session rs
            where rs.id = session_id and rs.user_id = auth.uid()
          )
        )
    $pol$;
  exception when duplicate_object then null; end;
end $$;

-- Per-user gear usage (canonicalized)
create or replace view view_gear_usage_user as
with canon as (
  select
    rsg.user_id,
    rsg.role,
    rs.id as session_id,
    rs.completed_at,
    rs.distance_km,
    -- canonical key collapses external mapped items into curated
    case
      when rsg.gear_item_id is not null then rsg.gear_item_id::text
      when ep.canonical_gear_item_id is not null then ep.canonical_gear_item_id::text
      else 'ext:' || rsg.external_product_id::text
    end as canonical_key,
    coalesce(gi.name, ep.title) as title,
    coalesce(gi.default_image_url, ep.image_url) as image_url,
    coalesce(gc.slug, ep.category_slug) as category_slug,
    rsg.carried_weight_kg
  from ruck_session_gear rsg
  join ruck_session rs on rs.id = rsg.session_id and rs.status = 'completed'
  left join gear_items gi on gi.id = rsg.gear_item_id
  left join gear_categories gc on gc.id = gi.category_id
  left join external_products ep on ep.id = rsg.external_product_id
)
select
  user_id,
  role,
  canonical_key,
  title,
  image_url,
  category_slug,
  count(distinct session_id) as sessions_count,
  sum(coalesce(distance_km, 0)) as total_distance_km,
  max(coalesce(carried_weight_kg, 0)) as max_weight_kg,
  avg(nullif(carried_weight_kg, 0)) as avg_weight_kg,
  max(completed_at) as last_used_at
from canon
group by user_id, role, canonical_key, title, image_url, category_slug;

-- Global gear usage (anonymous)
create or replace view view_gear_usage_global as
with canon as (
  select
    rsg.role,
    rs.id as session_id,
    rs.distance_km,
    case
      when rsg.gear_item_id is not null then rsg.gear_item_id::text
      when ep.canonical_gear_item_id is not null then ep.canonical_gear_item_id::text
      else 'ext:' || rsg.external_product_id::text
    end as canonical_key,
    coalesce(gi.name, ep.title) as title,
    coalesce(gi.default_image_url, ep.image_url) as image_url,
    coalesce(gc.slug, ep.category_slug) as category_slug,
    rsg.carried_weight_kg
  from ruck_session_gear rsg
  join ruck_session rs on rs.id = rsg.session_id and rs.status = 'completed'
  left join gear_items gi on gi.id = rsg.gear_item_id
  left join gear_categories gc on gc.id = gi.category_id
  left join external_products ep on ep.id = rsg.external_product_id
)
select
  role,
  canonical_key,
  title,
  image_url,
  category_slug,
  count(distinct session_id) as sessions_count,
  sum(coalesce(distance_km, 0)) as total_distance_km,
  max(coalesce(carried_weight_kg, 0)) as max_weight_kg
from canon
group by role, canonical_key, title, image_url, category_slug
order by total_distance_km desc nulls last;
