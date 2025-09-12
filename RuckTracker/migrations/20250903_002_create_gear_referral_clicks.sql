-- Create gear_referral_clicks table for outbound click logging
-- Mirrors schema in rucking_app/ImplementationDocs/Gear_Feature_Spec.md

CREATE TABLE IF NOT EXISTS gear_referral_clicks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sku_id uuid REFERENCES gear_skus(id),
  gear_item_id uuid REFERENCES gear_items(id),
  retailer text,
  code text,
  referral_id uuid REFERENCES gear_referrals(id),
  user_id uuid,
  clicked_at timestamptz NOT NULL DEFAULT now(),
  region_code text,
  currency_code text,
  target_url text,
  user_agent text,
  ip_hash text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Lookup/analytics indexes
CREATE INDEX IF NOT EXISTS idx_grc_sku_time ON gear_referral_clicks (sku_id, clicked_at DESC);
CREATE INDEX IF NOT EXISTS idx_grc_item_time ON gear_referral_clicks (gear_item_id, clicked_at DESC);
CREATE INDEX IF NOT EXISTS idx_grc_user_time ON gear_referral_clicks (user_id, clicked_at DESC);

-- RLS: Admin/service-only read. Inserts via service role/RPC only.
ALTER TABLE gear_referral_clicks ENABLE ROW LEVEL SECURITY;

-- Deny-by-default: no permissive policies except service role below
DROP POLICY IF EXISTS grc_service_read ON gear_referral_clicks;
CREATE POLICY grc_service_read ON gear_referral_clicks
  FOR SELECT
  USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS grc_service_insert ON gear_referral_clicks;
CREATE POLICY grc_service_insert ON gear_referral_clicks
  FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

-- Note: If we later add an RPC for anonymous logging, we can create a SECURITY DEFINER function
-- that inserts into this table and keep RLS locked down to service/admin roles.
