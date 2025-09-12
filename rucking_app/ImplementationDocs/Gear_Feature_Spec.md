
# Gear Feature Spec

## Overview
A curated, scalable Gear catalog integrated into the app with dynamic pricing, referral links, user ratings/comments, and the ability to save/own gear. Users can filter to “My Gear” (saved/owned). Catalog items are indexed by SKU, support multiple retailers, and enable future referral tracking and price updates.

Goals:
- Provide a smart Gear page with randomized curated items and filtering.
- Track user interactions: save, own, rate, comment.
- Support dynamic prices per retailer with history.
- Support referral links with tracking tokens.
- Support app-exclusive discounts per item or SKU with validity windows.
- Future-safe for price jobs, referral attribution, and model-driven ranking.

Non-goals (Phase 1):
- Building external price scrapers in-app. We will accept webhook or scheduled job inputs.
- Complex affiliate network integration beyond basic referral tokens/links.

## Architecture
- Client (Flutter): new `Gear` pages.
- Backend API (existing Python service in `RuckTracker/api/`): REST endpoints for gear, prices, comments, user saves/ownership.
- Database (Postgres): normalized schema for catalog, SKUs, prices, referrals, user mappings, comments, images, categories.
- Background jobs: price refresh pipeline (via serverless function or job) writing into price history; optional referral click events.

## Data Model (Postgres)

### Tables

1) gear_items
- id (PK, uuid)
- name (text, required)
- brand (text, indexed)
- model (text)
- description (text)
- category_id (fk -> gear_categories.id)
- default_image_url (text)
- is_active (bool, default true)
- created_at (timestamptz, default now())
- updated_at (timestamptz, default now())
Indexes: (brand), (category_id), (is_active)

2) gear_categories
- id (PK, uuid)
- slug (text unique, e.g., "packs", "shoes", "apparel")
- name (text)
- created_at (timestamptz)

3) gear_skus
- id (PK, uuid)
- gear_item_id (fk -> gear_items.id, required)
- retailer (text, required, e.g., "amazon", "goruck")
- sku (text, required)
- url (text) — product page
- currency (text, default "USD")
- is_active (bool, default true)
- created_at (timestamptz)
Unique: (retailer, sku)
Indexes: (gear_item_id), (retailer)

4) gear_prices
- id (PK, uuid)
- sku_id (fk -> gear_skus.id, required)
- price_minor (bigint, required) — price in minor units (cents)
- recorded_at (timestamptz, default now())
Indexes: (sku_id, recorded_at desc)

5) gear_referrals
- id (PK, uuid)
- sku_id (fk -> gear_skus.id)
- referral_code (text) — token for link attribution
- referral_url (text) — final redirect URL with token
- source (text) — e.g., "impact", "cj", "internal"
- is_active (bool, default true)
- created_at (timestamptz)
Indexes: (sku_id), (referral_code)

6) user_gear
- id (PK, uuid)
- user_id (uuid, required)
- gear_item_id (fk -> gear_items.id, required)
- relation (text enum: 'saved' | 'owned')
- created_at (timestamptz default now())
Unique: (user_id, gear_item_id, relation)
Indexes: (user_id), (gear_item_id), (relation)

7) gear_comments
- id (PK, uuid)
- user_id (uuid, required)
- gear_item_id (fk -> gear_items.id, required)
- rating (smallint, nullable, 1..5)
- title (text)
- body (text)
- ownership_claimed (bool default false)
- created_at (timestamptz default now())
- updated_at (timestamptz default now())
Indexes: (gear_item_id), (user_id), (created_at desc)
Constraints: rating between 1 and 5 when not null

8) gear_images
- id (PK, uuid)
- gear_item_id (fk -> gear_items.id, required)
- image_url (text, required)
- sort_order (int)
- created_at (timestamptz)
Index: (gear_item_id, sort_order)

9) gear_item_tags
- id (PK, uuid)
- gear_item_id (fk -> gear_items.id)
- tag (text)
Unique: (gear_item_id, tag)
Index: (tag)

10) gear_discounts
- id (PK, uuid)
- gear_item_id (fk -> gear_items.id, nullable) — applies to all SKUs of the item
- sku_id (fk -> gear_skus.id, nullable) — applies to a specific SKU
- name (text) — e.g., "Ruckers-only discount"
- percent numeric(5,2), nullable — percent off when set
- fixed_minor bigint, nullable — fixed amount off (minor units)
- coupon_code (text), nullable — if needed for checkout
- audience (text) default 'all_app_users' — future extensibility
- valid_from (timestamptz) default now()
- valid_until (timestamptz), nullable
- is_active (bool) default true
- created_at (timestamptz) default now()
Constraints:
- CHECK ((gear_item_id IS NOT NULL) OR (sku_id IS NOT NULL))
- CHECK ((percent IS NOT NULL) <> (fixed_minor IS NOT NULL))
Indexes: (gear_item_id), (sku_id), (is_active), (valid_from), (valid_until)

### Rucking Taxonomy (Categories & Slugs)
- Primary categories (slug → label)
  - `rucks` → Backpacks / Rucks
  - `ruck_plates` → Ruck Plates / Weights
  - `weighted_vests` → Weighted Vests
  - `devices` → Devices & Sensors (watches, HR straps, foot pods)
  - `shoes` → Shoes
  - `socks` → Socks
  - `ruck_straps` → Ruck Straps & Handles
  - `accessories` → Accessories
  - `clothing_outerwear` → Clothing & Outerwear

- Suggested subcategories/attributes (optional, stored in `specs_jsonb` on `gear_items`):
  - For `rucks`: capacity_liters, frame (framed|frameless), hydration_compatible (bool), molle (bool), event_ready (bool)
  - For `ruck_plates`: weight_kg, weight_lb, plate_form_factor (standard|long|vest)
  - For `weighted_vests`: max_load_kg, plate_compatibility, closure_type
  - For `shoes`: terrain (road|trail|hybrid|boot), drop_mm, width (narrow|standard|wide), waterproof (bool)
  - For `socks`: height (no_show|ankle|crew|knee), cushion (light|mid|heavy), fabric (wool|synthetic|blend)
  - For `ruck_straps`: type (sternum|waist|shoulder|carry_handle), compatibility (molle|universal)
  - For `accessories`: hydration (bladders|bottles), pouches, lights, safety, repair
  - For `clothing_outerwear`: layer (base|mid|shell|insulation), weather (rain|cold|hot), gender_fit (mens|womens|unisex)
  - For `devices`: type (watch|chest_strap|foot_pod|sensor), ecosystem (apple_watch|garmin|wear_os|fitbit|other),
    connectivity (bluetooth|ant_plus), hr_method (optical|chest), gps (true|false), battery_life_hours (int)

- Synonyms mapping (for search/import):
  - Backpacks → `rucks`
  - Plates/Weights → `ruck_plates`
  - Vests/Weighted Gear → `weighted_vests`
  - Wearables/Devices/Sensors → `devices`
  - Footwear → `shoes`
  - Straps/Handles → `ruck_straps`
  - Apparel → `clothing_outerwear`

Seed guidance: insert rows in `gear_categories` for each slug above. All listing/filter UIs should use these slugs.

### Views / Materialized Views
- view_gear_latest_prices: latest base price per SKU and a rollup per gear_item with min/avg/max across active SKUs.
- view_gear_effective_latest_prices: applies any currently-active discount (item-level or SKU-level) to latest base prices and exposes final_price_minor plus discount metadata.
- view_gear_item_summary: combines gear_items with category, first image, summary rating (avg), comment_count, and price rollups (use effective prices when present, else base).

- All views MUST filter `gear_items.is_active = true` and `gear_skus.is_active = true`, and only consider `gear_discounts.is_active = true` when applying discounts.

### Example DDL (sketch)
```sql
-- categories
create table if not exists gear_categories (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  created_at timestamptz not null default now()
);

-- items
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

-- skus
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

-- prices
create table if not exists gear_prices (
  id uuid primary key default gen_random_uuid(),
  sku_id uuid not null references gear_skus(id),
  price_minor bigint not null,
  recorded_at timestamptz not null default now()
);
create index if not exists idx_gear_prices_sku_time on gear_prices(sku_id, recorded_at desc);

-- referrals
create table if not exists gear_referrals (
  id uuid primary key default gen_random_uuid(),
  sku_id uuid not null references gear_skus(id),
  referral_code text,
  referral_url text,
  source text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists idx_gear_referrals_sku on gear_referrals(sku_id);

-- retailer-level promo/discount codes (manufacturer-level)
create table if not exists retailer_discount_codes (
  id uuid primary key default gen_random_uuid(),
  retailer text not null,               -- must match gear_skus.retailer
  code text not null,
  percent numeric(5,2),                 -- one of percent or fixed_minor
  fixed_minor bigint,
  region_code text,                     -- optional targeting by region (e.g., US, UK)
  currency_code text,                   -- optional targeting by currency
  apply_method text not null default 'param', -- 'param' | 'display_only' | 'path' | 'none'
  apply_param_name text not null default 'coupon',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  unique(retailer, code, coalesce(region_code, 'ALL'))
);

-- outbound click logs (record all clicks to retailers)
create table if not exists gear_referral_clicks (
  id uuid primary key default gen_random_uuid(),
  sku_id uuid references gear_skus(id),
  gear_item_id uuid references gear_items(id),
  retailer text,                 -- redundant for fast analytics
  code text,                     -- retailer/manufacturer code used, if any
  referral_id uuid references gear_referrals(id), -- when a sku-level referral row exists
  user_id uuid,                  -- nullable for anonymous clicks
  clicked_at timestamptz not null default now(),
  region_code text,
  currency_code text,
  target_url text,               -- final URL we redirected to
  user_agent text,
  ip_hash text,                  -- store only a salted hash, never raw IP
  created_at timestamptz not null default now()
);
create index if not exists idx_grc_sku_time on gear_referral_clicks(sku_id, clicked_at desc);
create index if not exists idx_grc_item_time on gear_referral_clicks(gear_item_id, clicked_at desc);
create index if not exists idx_grc_user_time on gear_referral_clicks(user_id, clicked_at desc);

-- user gear mapping
create table if not exists user_gear (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  gear_item_id uuid not null references gear_items(id),
  relation text not null check (relation in ('saved','owned')),
  created_at timestamptz not null default now(),
  unique(user_id, gear_item_id, relation)
);
create index if not exists idx_user_gear_user on user_gear(user_id);

-- comments
create table if not exists gear_comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  gear_item_id uuid not null references gear_items(id),
  rating smallint check (rating between 1 and 5),
  title text,
  body text,
  ownership_claimed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_gear_comments_item on gear_comments(gear_item_id);

-- discounts
create table if not exists gear_discounts (
  id uuid primary key default gen_random_uuid(),
  gear_item_id uuid references gear_items(id),
  sku_id uuid references gear_skus(id),
  name text,
  percent numeric(5,2),
  fixed_minor bigint,
  coupon_code text,
  audience text not null default 'all_app_users',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check ((gear_item_id is not null) or (sku_id is not null)),
  check ((percent is not null) <> (fixed_minor is not null))
);
create index if not exists idx_gear_discounts_item on gear_discounts(gear_item_id);
create index if not exists idx_gear_discounts_sku on gear_discounts(sku_id);
create index if not exists idx_gear_discounts_active on gear_discounts(is_active);
```

### Integrity & Performance
- Foreign keys ON DELETE RESTRICT for catalog tables; ON DELETE CASCADE only for derived data (images) if needed.
- Use partial indexes on is_active where relevant.
- Consider trigram index for search across name/brand/model if needed later.

Discounts:
- Apply at query time via effective price view to avoid mutating historical price points.
- Prefer SKU-level discounts over item-level when both apply; when both exist, choose the best (lowest final price).

## API Design (REST)
Base path: `/api/gear`
Auth: required for write actions; reads can be public or behind auth depending on app policy.

### Listing & Details
- GET `/api/gear/items`
  - Query params: `q`, `category`, `brand`, `sort` (popularity|price_low|price_high|rating|new), `filter` (all|saved|owned), `limit`, `offset`, `random=true`.
  - Returns: array of item summaries from `view_gear_item_summary` with price rollups (discount-aware) and rating. Only items with `gear_items.is_active = true` are included; inactive SKUs are excluded from rollups.
- GET `/api/gear/items/{item_id}`
  - Returns: full item with images, active SKUs with latest base and effective price (if any discount), discount metadata (name, percent/fixed, coupon_code), referral URLs if available, and comment summary. If the item is inactive, the endpoint MUST return 404 (or 410 Gone where clients distinguish) and the UI should treat it as no longer available.

### User Save/Own
- POST `/api/gear/items/{item_id}/save` — body: `{ saved: boolean }`
- POST `/api/gear/items/{item_id}/own` — body: `{ owned: boolean }`
- GET `/api/gear/me` — returns `{ saved: [...], owned: [...] }`

### Comments & Ratings
- GET `/api/gear/items/{item_id}/comments` — query: `limit`, `offset`, `sort` (new|top)
- POST `/api/gear/items/{item_id}/comments` — body: `{ rating?, title?, body, ownership_claimed? }`
- PATCH `/api/gear/comments/{comment_id}` — edit by owner
- DELETE `/api/gear/comments/{comment_id}` — delete by owner or admin
- Aggregations: server computes `avg_rating`, `comment_count` per item.

### Prices & Referrals
- GET `/api/gear/items/{item_id}/prices` — latest price per SKU plus history window (optional since detail includes latest).
- GET `/api/gear/ref/{retailer}/{code}` — redirect to retailer product URL, applying the code when possible, and record click event.
  - Query params: `sku_id` (recommended), `region`, optional `preview=true` to return JSON instead of redirect.
  - URL construction:
    - Resolve SKU by `sku_id` (must belong to `{retailer}`), ensure item and SKU are active.
    - Look up active `retailer_discount_codes` for `{retailer}`, `{code}` (and `region` if provided).
    - If `apply_method = 'param'`, append `?{apply_param_name}={code}` to the SKU base URL (respect existing query string).
    - If `apply_method = 'display_only'`, redirect to base URL and include `{ code }` in preview JSON; UI shows "Use code {code} at checkout".
    - If `apply_method = 'path'`, apply retailer-specific path rule (future; via template).
  - Response should include whether a discount is present and the effective price for preview before redirect (when used via API, not redirect).
  - Redirects MUST only occur for active items, active SKUs, and active referral/code rows. If inactive, respond with 404/410 and do not redirect.

### Admin/Backfill (secured)
- POST `/api/gear/admin/items` — create/update items
- POST `/api/gear/admin/skus` — add SKU with retailer and URL
- POST `/api/gear/admin/prices` — upsert price points in bulk
- POST `/api/gear/admin/referrals` — upsert referral links
  
  Additionally, admins can toggle active state:
  - PATCH `/api/gear/admin/items/{item_id}` — body: `{ is_active: boolean }`
  - PATCH `/api/gear/admin/skus/{sku_id}` — body: `{ is_active: boolean }`

### Response Sketch (Item Summary)
```json
{
  "id": "uuid",
  "name": "GORUCK GR1 26L",
  "brand": "GORUCK",
  "category": "packs",
  "image": "https://...",
  "price": {"min": 29500, "max": 33500, "currency": "USD"},
  "effective_price": {"min": 26500, "max": 32500, "currency": "USD"},
  "discount": {"present": true, "label": "Ruckers-only", "type": "percent", "value": 10.0},
  "rating": {"avg": 4.7, "count": 128},
  "saved": true,
  "owned": false
}
```

## Price Updates & Referral Tracking
- Price pipeline writes to `gear_prices` periodically. Latest price = max(recorded_at) per sku.
- Referral clicks endpoint records events (optional table `gear_referral_clicks`: id, referral_id, user_id?, clicked_at, user_agent, ip_hash).
- For compliance: do not store raw IP; hash with salt and retention limits.

## Flutter UI/UX

### Navigation
- Add a "Gear" entry to the home menu near `Profile`, `Clubs`, `Notifications`.
- Route: `GearListPage` -> `GearDetailPage`.

### Screens
- GearListPage
  - Grid/list of cards: image, name, brand, min price, rating, Save/Own toggles.
  - Filters: All | Saved | Owned; search; category chips; sort dropdown.
  - Randomized variety when no filters or `random=true`.
  - Empty states and skeleton shimmers.
- GearDetailPage
  - Image carousel, name/brand/model, description, tags.
  - Latest prices per retailer with referral badges.
  - If a discount applies: show strikethrough base price, highlighted effective price, and a "Ruckers-only discount" badge; include coupon code if required.
  - Save/Own toggles; write a comment; list of comments with rating.

### State & Data Layer (Flutter)
- Models: `GearItem`, `GearSku`, `GearPrice`, `GearReferral`, `GearComment`.
- Repository: `GearRepository` calling REST endpoints.
- BLoC/Notifier: `GearListBloc`, `GearDetailBloc`, `UserGearBloc`.
- Respect existing patterns in `rucking_app/lib/` for DI and error handling.

### UX Details
- Ratings: 1–5, half-star display optional.
- Prices: show currency; format from minor units; display base and effective price when discount present.
- Referral: show "Buy" CTA that opens referral URL using in-app browser; track click.
- Accessibility: large tap targets, alt text, readable contrasts.

- Inactive items: never shown in lists. If a user navigates directly and the backend returns 404/410 for an inactive item, show a "No longer available" message and disable Save/Own/Comment/Buy actions.

### Analytics
- gear_list_view, gear_filter_applied, gear_item_view, gear_saved_toggled, gear_owned_toggled, gear_buy_click, gear_comment_created, gear_comment_deleted.

## Security, Abuse, and Performance
- Auth required for mutations; rate-limit comment creation and toggles.
- Moderate comments: basic profanity filter; admin delete.
- Caching: CDN for images; server-side cache for list queries; optional materialized view refresh.
- Pagination across endpoints.

## Row-Level Security (RLS)
Enable RLS on all gear tables by default. Policies below assume Supabase with `auth.uid()` available and a service role used by the backend API.

General rules
- Catalog reads public/authenticated; writes admin/service-only.
- User-owned mappings (`user_gear`, `gear_comments`) are self-scoped by `user_id = auth.uid()`.
- Referral/discount management is service/admin-only; clicks insert via server (or a SECURITY DEFINER RPC) and are not publicly readable.

Enable RLS
```sql
alter table gear_items enable row level security;
alter table gear_categories enable row level security;
alter table gear_skus enable row level security;
alter table gear_prices enable row level security;
alter table gear_images enable row level security;
alter table gear_item_tags enable row level security;
alter table gear_discounts enable row level security;
alter table user_gear enable row level security;
alter table gear_comments enable row level security;
alter table gear_referrals enable row level security;
alter table retailer_discount_codes enable row level security;
alter table gear_referral_clicks enable row level security;
```

Catalog: read-only for anon/auth; write admin-only
```sql
-- READ: only active rows
create policy catalog_read_items on gear_items
  for select using (is_active = true);
create policy catalog_read_categories on gear_categories for select using (true);
create policy catalog_read_skus on gear_skus for select using (is_active = true);
create policy catalog_read_prices on gear_prices for select using (true);
create policy catalog_read_images on gear_images for select using (true);
create policy catalog_read_tags on gear_item_tags for select using (true);

-- WRITE: service/admin only (replace with your admin role)
create policy catalog_write_items on gear_items
  for all to role service_role using (true) with check (true);
create policy catalog_write_skus on gear_skus
  for all to role service_role using (true) with check (true);
create policy catalog_write_prices on gear_prices
  for all to role service_role using (true) with check (true);
create policy catalog_write_images on gear_images
  for all to role service_role using (true) with check (true);
create policy catalog_write_tags on gear_item_tags
  for all to role service_role using (true) with check (true);
```

User-owned tables
```sql
-- user_gear: user can read/write their own rows
create policy user_gear_read on user_gear for select
  using (user_id = auth.uid());
create policy user_gear_write on user_gear for insert with check (user_id = auth.uid());
create policy user_gear_update on user_gear for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy user_gear_delete on user_gear for delete using (user_id = auth.uid());

-- gear_comments: read all, write own
create policy comments_read on gear_comments for select using (true);
create policy comments_insert on gear_comments for insert with check (user_id = auth.uid());
create policy comments_update on gear_comments for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy comments_delete on gear_comments for delete using (user_id = auth.uid());

-- Optional: admin moderation
create policy comments_admin_all on gear_comments for all to role service_role using (true) with check (true);
```

Discounts, referrals, and clicks
```sql
-- Discounts and referrals: service/admin only
create policy discounts_admin on gear_discounts for all to role service_role using (true) with check (true);
create policy referrals_admin on gear_referrals for all to role service_role using (true) with check (true);
create policy retailer_codes_admin on retailer_discount_codes for all to role service_role using (true) with check (true);

-- Click logs: no public read; insert via service role or an RPC
create policy clicks_insert_server on gear_referral_clicks
  for insert to role service_role with check (true);
-- If you expose a SECURITY DEFINER RPC (e.g., log_gear_click), keep table non-readable:
revoke select on gear_referral_clicks from anon, authenticated;
```

Views and performance
- Ensure views (e.g., `view_gear_item_summary`, `view_gear_effective_latest_prices`) filter `is_active` and are created with `security_invoker` to respect RLS.
- Add partial indexes on `is_active` columns; consider `(gear_item_id, is_active)` on SKUs.

## Rollout Plan
- Feature flag: `gear_enabled`.
- Phase 1: schema + list/detail + save/own + comments.
- Phase 2: referral redirect + click logging + ranking improvements.
- Phase 3: price-update automation + notifications on price drops (optional).

## Implementation Checklist
- [x] Database migrations
  - [x] Create `retailer_discount_codes` (+ unique on `(retailer, code, coalesce(region_code,'ALL'))`).
  - [x] Create `gear_referral_clicks` (+ indexes) and enable RLS.
  - [x] Add RLS policies for catalog tables and secure RPC `public.log_gear_click(...)`.
  - [x] Create core catalog tables: `gear_categories`, `gear_items`, `gear_skus`, `gear_prices`, `gear_images`, `gear_item_tags`, `gear_discounts`, `gear_referrals`.
  - [x] Create `external_products` and `user_gear` (owned/wishlist with visibility).
  - [x] Create session linking: `ruck_session_gear` (+ RLS).
  - [x] Create public/usage views: `view_owned_gear_public`, `view_gear_owned_counts`, `view_gear_usage_user`, `view_gear_usage_global`.
  - [x] Seed `gear_categories` with taxonomy (includes `devices`).
  - [x] Price-rollup views: `view_gear_latest_prices`, `view_gear_effective_latest_prices`, `view_gear_item_summary`.

- [ ] Backend API
  - [x] Curated search: `GET /api/gear/search`.
  - [ ] Amazon proxy: `GET /api/amazon/search`, `GET /api/amazon/item?asin=` (PA‑API, cached ≤24h).
  - [x] Claim/unclaim: `POST /api/gear/claim`, `POST /api/gear/unclaim` (curated or external ref).
  - [x] Comments: `GET/POST /api/gear/items/{id}/comments` and `/api/gear/external/{id}/comments`.
  - [x] Referral redirect: `GET /api/gear/ref/{retailer}/{code}` (allowlisted hosts, preview mode; rate limit pending).
  - [x] Session gear: `GET/PATCH /api/rucks/{id}/gear` (registered).
  - [x] Usage stats: `GET /api/stats/gear/usage`, `GET /api/stats/gear/top` (registered).
  - [x] Register new blueprints in `RuckTracker/app.py` (gear + gear_usage + referral + amazon).

- [x] Click logging
  - [x] RPC `public.log_gear_click(...)` with SECURITY DEFINER and RLS-locked table.
  - [x] Backend helper to compute salted `ip_hash` using `IP_HASH_SALT`.
  - [ ] Ensure logging failures never block redirects (best‑effort).

- [ ] Admin/operations
  - [ ] Secure admin upsert for `retailer_discount_codes`.
  - [x] Feature flag: `GEAR_ENABLED` gates API.
  - [ ] Monitoring: Sentry breadcrumbs/context for referral/PA‑API failures.
  - [x] CODEOWNERS protection for gear tables/endpoints and location code.

- [ ] Discount rules
  - [ ] Precedence/stacking: SKU vs item vs retailer; choose best effective price; avoid double application.

- [ ] Flutter client
  - [x] AffiliateDisclosure widget placed near gear lists/detail and Buy CTAs.
  - [x] “Add Gear” dialog: curated search → claim (own/wishlist + visibility).
  - [x] Gear page: Curated feed + Community‑Owned + Most Wishlisted + your Owned/Wishlist.
  - [ ] Profile sections: Featured, Owned, Wishlist (mirror of Gear page sections).
  - [x] Icon integration: header gear icon replaces profile shortcut on Home.
  - [x] Add Gear screen/route and wire header icon to Gear page.

- [ ] Testing
  - [ ] Unit tests for URL construction, code lookup, claim/unclaim logic.
  - [ ] API tests for comments, search, session gear, and usage stats.
  - [ ] DB tests for constraints, RLS, and views.
  - [ ] Privacy tests: IP hashing present; no raw IP stored.

- [ ] Internationalization
  - [ ] Region/currency fallback; marketplace routing for Amazon tags.

## Test Plan
- Unit tests for repository and BLoC.
- API tests for filters, sorting, permissions, and data integrity.
- Migration tests to ensure indexes and constraints.

## Open Questions
- Do we want public read or auth-only for list endpoints?
- Are there preferred affiliate networks to prioritize?
- Should we support size/color variants (SKU-level attributes) in Phase 1?
