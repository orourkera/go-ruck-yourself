-- Create retailer_discount_codes table for retailer/manufacturer-level promo codes
-- Follows schema from rucking_app/ImplementationDocs/Gear_Feature_Spec.md

CREATE TABLE IF NOT EXISTS retailer_discount_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  retailer text NOT NULL,               -- must match gear_skus.retailer
  code text NOT NULL,
  percent numeric(5,2),                 -- one of percent or fixed_minor
  fixed_minor bigint,
  region_code text,                     -- optional targeting by region (e.g., US, UK)
  currency_code text,                   -- optional targeting by currency
  apply_method text NOT NULL DEFAULT 'param', -- 'param' | 'display_only' | 'path' | 'none'
  apply_param_name text NOT NULL DEFAULT 'coupon',
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- ensure exactly one of percent or fixed_minor is provided
  CHECK ((percent IS NOT NULL) <> (fixed_minor IS NOT NULL)),
  -- restrict allowed application methods for safety
  CHECK (apply_method IN ('param','display_only','path','none'))
);

-- Uniqueness across retailer, code, and region (NULL treated as 'ALL')
CREATE UNIQUE INDEX IF NOT EXISTS idx_rdc_retailer_code_region
  ON retailer_discount_codes (retailer, code, COALESCE(region_code, 'ALL'));

-- Helpful lookup and filtering indexes
CREATE INDEX IF NOT EXISTS idx_rdc_retailer ON retailer_discount_codes (retailer);
CREATE INDEX IF NOT EXISTS idx_rdc_code ON retailer_discount_codes (code);
CREATE INDEX IF NOT EXISTS idx_rdc_valid_from ON retailer_discount_codes (valid_from);
CREATE INDEX IF NOT EXISTS idx_rdc_valid_until ON retailer_discount_codes (valid_until);
CREATE INDEX IF NOT EXISTS idx_rdc_is_active ON retailer_discount_codes (is_active);
