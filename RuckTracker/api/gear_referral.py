import logging
from urllib.parse import urlparse, urlencode, urlunparse, parse_qsl
from flask import Blueprint, request, jsonify, redirect
from sqlalchemy import text

from RuckTracker.extensions import db
from RuckTracker.utils.security import salted_ip_hash

logger = logging.getLogger(__name__)

gear_referral_bp = Blueprint('gear_referral', __name__)


def _merge_query(url: str, extra: dict) -> str:
    parts = urlparse(url)
    qs = dict(parse_qsl(parts.query, keep_blank_values=True))
    qs.update({k: v for k, v in extra.items() if v is not None})
    new_query = urlencode(qs)
    return urlunparse((parts.scheme, parts.netloc, parts.path, parts.params, new_query, parts.fragment))


def _is_allowlisted_host(host: str) -> bool:
    allow = {'amazon.com', 'www.amazon.com', 'goruck.com', 'www.goruck.com'}
    return host.lower() in allow


@gear_referral_bp.route('/gear/ref/<string:retailer>/<string:code>', methods=['GET'])
def gear_referral(retailer: str, code: str):
    """Build a safe referral URL and optionally redirect.

    Query: sku_id (uuid), preview=true|false, region, currency
    """
    sku_id = request.args.get('sku_id')
    preview = request.args.get('preview', 'false').lower() == 'true'
    region = request.args.get('region')
    currency = request.args.get('currency')

    # Fetch base URL from gear_skus; attach coupon code if applicable via param method defaults
    row = db.session.execute(text(
        """
        select s.url, r.referral_url, r.referral_code
        from gear_skus s
        left join gear_referrals r on r.sku_id = s.id and r.is_active = true
        where s.id = :sid and s.retailer = :ret and s.is_active = true
        """
    ), {'sid': sku_id, 'ret': retailer}).mappings().first() if sku_id else None

    base_url = None
    if row and row.get('referral_url'):
        base_url = row['referral_url']
    elif row and row.get('url'):
        base_url = row['url']
    else:
        return jsonify({'error': 'invalid_sku_or_retailer'}), 404

    # Safety: allowlist host
    host = urlparse(base_url).netloc
    if not _is_allowlisted_host(host):
        logger.warning(f"Blocked referral to non-allowlisted host: {host}")
        return jsonify({'error': 'host_not_allowed'}), 400

    # Build target with coupon param when supplied via path param (basic)
    target_url = _merge_query(base_url, {'coupon': code})

    # Best-effort click log (may fail if RLS denies current role)
    try:
        ip = request.headers.get('X-Forwarded-For', request.remote_addr)
        ip_hash = salted_ip_hash((ip or '').split(',')[0].strip())
        # Prefer RPC with SECURITY DEFINER where available
        db.session.execute(text(
            "select public.log_gear_click(:sid, :gid, :ret, :code, :rid, :region, :currency, :url, :ua, :ip_hash)"
        ), {
            'sid': sku_id,
            'gid': None,
            'ret': retailer,
            'code': code,
            'rid': None,
            'region': region,
            'currency': currency,
            'url': target_url,
            'ua': request.headers.get('User-Agent', '')[:512],
            'ip_hash': ip_hash,
        })
        db.session.commit()
    except Exception:
        logger.exception("Referral click log failed (non-blocking)")

    if preview:
        return jsonify({'target_url': target_url}), 200
    return redirect(target_url, code=302)
