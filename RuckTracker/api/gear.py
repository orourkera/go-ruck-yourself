import logging
import os
from flask import Blueprint, request, jsonify, g
from sqlalchemy import text

from RuckTracker.extensions import db
from RuckTracker.supabase_client import get_supabase_client
from RuckTracker.utils.auth_helper import get_current_user_id

logger = logging.getLogger(__name__)

gear_bp = Blueprint('gear', __name__)


def _gear_enabled() -> bool:
    return (os.environ.get('GEAR_ENABLED', 'true').lower() == 'true')


@gear_bp.route('/gear/search', methods=['GET'])
def search_gear():
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    """Search curated gear items by name/brand/model and optional category slug.

    Query params: q, category, limit, offset
    """
    q = (request.args.get('q') or '').strip()
    category = (request.args.get('category') or '').strip()
    limit = min(int(request.args.get('limit', 20)), 50)
    offset = int(request.args.get('offset', 0))

    clauses = ["gi.is_active = true"]
    params = {'limit': limit, 'offset': offset}
    if q:
        clauses.append("(gi.name ilike :q or coalesce(gi.brand,'') ilike :q or coalesce(gi.model,'') ilike :q)")
        params['q'] = f"%{q}%"
    if category:
        clauses.append("gc.slug = :cat")
        params['cat'] = category

    where = " where " + " and ".join(clauses) if clauses else ""
    sql = text(
        f"""
        select gi.id, gi.name, gi.brand, gi.model, gi.default_image_url, gc.slug as category_slug
        from gear_items gi
        left join gear_categories gc on gi.category_id = gc.id
        {where}
        order by gi.updated_at desc nulls last, gi.created_at desc
        limit :limit offset :offset
        """
    )
    rows = db.session.execute(sql, params).mappings().all()
    return jsonify({'items': list(rows)}), 200


@gear_bp.route('/gear/items', methods=['GET'])
def list_gear_items():
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    """List curated gear item summaries from view_gear_item_summary.

    Query params: q, category, brand, sort, limit, offset
    """
    q = (request.args.get('q') or '').strip()
    category = (request.args.get('category') or '').strip()
    brand = (request.args.get('brand') or '').strip()
    sort = (request.args.get('sort') or 'new').lower()
    limit = min(int(request.args.get('limit', 20)), 50)
    offset = int(request.args.get('offset', 0))

    clauses = []
    params = {'limit': limit, 'offset': offset}
    if q:
        clauses.append("(name ilike :q or coalesce(brand,'') ilike :q or coalesce(model,'') ilike :q)")
        params['q'] = f"%{q}%"
    if category:
        clauses.append("category_slug = :cat")
        params['cat'] = category
    if brand:
        clauses.append("brand ilike :brand")
        params['brand'] = f"%{brand}%"

    where = (" where " + " and ".join(clauses)) if clauses else ""
    order_by = {
        'price_low': 'price_min_minor asc nulls last',
        'price_high': 'price_max_minor desc nulls last',
        'rating': 'price_min_minor asc nulls last',  # placeholder without ratings agg
        'new': 'gear_item_id desc',
        'popularity': 'price_min_minor asc nulls last',  # placeholder
    }.get(sort, 'gear_item_id desc')

    sql = text(
        f"""
        select gear_item_id as id, name, brand, model, default_image_url, category_slug,
               price_min_minor, price_avg_minor, price_max_minor
        from view_gear_item_summary
        {where}
        order by {order_by}
        limit :limit offset :offset
        """
    )
    rows = db.session.execute(sql, params).mappings().all()
    return jsonify({'items': list(rows)}), 200


@gear_bp.route('/gear/items/<string:item_id>', methods=['GET'])
def get_gear_item(item_id: str):
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404

    # Fetch main item
    item = db.session.execute(text(
        """
        select gi.id, gi.name, gi.brand, gi.model, gi.description, gi.default_image_url,
               gc.slug as category_slug
        from gear_items gi
        left join gear_categories gc on gi.category_id = gc.id
        where gi.id = :id and gi.is_active = true
        """
    ), {'id': item_id}).mappings().first()
    if not item:
        return jsonify({'error': 'not_found'}), 404

    # Images
    images = db.session.execute(text(
        "select image_url, sort_order from gear_images where gear_item_id = :id order by sort_order nulls last, created_at asc"
    ), {'id': item_id}).mappings().all()

    # Active SKUs with latest/effective prices and discount metadata
    skus = db.session.execute(text(
        """
        select s.id as sku_id, s.retailer, s.sku, s.url,
               e.base_minor, e.effective_minor, e.discount_id,
               d.name as discount_name, d.percent as discount_percent,
               d.fixed_minor as discount_fixed_minor, d.coupon_code,
               r.referral_code
        from gear_skus s
        left join view_gear_effective_latest_prices e on e.sku_id = s.id
        left join gear_discounts d on d.id = e.discount_id
        left join gear_referrals r on r.sku_id = s.id and r.is_active = true
        where s.gear_item_id = :id and s.is_active = true
        order by s.created_at asc
        """
    ), {'id': item_id}).mappings().all()

    # Comment summary
    agg = db.session.execute(text(
        "select avg(rating)::numeric(3,2) as avg_rating, count(*) as comment_count from gear_comments where gear_item_id = :id and rating is not null"
    ), {'id': item_id}).mappings().first()

    return jsonify({
        'item': dict(item),
        'images': list(images),
        'skus': list(skus),
        'rating': {
            'avg': agg['avg_rating'] if agg and agg['avg_rating'] is not None else None,
            'count': agg['comment_count'] if agg else 0,
        }
    }), 200


@gear_bp.route('/gear/claim', methods=['POST'])
def claim_gear():
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    """Claim ownership or save to wishlist.

    Body accepts either:
      { gear_item_id: uuid, relation: 'owned'|'saved', visibility?: 'public'|'followers'|'private' }
    or
      { source: 'amazon'|'shopify'|'other', external_id: string, title?, image_url?, url?, retailer?, category_slug?, relation, visibility? }
    """
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({'error': 'Authentication required'}), 401

    data = request.get_json(silent=True) or {}
    relation = (data.get('relation') or 'owned').lower()
    visibility = (data.get('visibility') or 'public').lower()
    if relation not in {'owned', 'saved'}:
        return jsonify({'error': 'invalid relation'}), 400
    if visibility not in {'public', 'followers', 'private'}:
        return jsonify({'error': 'invalid visibility'}), 400

    gear_item_id = data.get('gear_item_id')
    source = (data.get('source') or '').lower()
    external_id = data.get('external_id')
    external_product_id = None

    try:
        with db.session.begin():
            if not gear_item_id:
                # Upsert external product
                if not source or not external_id:
                    return jsonify({'error': 'gear_item_id or (source, external_id) required'}), 400
                ep = db.session.execute(text(
                    """
                    insert into external_products (source, external_id, url, retailer, title, image_url, category_slug)
                    values (:source, :external_id, :url, :retailer, :title, :image_url, :category_slug)
                    on conflict (source, external_id)
                    do update set
                      url = coalesce(excluded.url, external_products.url),
                      retailer = coalesce(excluded.retailer, external_products.retailer),
                      title = coalesce(excluded.title, external_products.title),
                      image_url = coalesce(excluded.image_url, external_products.image_url),
                      category_slug = coalesce(excluded.category_slug, external_products.category_slug)
                    returning id
                    """
                ), {
                    'source': source,
                    'external_id': external_id,
                    'url': data.get('url'),
                    'retailer': data.get('retailer'),
                    'title': data.get('title'),
                    'image_url': data.get('image_url'),
                    'category_slug': data.get('category_slug'),
                }).first()
                external_product_id = ep[0] if ep else None

            # Insert claim (unique on user + ref_key + relation)
            db.session.execute(text(
                """
                insert into user_gear (user_id, gear_item_id, external_product_id, relation, visibility)
                values (:uid, :gear_item_id, :external_product_id, :relation, :visibility)
                on conflict (user_id, ref_key, relation) do update set visibility = excluded.visibility
                """
            ), {
                'uid': user_id,
                'gear_item_id': gear_item_id,
                'external_product_id': external_product_id,
                'relation': relation,
                'visibility': visibility,
            })
        return jsonify({'ok': True}), 200
    except Exception as e:
        logger.exception("Failed to claim gear")
        return jsonify({'error': 'internal_error'}), 500


@gear_bp.route('/gear/unclaim', methods=['POST'])
def unclaim_gear():
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({'error': 'Authentication required'}), 401
    data = request.get_json(silent=True) or {}
    relation = (data.get('relation') or 'owned').lower()
    if relation not in {'owned', 'saved'}:
        return jsonify({'error': 'invalid relation'}), 400
    gear_item_id = data.get('gear_item_id')
    external_product_id = data.get('external_product_id')
    if not gear_item_id and not external_product_id:
        return jsonify({'error': 'gear_item_id or external_product_id required'}), 400

    try:
        with db.session.begin():
            db.session.execute(text(
                """
                delete from user_gear
                where user_id = :uid and relation = :relation
                  and (coalesce(gear_item_id::text, external_product_id::text)) = coalesce(:gi::text, :ep::text)
                """
            ), {'uid': user_id, 'relation': relation, 'gi': gear_item_id, 'ep': external_product_id})
        return jsonify({'ok': True}), 200
    except Exception:
        logger.exception("Failed to unclaim gear")
        return jsonify({'error': 'internal_error'}), 500


@gear_bp.route('/gear/profile/<string:user_id>', methods=['GET'])
def get_profile_gear(user_id: str):
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    """Return public gear for a profile: owned and wishlist (saved)."""
    owned = db.session.execute(text(
        "select * from view_owned_gear_public where user_id = :uid order by created_at desc"
    ), {'uid': user_id}).mappings().all()
    saved = db.session.execute(text(
        "select * from view_saved_gear_public where user_id = :uid order by created_at desc"
    ), {'uid': user_id}).mappings().all()
    return jsonify({'user_id': user_id, 'owned': list(owned), 'saved': list(saved)}), 200


@gear_bp.route('/gear/items/<string:item_id>/comments', methods=['GET', 'POST'])
def curated_item_comments(item_id: str):
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    if request.method == 'GET':
        rows = db.session.execute(text(
            """
            select gc.id, gc.user_id, gc.rating, gc.title, gc.body, gc.ownership_claimed, gc.created_at
            from gear_comments gc where gc.gear_item_id = :id order by gc.created_at desc
            """
        ), {'id': item_id}).mappings().all()
        return jsonify({'items': list(rows)}), 200

    # POST
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({'error': 'Authentication required'}), 401
    data = request.get_json(silent=True) or {}
    try:
        with db.session.begin():
            db.session.execute(text(
                """
                insert into gear_comments (user_id, gear_item_id, rating, title, body, ownership_claimed)
                values (:uid, :gid, :rating, :title, :body, :own)
                """
            ), {
                'uid': user_id,
                'gid': item_id,
                'rating': data.get('rating'),
                'title': data.get('title'),
                'body': data.get('body'),
                'own': bool(data.get('ownership_claimed', False)),
            })
        return jsonify({'ok': True}), 201
    except Exception:
        logger.exception("Failed to post comment")
        return jsonify({'error': 'internal_error'}), 500


@gear_bp.route('/gear/external/<string:external_id>/comments', methods=['GET', 'POST'])
def external_item_comments(external_id: str):
    if not _gear_enabled():
        return jsonify({'error': 'gear_disabled'}), 404
    if request.method == 'GET':
        rows = db.session.execute(text(
            """
            select gc.id, gc.user_id, gc.rating, gc.title, gc.body, gc.ownership_claimed, gc.created_at
            from gear_comments gc where gc.external_product_id = :id order by gc.created_at desc
            """
        ), {'id': external_id}).mappings().all()
        return jsonify({'items': list(rows)}), 200

    user_id = get_current_user_id()
    if not user_id:
        return jsonify({'error': 'Authentication required'}), 401
    data = request.get_json(silent=True) or {}
    try:
        with db.session.begin():
            db.session.execute(text(
                """
                insert into gear_comments (user_id, external_product_id, rating, title, body, ownership_claimed)
                values (:uid, :eid, :rating, :title, :body, :own)
                """
            ), {
                'uid': user_id,
                'eid': external_id,
                'rating': data.get('rating'),
                'title': data.get('title'),
                'body': data.get('body'),
                'own': bool(data.get('ownership_claimed', False)),
            })
        return jsonify({'ok': True}), 201
    except Exception:
        logger.exception("Failed to post comment (external)")
        return jsonify({'error': 'internal_error'}), 500
