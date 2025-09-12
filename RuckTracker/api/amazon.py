import logging
import os
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
    """Proxy for Amazon PA-API search. Returns 501 if keys are not configured.

    Query params: q, category, page
    """
    cfg = _amazon_config()
    if not all([cfg['partner_tag'], cfg['access_key'], cfg['secret_key']]):
        return jsonify({'error': 'amazon_not_configured'}), 501

    # Stub: integrate PA-API request signing and call here
    # To keep this safe in environments without network access, return a minimal payload
    q = (request.args.get('q') or '').strip()
    category = (request.args.get('category') or '').strip()
    logger.info(f"AMAZON SEARCH q={q} category={category}")
    return jsonify({'items': [], 'note': 'PA-API integration pending'}), 200


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
    logger.info(f"AMAZON ITEM asin={asin}")
    return jsonify({'item': None, 'note': 'PA-API integration pending'}), 200
