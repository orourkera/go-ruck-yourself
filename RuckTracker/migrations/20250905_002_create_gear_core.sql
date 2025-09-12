-- Core Gear Catalog, External Products, User Claims, and Public Views
-- Safe to run multiple times; uses IF NOT EXISTS and CREATE OR REPLACE VIEW

-- UUID generator is required for defaults (on Supabase/PG14+ this exists by default)
-- If missing, enable: create extension if not exists pgcrypto;

-- Categories
create table if not exists gear_categories (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  created_at timestamptz not null default now()
);

-- Curated items
create table if not exists gear_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  brand text,
  model text,
  description text,
  category_id uuid references gear_categories(id),
  default_image_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_gear_items_brand on gear_items(brand);
create index if not exists idx_gear_items_category on gear_items(category_id);
create index if not exists idx_gear_items_active on gear_items(is_active);

-- SKUs per retailer for curated items
create table if not exists gear_skus (
  id uuid primary key default gen_random_uuid(),
  gear_item_id uuid not null references gear_items(id),
  retailer text not null,
  sku text not null,
  url text,
  currency text not null default 'USD',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(retailer, sku)
);
create index if not exists idx_gear_skus_item on gear_skus(gear_item_id);
create index if not exists idx_gear_skus_retailer on gear_skus(retailer);
create index if not exists idx_gear_skus_active on gear_skus(is_active);

-- Price history per SKU (minor units)
create table if not exists gear_prices (
  id uuid primary key default gen_random_uuid(),
  sku_id uuid not null references gear_skus(id),
  price_minor bigint not null,
  recorded_at timestamptz not null default now()
);
create index if not exists idx_gear_prices_sku_time on gear_prices(sku_id, recorded_at desc);

-- Images for curated items
create table if not exists gear_images (
  id uuid primary key default gen_random_uuid(),
  gear_item_id uuid not null references gear_items(id),
  image_url text not null,
  sort_order int,
  created_at timestamptz not null default now(),
  unique(gear_item_id, sort_order)
);
create index if not exists idx_gear_images_item on gear_images(gear_item_id);

-- Tags for curated items
create table if not exists gear_item_tags (
  id uuid primary key default gen_random_uuid(),
  gear_item_id uuid references gear_items(id),
  tag text not null,
  unique(gear_item_id, lower(tag))
);
create index if not exists idx_gear_item_tags_tag on gear_item_tags(lower(tag));

-- Discounts: item-level or SKU-level
create table if not exists gear_discounts (
  id uuid primary key default gen_random_uuid(),
  gear_item_id uuid references gear_items(id),
  sku_id uuid references gear_skus(id),
  name text,
  percent numeric(5,2),             -- 0..100
  fixed_minor bigint,
  coupon_code text,
  audience text not null default 'all_app_users',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check ((gear_item_id is not null) or (sku_id is not null)),
  check ((percent is not null) <> (fixed_minor is not null)),
  check (percent is null or (percent >= 0 and percent <= 100))
);
create index if not exists idx_gear_discounts_item on gear_discounts(gear_item_id);
create index if not exists idx_gear_discounts_sku on gear_discounts(sku_id);
create index if not exists idx_gear_discounts_active on gear_discounts(is_active);
create index if not exists idx_gear_discounts_valid_from on gear_discounts(valid_from);
create index if not exists idx_gear_discounts_valid_until on gear_discounts(valid_until);

-- Referral links at SKU level (affiliate/collab)
create table if not exists gear_referrals (
  id uuid primary key default gen_random_uuid(),
  sku_id uuid not null references gear_skus(id),
  referral_code text,
  referral_url text,
  source text,                      -- e.g., impact, cj, internal
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists idx_gear_referrals_sku on gear_referrals(sku_id);

-- External products (Amazon, Shopify store, etc.) to avoid duplicating catalog locally
create table if not exists external_products (
  id uuid primary key default gen_random_uuid(),
  source text not null,             -- 'amazon' | 'shopify' | 'other'
  external_id text not null,        -- e.g., ASIN
  url text,                         -- canonical PDP URL
  retailer text,                    -- e.g., 'amazon'
  title text,
  image_url text,
  category_slug text,               -- maps into our taxonomy
  canonical_gear_item_id uuid references gear_items(id), -- optional mapping to curated
  created_at timestamptz not null default now(),
  unique(source, external_id)
);
create index if not exists idx_external_products_category on external_products(category_slug);
create index if not exists idx_external_products_canonical on external_products(canonical_gear_item_id);

-- Comments & ratings (supports curated or external reference)
create table if not exists gear_comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  gear_item_id uuid references gear_items(id),
  external_product_id uuid references external_products(id),
  rating smallint check (rating between 1 and 5),
  title text,
  body text,
  ownership_claimed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((gear_item_id is not null) or (external_product_id is not null))
);
create index if not exists idx_gear_comments_item on gear_comments(gear_item_id);
create index if not exists idx_gear_comments_external on gear_comments(external_product_id);
create index if not exists idx_gear_comments_user on gear_comments(user_id);

-- User claims and saves (supports curated or external reference)
create table if not exists user_gear (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  gear_item_id uuid references gear_items(id),
  external_product_id uuid references external_products(id),
  relation text not null check (relation in ('saved','owned')),
  visibility text not null default 'public' check (visibility in ('public','followers','private')),
  created_at timestamptz not null default now(),
  -- generated key to deduplicate per user across curated or external
  ref_key text generated always as (coalesce(gear_item_id::text, external_product_id::text)) stored,
  unique(user_id, ref_key, relation)
);
create index if not exists idx_user_gear_user on user_gear(user_id);
create index if not exists idx_user_gear_visibility on user_gear(visibility);
create index if not exists idx_user_gear_relation on user_gear(relation);

-- Unified public-owned gear view (for profiles and discovery)
create or replace view view_owned_gear_public as
select
  ug.user_id,
  ug.created_at,
  coalesce(ep.category_slug, gc.slug) as category_slug,
  case when ug.gear_item_id is not null then 'curated' else 'external' end as source,
  ug.gear_item_id,
  ug.external_product_id,
  -- unified presentation fields
  coalesce(gi.name, ep.title) as title,
  coalesce(gi.default_image_url, ep.image_url) as image_url
from user_gear ug
left join gear_items gi on ug.gear_item_id = gi.id
left join gear_categories gc on gi.category_id = gc.id
left join external_products ep on ug.external_product_id = ep.id
where ug.relation = 'owned' and ug.visibility = 'public';

-- Public owned-gear counts for discovery pages
create or replace view view_gear_owned_counts as
with base as (
  select
    case
      when ug.gear_item_id is not null then ug.gear_item_id::text
      when ep.canonical_gear_item_id is not null then ep.canonical_gear_item_id::text
      else 'ext:' || ep.id::text
    end as canonical_key,
    case when ug.gear_item_id is not null or ep.canonical_gear_item_id is not null then 'curated' else 'external' end as source,
    coalesce(ep.category_slug, gc.slug) as category_slug,
    coalesce(gi.name, ep.title) as title,
    coalesce(gi.default_image_url, ep.image_url) as image_url
  from user_gear ug
  left join gear_items gi on ug.gear_item_id = gi.id
  left join gear_categories gc on gi.category_id = gc.id
  left join external_products ep on ug.external_product_id = ep.id
  where ug.relation = 'owned' and ug.visibility = 'public'
)
select canonical_key, source, category_slug, title, image_url, count(*) as owners_count
from base
group by canonical_key, source, category_slug, title, image_url
order by owners_count desc;

-- Public wishlist (saved) gear view
create or replace view view_saved_gear_public as
select
  ug.user_id,
  ug.created_at,
  coalesce(ep.category_slug, gc.slug) as category_slug,
  case when ug.gear_item_id is not null then 'curated' else 'external' end as source,
  ug.gear_item_id,
  ug.external_product_id,
  coalesce(gi.name, ep.title) as title,
  coalesce(gi.default_image_url, ep.image_url) as image_url
from user_gear ug
left join gear_items gi on ug.gear_item_id = gi.id
left join gear_categories gc on gi.category_id = gc.id
left join external_products ep on ug.external_product_id = ep.id
where ug.relation = 'saved' and ug.visibility = 'public';

-- Saved (wishlist) counts for discovery pages
create or replace view view_gear_saved_counts as
with base as (
  select
    case
      when ug.gear_item_id is not null then ug.gear_item_id::text
      when ep.canonical_gear_item_id is not null then ep.canonical_gear_item_id::text
      else 'ext:' || ep.id::text
    end as canonical_key,
    case when ug.gear_item_id is not null or ep.canonical_gear_item_id is not null then 'curated' else 'external' end as source,
    coalesce(ep.category_slug, gc.slug) as category_slug,
    coalesce(gi.name, ep.title) as title,
    coalesce(gi.default_image_url, ep.image_url) as image_url
  from user_gear ug
  left join gear_items gi on ug.gear_item_id = gi.id
  left join gear_categories gc on gi.category_id = gc.id
  left join external_products ep on ug.external_product_id = ep.id
  where ug.relation = 'saved' and ug.visibility = 'public'
)
select canonical_key, source, category_slug, title, image_url, count(*) as saved_count
from base
group by canonical_key, source, category_slug, title, image_url
order by saved_count desc;
