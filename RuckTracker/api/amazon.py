import logging
import os
import hmac
import hashlib
from datetime import datetime
from urllib.parse import urlparse
import requests
from flask import Blueprint, request, jsonify

logger = logging.getLogger(__name__)

amazon_bp = Blueprint('amazon', __name__)


def _gear_enabled() -> bool:
    return (os.environ.get('GEAR_ENABLED', 'true').lower() == 'true')


def _amazon_config():
    return {
        'partner_tag': os.environ.get('AMAZON_PARTNER_TAG'),
        'access_key': os.environ.get('AMAZON_ACCESS_KEY'),
        'secret_key': os.environ.get('AMAZON_SECRET_KEY'),
        'marketplace': os.environ.get('AMAZON_MARKETPLACE', 'www.amazon.com'),
    }


@amazon_bp.route('/amazon/search', methods=['GET'])
def amazon_search():
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    """Proxy for Amazon PA-API SearchItems. No mock fallback.

    Query params: q, category, page
    """
    cfg = _amazon_config()
    if not all([cfg['partner_tag'], cfg['access_key'], cfg['secret_key']]):
        return jsonify({'error': 'amazon_not_configured'}), 501

    q = (request.args.get('q') or '').strip()
    category = (request.args.get('category') or '').strip() or None
    page = int(request.args.get('page', 1))

    body = {
        'Keywords': q,
        'PartnerTag': cfg['partner_tag'],
        'PartnerType': 'Associates',
        'Marketplace': cfg['marketplace'],
        'ItemPage': page,
    }
    if category:
        body['SearchIndex'] = category

    try:
        data = _paapi_request('SearchItems', body, cfg)
        items = []
        for it in (data.get('SearchResult', {}).get('Items') or []):
            asin = it.get('ASIN')
            title = it.get('ItemInfo', {}).get('Title', {}).get('DisplayValue')
            image = (it.get('Images', {}).get('Primary', {}) or {}).get('Large', {}) or {}
            img_url = image.get('URL')
            url = it.get('DetailPageURL')
            items.append({
                'asin': asin,
                'title': title,
                'image_url': img_url,
                'url': url,
              })
        return jsonify({'items': items}), 200
    except Exception as e:
        logger.exception('AMAZON SEARCH error')
        return jsonify({'error': 'amazon_error', 'message': str(e)}), 502


@amazon_bp.route('/amazon/item', methods=['GET'])
def amazon_item():
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    cfg = _amazon_config()
    if not all([cfg['partner_tag'], cfg['access_key'], cfg['secret_key']]):
        return jsonify({'error': 'amazon_not_configured'}), 501
    asin = (request.args.get('asin') or '').strip()
    if not asin:
        return jsonify({'error': 'asin_required'}), 400
    try:
        body = {
            'ItemIds': [asin],
            'PartnerTag': cfg['partner_tag'],
            'PartnerType': 'Associates',
            'Marketplace': cfg['marketplace'],
            'Resources': [
                'Images.Primary.Large',
                'ItemInfo.Title',
                'Offers.Listings.Price'
            ],
        }
        data = _paapi_request('GetItems', body, cfg)
        items = data.get('ItemsResult', {}).get('Items') or []
        item = items[0] if items else {}
        return jsonify({'item': item}), 200
    except Exception as e:
        logger.exception('AMAZON ITEM error')
        return jsonify({'error': 'amazon_error', 'message': str(e)}), 502


def _amz_region_and_host(marketplace: str):
    mp = marketplace.lower()
    if 'amazon.co.uk' in mp:
        return 'eu-west-1', 'webservices.amazon.co.uk'
    if 'amazon.de' in mp:
        return 'eu-west-1', 'webservices.amazon.de'
    if 'amazon.co.jp' in mp:
        return 'us-west-2', 'webservices.amazon.co.jp'
    if 'amazon.ca' in mp:
        return 'us-east-1', 'webservices.amazon.ca'
    # default US
    return 'us-east-1', 'webservices.amazon.com'


def _sign(key, msg):
    return hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()


def _get_signature_key(key, date_stamp, region_name, service_name):
    k_date = _sign(('AWS4' + key).encode('utf-8'), date_stamp)
    k_region = hmac.new(k_date, region_name.encode('utf-8'), hashlib.sha256).digest()
    k_service = hmac.new(k_region, service_name.encode('utf-8'), hashlib.sha256).digest()
    k_signing = hmac.new(k_service, b'aws4_request', hashlib.sha256).digest()
    return k_signing


def _paapi_request(target: str, body: dict, cfg: dict):
    region, host = _amz_region_and_host(cfg['marketplace'])
    service = 'ProductAdvertisingAPI'
    endpoint = f'https://{host}/paapi5/{target.lower()}'

    amz_target = f'com.amazon.paapi5.v1.ProductAdvertisingAPIv1.{target}'
    content = jsonify(body).get_data(as_text=True)

    t = datetime.utcnow()
    amz_date = t.strftime('%Y%m%dT%H%M%SZ')
    date_stamp = t.strftime('%Y%m%d')

    canonical_uri = f'/paapi5/{target.lower()}'
    canonical_querystring = ''
    canonical_headers = f'content-encoding:amz-1.0\ncontent-type:application/json; charset=utf-8\nhost:{host}\nx-amz-date:{amz_date}\nx-amz-target:{amz_target}\n'
    signed_headers = 'content-encoding;content-type;host;x-amz-date;x-amz-target'
    payload_hash = hashlib.sha256(content.encode('utf-8')).hexdigest()
    canonical_request = f'POST\n{canonical_uri}\n{canonical_querystring}\n{canonical_headers}\n{signed_headers}\n{payload_hash}'

    algorithm = 'AWS4-HMAC-SHA256'
    credential_scope = f'{date_stamp}/{region}/{service}/aws4_request'
    string_to_sign = f'{algorithm}\n{amz_date}\n{credential_scope}\n{hashlib.sha256(canonical_request.encode("utf-8")).hexdigest()}'
    signing_key = _get_signature_key(cfg['secret_key'], date_stamp, region, service)
    signature = hmac.new(signing_key, string_to_sign.encode('utf-8'), hashlib.sha256).hexdigest()

    authorization_header = (
        f'{algorithm} Credential={cfg["access_key"]}/{credential_scope}, '
        f'SignedHeaders={signed_headers}, Signature={signature}'
    )

    headers = {
        'content-encoding': 'amz-1.0',
        'content-type': 'application/json; charset=utf-8',
        'x-amz-target': amz_target,
        'x-amz-date': amz_date,
        'Authorization': authorization_header,
        'host': host,
    }

    resp = requests.post(endpoint, data=content.encode('utf-8'), headers=headers, timeout=15)
    if resp.status_code != 200:
        raise RuntimeError(f'PA-API error {resp.status_code}: {resp.text[:200]}')
    return resp.json()
